import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalLabGovernancePage extends StatefulWidget {
  const HospitalLabGovernancePage({super.key});

  @override
  State<HospitalLabGovernancePage> createState() =>
      _HospitalLabGovernancePageState();
}

class _HospitalLabGovernancePageState extends State<HospitalLabGovernancePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _savingLabId;
  String? _error;
  _LabGovernance? _governance;
  List<Map<String, dynamic>> _outsourcedLabs = [];
  String _providerFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response = await _supabase.rpc('corvia_hospital_lab_governance_v3');
      final data = _map(response);
      final internal = data['internal_lab'];
      final outsourced = data['outsourced_labs'];
      if (internal is! Map || outsourced is! List) {
        throw const FormatException(
            'Laboratory governance returned invalid data.');
      }
      if (!mounted) return;
      setState(() {
        _governance =
            _LabGovernance.fromJson(Map<String, dynamic>.from(internal));
        _outsourcedLabs = outsourced
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _cleanError(error);
      });
    }
  }

  Future<void> _setProvider(Map<String, dynamic> provider, bool enabled) async {
    final id = provider['lab_organization_id']?.toString() ?? '';
    if (id.isEmpty || _savingLabId != null) return;
    final name = provider['lab_name']?.toString() ?? 'this laboratory';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(enabled
            ? 'Connect outsourced laboratory?'
            : 'Stop new laboratory orders?'),
        content: Text(enabled
            ? 'Allow doctors at this hospital to send new laboratory orders to $name?'
            : 'Remove $name from the choices for new orders? Existing orders and results will not be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(enabled ? 'Connect laboratory' : 'Disconnect')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingLabId = id);
    try {
      final response = await _supabase.rpc(
        'corvia_hospital_set_outsourced_lab',
        params: {'p_lab_organization_id': id, 'p_enabled': enabled},
      );
      if (response is! Map ||
          response['lab_organization_id']?.toString() != id ||
          response['is_connected'] != enabled) {
        throw const FormatException(
            'The laboratory connection was not confirmed.');
      }
      await _load();
      _showMessage(enabled
          ? '$name is available for new orders.'
          : '$name was removed from new laboratory orders.');
    } catch (error) {
      _showMessage(_cleanError(error));
    } finally {
      if (mounted) setState(() => _savingLabId = null);
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw Exception('Laboratory settings returned invalid data.');
  }

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', '')
      .replaceAll(')', '');

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<Widget> _providerCards() {
    final query = _providerFilter.trim().toLowerCase();
    final providers = _outsourcedLabs.where((provider) {
      if (query.isEmpty) return true;
      return (provider['lab_name']?.toString().toLowerCase() ?? '')
          .contains(query);
    }).toList();
    if (_outsourcedLabs.isEmpty) {
      return const [
        _ProviderEmptyState(
          title: 'No outsourced laboratories available',
          body:
              'An outsourced laboratory organisation must exist before it can be connected.',
        )
      ];
    }
    if (providers.isEmpty) {
      return const [
        _ProviderEmptyState(
          title: 'No matching laboratories',
          body: 'Try a different provider name.',
        )
      ];
    }
    return providers.map(_providerCard).toList();
  }

  Widget _providerCard(Map<String, dynamic> provider) {
    final id = provider['lab_organization_id']?.toString() ?? '';
    final connected = provider['is_connected'] == true;
    final active = provider['is_active'] != false;
    final saving = _savingLabId == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: connected
              ? context.cAccentReadable.withValues(alpha: 0.45)
              : context.cDivider,
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: (connected ? CorviaColors.accent : context.cTextMuted)
                .withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.local_shipping_outlined,
              color:
                  connected ? context.cAccentReadable : context.cTextSecondary),
        ),
        const SizedBox(width: 13),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(provider['lab_name']?.toString() ?? 'Outsourced laboratory',
                style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              active
                  ? 'Outsourced laboratory provider'
                  : 'Provider is inactive',
              style: TextStyle(color: context.cTextSecondary),
            ),
            const SizedBox(height: 9),
            _ProviderStatePill(connected: connected),
          ]),
        ),
        const SizedBox(width: 10),
        if (saving)
          const Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          Switch.adaptive(
            value: connected,
            onChanged: active && _savingLabId == null
                ? (value) => _setProvider(provider, value)
                : null,
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: CorviaColors.accent));
    }
    if (_error != null) {
      return _GovernanceError(message: _error!, onRetry: _load);
    }

    final governance = _governance;
    if (governance == null) {
      return _GovernanceError(
          message: 'Laboratory settings are unavailable.', onRetry: _load);
    }

    return RefreshIndicator(
      color: context.cAccentReadable,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Laboratory Governance',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Manage the internal laboratory and the outsourced providers available to your doctors. Clinical laboratory work stays with technicians and verifiers.',
            style: TextStyle(color: context.cTextSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          _OverviewCard(governance: governance),
          const SizedBox(height: 16),
          _LabTeamExpansion(governance: governance),
          const SizedBox(height: 20),
          Text('Outsourced laboratory network',
              style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(
              'Connected providers appear when doctors choose where to send a new lab order.',
              style: TextStyle(color: context.cTextSecondary)),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _providerFilter = value),
            decoration: const InputDecoration(
              labelText: 'Filter outsourced laboratories',
              hintText: 'Search by provider name',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ..._providerCards(),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.shield_outlined,
            title: 'Administrative boundary',
            body:
                'Hospital Admins and Lab Admins cannot receive specimens, enter results, verify results or release results.',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LabGovernance {
  const _LabGovernance({
    required this.labName,
    required this.isActive,
    required this.activeTechnicians,
    required this.activeVerifiers,
    required this.activeAdmins,
    required this.teamMembers,
  });

  final String labName;
  final bool isActive;
  final int activeTechnicians;
  final int activeVerifiers;
  final int activeAdmins;
  final List<_LabTeamMember> teamMembers;

  factory _LabGovernance.fromJson(Map<String, dynamic> json) => _LabGovernance(
        labName: json['lab_name']?.toString().trim().isEmpty ?? true
            ? 'Hospital laboratory'
            : json['lab_name'].toString().trim(),
        isActive: json['is_active'] != false,
        activeTechnicians: (json['active_technicians'] as num?)?.toInt() ?? 0,
        activeVerifiers: (json['active_verifiers'] as num?)?.toInt() ?? 0,
        activeAdmins: (json['active_admins'] as num?)?.toInt() ?? 0,
        teamMembers: (json['team_members'] as List?)
                ?.whereType<Map>()
                .map((row) =>
                    _LabTeamMember.fromJson(Map<String, dynamic>.from(row)))
                .toList() ??
            const [],
      );
}

class _LabTeamMember {
  const _LabTeamMember({
    required this.name,
    required this.email,
    required this.role,
  });

  final String name;
  final String email;
  final String role;

  factory _LabTeamMember.fromJson(Map<String, dynamic> json) {
    final email = json['email']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    return _LabTeamMember(
      name: name.isEmpty ? (email.isEmpty ? 'Lab team member' : email) : name,
      email: email,
      role: json['role']?.toString().trim().isEmpty ?? true
          ? 'Lab team member'
          : json['role'].toString().trim(),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.governance});
  final _LabGovernance governance;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [CorviaColors.accentDark, CorviaColors.accent]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.science_rounded, color: Colors.white, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(governance.labName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    governance.isActive
                        ? 'Internal laboratory is active'
                        : 'Internal laboratory is inactive',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _LabTeamExpansion extends StatelessWidget {
  const _LabTeamExpansion({required this.governance});

  final _LabGovernance governance;

  String get _summary =>
      '${governance.activeTechnicians} technician${governance.activeTechnicians == 1 ? '' : 's'}, '
      '${governance.activeVerifiers} verifier${governance.activeVerifiers == 1 ? '' : 's'} and '
      '${governance.activeAdmins} Lab Admin${governance.activeAdmins == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          backgroundColor: context.cBgSecondary,
          collapsedBackgroundColor: context.cBgSecondary,
          shape: Border.all(color: context.cDivider),
          collapsedShape: Border.all(color: context.cDivider),
          iconColor: context.cAccentReadable,
          collapsedIconColor: context.cTextSecondary,
          leading: Icon(
            Icons.manage_accounts_outlined,
            color: context.cAccentReadable,
          ),
          title: Text(
            'Internal laboratory team',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            _summary,
            style: TextStyle(color: context.cTextSecondary, fontSize: 13),
          ),
          children: [
            if (governance.teamMembers.isEmpty)
              const _LabTeamEmptyState()
            else
              ...governance.teamMembers.map(
                (member) => _LabTeamMemberCard(member: member),
              ),
          ],
        ),
      );
}

class _LabTeamMemberCard extends StatelessWidget {
  const _LabTeamMemberCard({required this.member});

  final _LabTeamMember member;

  @override
  Widget build(BuildContext context) {
    final isVerifier = member.role == 'Verifier';
    final isAdmin = member.role == 'Lab Admin';
    final icon = isAdmin
        ? Icons.admin_panel_settings_outlined
        : isVerifier
            ? Icons.fact_check_outlined
            : Icons.biotech_outlined;
    final color = isAdmin
        ? context.cAccentReadable
        : isVerifier
            ? CorviaColors.success
            : CorviaColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: context.cDivider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (member.email.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    member.email,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              member.role,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabTeamEmptyState extends StatelessWidget {
  const _LabTeamEmptyState();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.cBgPrimary,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: context.cDivider),
        ),
        child: Column(
          children: [
            Icon(Icons.group_off_outlined, color: context.cTextMuted),
            const SizedBox(height: 8),
            Text(
              'No active laboratory team members',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Appoint a Lab Admin, then use the Lab Admin dashboard to assign Technician and Verifier roles.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary, height: 1.35),
            ),
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cDivider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.cAccentReadable),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: context.cTextPrimary,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: TextStyle(
                          color: context.cTextSecondary, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProviderStatePill extends StatelessWidget {
  const _ProviderStatePill({required this.connected});
  final bool connected;
  @override
  Widget build(BuildContext context) {
    final color = connected ? CorviaColors.success : context.cTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(connected ? 'Available for orders' : 'Not connected',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _ProviderEmptyState extends StatelessWidget {
  const _ProviderEmptyState({required this.title, required this.body});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.cDivider),
        ),
        child: Column(children: [
          Icon(Icons.domain_disabled_outlined,
              color: context.cTextMuted, size: 38),
          const SizedBox(height: 9),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.cTextPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary)),
        ]),
      );
}

class _GovernanceError extends StatelessWidget {
  const _GovernanceError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: CorviaColors.danger, size: 52),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}
