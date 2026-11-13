import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/role_choice_page.dart';
import '../../pages/shared/settings.dart';
import '../../services/account_mode_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/staff_workspace_shell.dart';
import '../../widgets/workspace_navigation.dart';

/// Organisation-scoped administration for internal and outsourced laboratories.
class HospitalLabAdminPage extends StatefulWidget {
  const HospitalLabAdminPage({super.key});
  @override
  State<HospitalLabAdminPage> createState() => _HospitalLabAdminPageState();
}

class _HospitalLabAdminPageState extends State<HospitalLabAdminPage>
    with WorkspaceNavigation<HospitalLabAdminPage> {
  int _activeSection = 0;
  final _client = Supabase.instance.client;
  final _search = TextEditingController();
  bool _loading = true,
      _saving = false,
      _searching = false,
      _hasSearched = false;
  bool _canOpenPatient = false, _assignVerifier = false;
  int _searchRevision = 0;
  String? _error, _searchError;
  Map<String, dynamic>? _data, _selected;
  List<Map<String, dynamic>> _accounts = [];
  String _teamFilter = 'active';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchRevision++;
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) {
      throw const FormatException('Invalid laboratory account list.');
    }
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  String _name(Map<String, dynamic> row) {
    final full = '${row['first_name'] ?? ''} ${row['surname'] ?? ''}'.trim();
    return row['name']?.toString() ??
        (full.isEmpty ? row['email']?.toString() ?? 'Account' : full);
  }

  String _clean(Object error) => error is PostgrestException
      ? error.message
      : error.toString().replaceFirst('Exception: ', '');
  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _client.rpc('corvia_lab_admin_settings_v2');
      if (result is! Map) {
        throw const FormatException(
            'Invalid laboratory administration response.');
      }
      final data = Map<String, dynamic>.from(result);
      _rows(data['workers']);
      _rows(data['recent_activity']);
      var patient = false;
      try {
        patient = (await AccountModeService.current()).hasPatientAccess;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _data = data;
          _canOpenPatient = patient;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _clean(error);
          _loading = false;
        });
      }
    }
  }

  void _queryChanged(String _) {
    _searchRevision++;
    setState(() {
      _accounts = [];
      _selected = null;
      _hasSearched = false;
      _searchError = null;
      _searching = false;
    });
  }

  Future<void> _searchAccounts() async {
    final query = _search.text.trim();
    if (query.length < 3 || _saving || _searching) return;
    final revision = ++_searchRevision;
    setState(() {
      _searching = true;
      _searchError = null;
      _selected = null;
      _accounts = [];
      _hasSearched = false;
    });
    try {
      final result = await _client.rpc(
          'corvia_hospital_lab_admin_search_accounts_json',
          params: {'p_search': query, 'p_limit': 25});
      final rows = _rows(result);
      if (mounted && revision == _searchRevision) {
        setState(() {
          final existingIds = _rows(_data?['workers'] ?? [])
              .map((worker) => worker['profile_id'])
              .toSet();
          _accounts = rows
              .where((account) => !existingIds.contains(account['profile_id']))
              .toList();
          _hasSearched = true;
        });
      }
    } catch (error) {
      if (mounted && revision == _searchRevision) {
        setState(() => _searchError = _clean(error));
      }
    } finally {
      if (mounted && revision == _searchRevision) {
        setState(() => _searching = false);
      }
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) =>
            AlertDialog(title: Text(title), content: Text(message), actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm')),
        ]),
      ) ??
      false;

  Future<void> _assign() async {
    final account = _selected;
    if (account == null || _saving) return;
    final role = _assignVerifier ? 'Verifier' : 'Technician';
    if (!await _confirm('Assign laboratory role?',
        'Assign ${_name(account)} as a $role in ${_data?['lab_name']}? A verifier cannot perform testing.')) {
      return;
    }
    if (!mounted || _saving) return;
    setState(() => _saving = true);
    try {
      final result =
          await _client.rpc('corvia_hospital_lab_admin_link_worker', params: {
        'p_profile_id': account['profile_id'],
        'p_can_verify_results': _assignVerifier,
      });
      if (result is! Map || result['profile_id'] != account['profile_id']) {
        throw const FormatException('Role assignment was not confirmed.');
      }
      _search.clear();
      _queryChanged('');
      await _load();
      _message('$role role assigned to ${_name(account)}.');
    } catch (error) {
      _message(_clean(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _update(Map<String, dynamic> worker,
      {bool? active, bool? verifier}) async {
    if (_saving) return;
    final nextActive = active ?? worker['is_active'] != false;
    final nextVerifier = verifier ?? worker['can_verify_results'] == true;
    final action = !nextActive
        ? 'Deactivate'
        : active == true
            ? 'Reactivate'
            : 'Change role for';
    if (!await _confirm('Update laboratory access?',
        '$action ${_name(worker)}${nextActive ? ' as a ${nextVerifier ? 'Verifier' : 'Technician'}' : ''}?')) {
      return;
    }
    if (!mounted || _saving) return;
    setState(() => _saving = true);
    try {
      final result =
          await _client.rpc('corvia_hospital_lab_admin_update_worker', params: {
        'p_profile_id': worker['profile_id'],
        'p_is_active': nextActive,
        'p_can_verify_results': nextVerifier,
      });
      if (result is! Map || result['profile_id'] != worker['profile_id']) {
        throw const FormatException('Access update was not confirmed.');
      }
      await _load();
      _message('Laboratory access updated.');
    } catch (error) {
      _message(_clean(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _client.auth.signOut();
      SettingsService.instance.sessionUnlocked = false;
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      _message('Sign out failed: ${_clean(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _scroll(List<Widget> children) => RefreshIndicator(
        onRefresh: _saving ? () async {} : _load,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ]),
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider),
      );

  Widget _heroCard() {
    final private = _data!['lab_type'] == 'private';
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [CorviaColors.accentDark, CorviaColors.accent],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(children: [
        const CircleAvatar(
          radius: 28,
          backgroundColor: Colors.white,
          child: Icon(Icons.biotech_rounded, size: 30, color: Colors.teal),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _data!['lab_name']?.toString() ?? 'Laboratory',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                private
                    ? 'Outsourced laboratory organisation'
                    : 'Internal hospital laboratory',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
        const Icon(Icons.verified_user_rounded, color: Colors.white),
      ]),
    );
  }

  Widget _statTile(String label, int value, IconData icon, Color color) =>
      Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 14),
            Text('$value',
                style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: context.cTextSecondary, fontSize: 12)),
          ],
        ),
      );

  Widget _rolePill(bool verifier, {bool inactive = false}) {
    final color = inactive
        ? context.cTextMuted
        : verifier
            ? const Color(0xFF7C3AED)
            : CorviaColors.success;
    final label = inactive
        ? 'Inactive'
        : verifier
            ? 'Verifier'
            : 'Technician';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _avatar(Map<String, dynamic> row) {
    final parts = _name(row)
        .split(RegExp(r'[\s@.]+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      backgroundColor: CorviaColors.accent.withValues(alpha: 0.12),
      child: Text(parts.isEmpty ? '?' : parts,
          style: TextStyle(
              color: context.cAccentReadable, fontWeight: FontWeight.bold)),
    );
  }

  Widget _section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(color: context.cTextSecondary)),
        ]),
      );
  Widget _overview(List<Map<String, dynamic>> workers) {
    final active = workers.where((w) => w['is_active'] != false).toList();
    return _scroll([
      _heroCard(),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _statTile(
            'Technicians',
            active.where((w) => w['can_verify_results'] != true).length,
            Icons.science_outlined,
            CorviaColors.success),
        _statTile(
            'Verifiers',
            active.where((w) => w['can_verify_results'] == true).length,
            Icons.fact_check_outlined,
            const Color(0xFF7C3AED)),
        _statTile('Inactive accounts', workers.length - active.length,
            Icons.person_off_outlined, CorviaColors.warning),
      ]),
      const SizedBox(height: 24),
      _section('Lab team', 'People with active access to this laboratory.'),
      if (active.isEmpty)
        const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('No active technicians or verifiers yet.')),
      for (final worker in active)
        Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: _cardDecoration(),
            child: ListTile(
                leading: _avatar(worker),
                title: Text(_name(worker),
                    style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(worker['email']?.toString() ?? '',
                    style: TextStyle(color: context.cTextSecondary)),
                trailing: _rolePill(worker['can_verify_results'] == true))),
      const SizedBox(height: 20),
      Container(
          decoration: _cardDecoration(),
          child: const Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your role: Laboratory Admin',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                        'Manage team membership and assign either Technician or Verifier. Administrators cannot perform testing, verify results or release results.'),
                    SizedBox(height: 12),
                    Text(
                        'Every result requires verification. The ordering doctor decides whether it then goes to the patient automatically or awaits their review.'),
                  ]))),
    ]);
  }

  Widget _team(List<Map<String, dynamic>> workers) {
    final filtered = workers.where((w) {
      if (_teamFilter == 'inactive') return w['is_active'] == false;
      if (w['is_active'] == false) return false;
      if (_teamFilter == 'technician') return w['can_verify_results'] != true;
      if (_teamFilter == 'verifier') return w['can_verify_results'] == true;
      return true;
    }).toList();
    return _scroll([
      _section('Team & roles',
          'Each account has one laboratory role. Changes require confirmation.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in {
          'active': 'Active',
          'technician': 'Technicians',
          'verifier': 'Verifiers',
          'inactive': 'Inactive'
        }.entries)
          ChoiceChip(
              label: Text(entry.value),
              selected: _teamFilter == entry.key,
              onSelected: _saving
                  ? null
                  : (_) => setState(() => _teamFilter = entry.key)),
      ]),
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No accounts in this group.')),
      for (final worker in filtered)
        Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: _cardDecoration(),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _avatar(worker),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_name(worker),
                                  style: TextStyle(
                                      color: context.cTextPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              SelectableText(worker['email']?.toString() ?? '',
                                  style:
                                      TextStyle(color: context.cTextSecondary)),
                            ],
                          ),
                        ),
                        _rolePill(worker['can_verify_results'] == true,
                            inactive: worker['is_active'] == false),
                      ]),
                      const SizedBox(height: 14),
                      SegmentedButton<bool>(
                        key: ValueKey(
                            '${worker['profile_id']}:${worker['can_verify_results']}:${worker['is_active']}'),
                        segments: const [
                          ButtonSegment(
                              value: false,
                              icon: Icon(Icons.science_outlined),
                              label: Text('Technician')),
                          ButtonSegment(
                              value: true,
                              icon: Icon(Icons.fact_check_outlined),
                              label: Text('Verifier')),
                        ],
                        selected: {worker['can_verify_results'] == true},
                        onSelectionChanged:
                            _saving || worker['is_active'] == false
                                ? null
                                : (value) {
                                    if (value.isNotEmpty &&
                                        value.first !=
                                            (worker['can_verify_results'] ==
                                                true)) {
                                      _update(worker, verifier: value.first);
                                    }
                                  },
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _update(worker,
                                  active: worker['is_active'] == false),
                          icon: Icon(worker['is_active'] == false
                              ? Icons.person_add_alt
                              : Icons.person_off_outlined),
                          label: Text(worker['is_active'] == false
                              ? 'Reactivate account'
                              : 'Deactivate access')),
                    ]))),
    ]);
  }

  Widget _addAccount() => _scroll([
        _section('Add account',
            'Search using part of a name or email. Accounts already in your lab are managed under Team & roles.'),
        TextField(
            controller: _search,
            enabled: !_saving,
            onChanged: _queryChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchAccounts(),
            decoration: InputDecoration(
                labelText: 'Name or email',
                hintText: 'Part of a name or email (at least 3 characters)',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _saving
                            ? null
                            : () {
                                _search.clear();
                                _queryChanged('');
                              },
                        icon: const Icon(Icons.clear)))),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _saving || _searching || _search.text.trim().length < 3
                ? null
                : _searchAccounts,
            icon: const Icon(Icons.search),
            label: const Text('Search accounts')),
        const SizedBox(height: 16),
        if (_searching)
          const LinearProgressIndicator()
        else if (_searchError != null)
          Text(_searchError!, style: TextStyle(color: CorviaColors.danger))
        else if (!_hasSearched)
          const Text('Ready to search. Results appear after you search.')
        else if (_accounts.isEmpty)
          const Text(
              'No eligible accounts found. Try a more specific name or email.'),
        for (final account in _accounts)
          Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: _cardDecoration().copyWith(
                  color: _selected?['profile_id'] == account['profile_id']
                      ? context.cAccentReadable.withValues(alpha: 0.1)
                      : context.cBgSecondary),
              child: ListTile(
                  leading: _avatar(account),
                  title: Text(_name(account)),
                  subtitle: Text(account['email']?.toString() ?? ''),
                  trailing: _selected?['profile_id'] == account['profile_id']
                      ? const Icon(Icons.check_circle_outline)
                      : null,
                  onTap: _saving || _searching
                      ? null
                      : () => setState(() {
                            _selected = account;
                            _assignVerifier = false;
                          }))),
        if (_selected != null) ...[
          const SizedBox(height: 16),
          _section('Assign ${_name(_selected!)}',
              'Technicians perform testing. Verifiers only review and approve or return submissions.'),
          DropdownButtonFormField<bool>(
              key: ValueKey(_selected!['profile_id']),
              initialValue: _assignVerifier,
              decoration: const InputDecoration(
                  labelText: 'Laboratory role', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: false, child: Text('Technician')),
                DropdownMenuItem(value: true, child: Text('Verifier'))
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _assignVerifier = value);
                      }
                    }),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _saving ? null : _assign,
              icon: const Icon(Icons.person_add_alt),
              label: Text(_saving ? 'Assigning...' : 'Assign role')),
        ],
      ]);
  Widget _activity(List<Map<String, dynamic>> activity) => _scroll([
        _section('Access activity',
            'Recent role assignments, access changes and the person who made each change.'),
        if (activity.isEmpty) const Text('No access changes recorded yet.'),
        for (final event in activity)
          Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: _cardDecoration(),
              child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(event['target_name']?.toString() ?? 'Account'),
                  subtitle: Text(
                      '${event['action']?.toString().replaceAll('_', ' ')}\n${event['actor_name'] ?? 'Administrator'} · ${_date(event['created_at'])}'),
                  isThreeLine: true)),
      ]);
  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Time unavailable';
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openSettings() async {
    if (_data == null) {
      await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
      return;
    }
    await pushWorkspace<void>(
        MaterialPageRoute<void>(
            builder: (_) => const SettingsPage(showAppBar: false)),
        label: 'Settings');
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      IconButton(
          tooltip: 'Refresh',
          onPressed: _saving || _loading ? null : _load,
          icon: const Icon(Icons.refresh)),
      if (_canOpenPatient)
        IconButton(
            tooltip: 'Switch Dashboard',
            onPressed: _saving
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const RoleChoicePage())),
            icon: const Icon(Icons.swap_horiz)),
      IconButton(
          tooltip: 'Options',
          onPressed: _saving ? null : _openSettings,
          icon: const Icon(Icons.settings_outlined)),
      IconButton(
          tooltip: 'Sign out',
          onPressed: _saving ? null : _signOut,
          icon: const Icon(Icons.logout)),
    ];
    if (_data == null) {
      return Scaffold(
        appBar:
            AppBar(title: const Text('Lab Administration'), actions: actions),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error ?? 'Laboratory access unavailable.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _load, child: const Text('Retry')),
                    ]))),
      );
    }
    final workers = _rows(_data!['workers']);
    const sections = [
      ('Overview', Icons.dashboard_rounded),
      ('Team & roles', Icons.groups_rounded),
      ('Add account', Icons.person_add_alt_1_rounded),
      ('Activity', Icons.history_rounded),
    ];
    return StaffWorkspaceShell(
      workspaceName: 'Laboratory Administration',
      breadcrumb: 'Lab Admin',
      pageTitle: workspaceTitle ?? sections[_activeSection].$1,
      subtitle: _data!['lab_name']?.toString(),
      onSignOut: _saving ? null : _signOut,
      headerActions: [
        if (workspaceCanPop)
          workspaceBackButton
        else
          OutlinedButton.icon(
            onPressed: _saving || _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
      ],
      items: [
        for (var i = 0; i < sections.length; i++)
          StaffShellItem(
            label: sections[i].$1,
            icon: sections[i].$2,
            selected: !workspaceCanPop && _activeSection == i,
            onTap: () {
              workspaceHome();
              setState(() => _activeSection = i);
            },
          ),
        if (_canOpenPatient)
          StaffShellItem(
            label: 'Switch to patient',
            icon: Icons.swap_horiz_rounded,
            onTap: _saving
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const RoleChoicePage())),
          ),
        StaffShellItem(
          label: 'Settings',
          selected: workspaceSelection == 'Settings',
          icon: Icons.settings_rounded,
          onTap: _saving ? null : _openSettings,
        ),
      ],
      body: workspaceBody(Column(children: [
        if (_loading || _saving) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child:
                  Text(_error!, style: TextStyle(color: CorviaColors.danger))),
        Expanded(
            child: switch (_activeSection) {
          1 => _team(workers),
          2 => _addAccount(),
          3 => _activity(_rows(_data!['recent_activity'])),
          _ => _overview(workers),
        }),
      ])),
    );
  }
}
