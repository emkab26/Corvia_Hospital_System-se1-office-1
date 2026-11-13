import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/role_choice_page.dart';
import '../../pages/shared/settings.dart';
import '../../services/account_mode_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/corvia_scanner.dart';
import '../../widgets/staff_workspace_shell.dart';
import '../../widgets/workspace_navigation.dart';

/// Technician-only specimen and result submission workspace.
class LabWorkerDashboardPage extends StatefulWidget {
  const LabWorkerDashboardPage({super.key});

  @override
  State<LabWorkerDashboardPage> createState() => _LabWorkerDashboardPageState();
}

class _LabWorkerDashboardPageState extends State<LabWorkerDashboardPage>
    with WorkspaceNavigation<LabWorkerDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _containerController = TextEditingController();

  bool _loading = true;
  bool _working = false;
  bool _editingResult = false;
  bool _isSigningOut = false;
  bool _canOpenPatientAccount = false;
  String? _error;
  _LabContext? _labContext;
  _Specimen? _specimen;
  List<_Specimen> _queue = [];
  String? _queueError;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _containerController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await _supabase.rpc('corvia_current_lab_technician_context');
      var canOpenPatientAccount = false;
      var signedInName = '';
      try {
        canOpenPatientAccount =
            (await AccountModeService.current()).hasPatientAccess;
      } catch (_) {
        // The lab workspace remains usable if the optional personal-account
        // lookup is unavailable on an older server schema.
      }
      try {
        final profile = await _supabase
            .from('profiles')
            .select('first_name, surname')
            .eq('user_id', _supabase.auth.currentUser?.id ?? '')
            .maybeSingle();
        if (profile != null) {
          signedInName = [
            profile['first_name']?.toString().trim() ?? '',
            profile['surname']?.toString().trim() ?? '',
          ].where((value) => value.isNotEmpty).join(' ');
        }
      } catch (_) {
        // The identity line is optional and must not block lab access.
      }
      if (!mounted) return;
      setState(() {
        _labContext = _LabContext.fromJson(_map(response));
        _labContext = _labContext!.copyWith(
          signedInName: signedInName,
        );
        _canOpenPatientAccount = canOpenPatientAccount;
        _loading = false;
      });
      await _refreshQueue();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _cleanError(error);
      });
    }
  }

  Future<void> _lookupContainer() async {
    if (_working) return;
    final containerId = _containerIdFrom(_containerController.text);
    if (containerId == null) {
      setState(() => _specimen = null);
      _message(
          'Scan a Corvia specimen or transport-bag QR, or enter its valid ID.');
      return;
    }
    setState(() => _working = true);
    await _fetchContainer(containerId);
    if (mounted) setState(() => _working = false);
  }

  Future<void> _fetchContainer(String containerId) async {
    if (mounted) setState(() => _specimen = null);
    try {
      final response = await _supabase.rpc(
        'corvia_lab_technician_collection_item',
        params: {'p_item_id': containerId},
      );
      if (!mounted) return;
      setState(() => _specimen = _Specimen.fromJson(_map(response)));
    } catch (error) {
      _message(_cleanError(error));
    }
  }

  Future<void> _refreshQueue() async {
    try {
      final response =
          await _supabase.rpc('corvia_lab_technician_collection_queue');
      if (response is! List) {
        throw const FormatException('Invalid specimen queue response.');
      }
      final specimens = response
          .whereType<Map>()
          .map((row) => _Specimen.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      if (mounted) {
        setState(() {
          _queue = specimens;
          _queueError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _queue = [];
          _queueError = _cleanError(error);
        });
      }
    }
  }

  Future<void> _openQueuedSpecimen(_Specimen specimen) async {
    if (_working) return;
    _containerController.text = specimen.id;
    await _lookupContainer();
  }

  Future<void> _receiveSpecimen() async {
    final specimen = _specimen;
    if (specimen == null || _working) return;
    setState(() => _working = true);
    try {
      final response = await _supabase.rpc(
        'corvia_lab_worker_receive_collection_item',
        params: {'p_item_id': specimen.id},
      );
      if (_map(response)['status'] != 'received') {
        throw const FormatException(
            'The server did not confirm specimen receipt.');
      }
      await _fetchContainer(specimen.id);
      await _refreshQueue();
      _message(
          'Specimen collection received. Its tests are ready for result entry.');
    } catch (error) {
      _message(_cleanError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _enterResult(_LabTest test) async {
    if (_working || !test.canSubmit) return;
    final specimenId = _specimen?.id;
    if (specimenId == null) return;
    setState(() {
      _working = true;
      _editingResult = true;
    });
    var resultText = test.draftResult;
    var documentUrl = test.draftFileUrl;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            '${test.isReturned ? 'Correct result' : 'Enter result'}: ${test.name}'),
        content: SizedBox(
          width: 520,
          child: Form(
              key: formKey,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (test.isReturned) ...[
                  Text('Verifier correction request: ${test.returnReason}'),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  initialValue: test.draftResult,
                  onChanged: (value) => resultText = value,
                  autofocus: true,
                  maxLines: 8,
                  maxLength: 10000,
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter at least two characters.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Result / laboratory notes',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: test.draftFileUrl,
                  onChanged: (value) => documentUrl = value,
                  maxLength: 2048,
                  decoration: const InputDecoration(
                      labelText: 'Result document URL (optional)',
                      border: OutlineInputBorder()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final uri = Uri.tryParse(value.trim());
                    return uri != null &&
                            uri.scheme == 'https' &&
                            uri.host.isNotEmpty
                        ? null
                        : 'Enter a valid HTTPS document URL.';
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                    'Submission sends this result to a verifier. It does not release it to the patient.'),
              ]))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, resultText.trim());
                }
              },
              child: const Text('Submit for verification')),
        ],
      ),
    );
    final fileUrl = documentUrl.trim();
    if (mounted) setState(() => _editingResult = false);
    if (result == null || !mounted) {
      if (mounted) setState(() => _working = false);
      return;
    }
    try {
      final response = await _supabase.rpc(
        'corvia_lab_technician_submit_result',
        params: {
          'p_lab_result_id': test.id,
          'p_result': result,
          'p_file_url': fileUrl.isEmpty ? null : fileUrl,
          'p_expected_version': test.submissionVersion
        },
      );
      final status = _map(response)['result_release_status']?.toString();
      if (status != 'awaiting_verification') {
        throw const FormatException(
            'The server did not confirm submission for verification.');
      }
      _message('Result submitted for verification.');
      await _fetchContainer(specimenId);
      await _refreshQueue();
    } catch (error) {
      _message(_cleanError(error));
      await _fetchContainer(specimenId);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _scanContainer() async {
    if (_working) return;
    workspaceHome();
    final scanner = CorviaScannerController();
    var handled = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scan sample or bag QR label'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CorviaScanner(
              controller: scanner,
              onDetect: (capture) {
                if (handled || capture.barcodes.isEmpty) return;
                final value = capture.barcodes.first.rawValue;
                if (value == null || value.trim().isEmpty) return;
                handled = true;
                scanner.stop();
                _containerController.text = value;
                Navigator.pop(dialogContext);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'))
        ],
      ),
    );
    scanner.dispose();
    if (handled && mounted) await _lookupContainer();
  }

  String? _containerIdFrom(String value) {
    final match = RegExp(
            r'^(?:(?:CORVIA_SPECIMEN\|container_id=)|(?:CORVIA_SPECIMEN_BAG\|bag_id=))?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$')
        .firstMatch(value.trim());
    return match?.group(1);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException(
        'Laboratory data returned an invalid response.');
  }

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', '')
      .replaceAll(')', '');

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _openOptions() => pushWorkspace<void>(
        MaterialPageRoute<void>(
            builder: (_) => const SettingsPage(showAppBar: false)),
        label: 'Settings',
      );

  Future<void> _openSwitchDashboard() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const RoleChoicePage()),
      );

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      SettingsService.instance.sessionUnlocked = false;
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (error) {
      _message('Sign out failed: ${error.message}');
    } catch (error) {
      _message('Sign out failed. $error');
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          backgroundColor: context.cBgPrimary,
          appBar: AppBar(title: const Text('Laboratory Workspace')),
          body: Center(
              child: CircularProgressIndicator(color: CorviaColors.accent)));
    }
    if (_error != null || _labContext == null) {
      return Scaffold(
          backgroundColor: context.cBgPrimary,
          appBar: AppBar(title: const Text('Laboratory Workspace')),
          body: _ErrorState(
              message: _error ?? 'Laboratory access is unavailable.',
              onRetry: _loadContext));
    }

    final contextData = _labContext!;
    final blocked = _working || _isSigningOut;
    return StaffWorkspaceShell(
      workspaceName: 'Laboratory',
      breadcrumb: 'Laboratory',
      pageTitle: workspaceTitle ?? 'Specimen work queue',
      subtitle: 'Receive specimens, enter results and send them for '
          'verification.',
      onSignOut: _isSigningOut ? null : _signOut,
      headerActions: [
        if (workspaceCanPop)
          workspaceBackButton
        else
          OutlinedButton.icon(
            onPressed: _working ? null : _refreshQueue,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
      ],
      items: [
        StaffShellItem(
          label: 'Work queue',
          icon: Icons.biotech_rounded,
          selected: !workspaceCanPop,
          onTap: blocked ? null : workspaceHome,
        ),
        if (!contextData.isOutsourced)
          StaffShellItem(
            label: 'Scan QR label',
            icon: Icons.qr_code_scanner_rounded,
            onTap: blocked ? null : _scanContainer,
          ),
        if (_canOpenPatientAccount)
          StaffShellItem(
            label: 'Switch to patient',
            icon: Icons.swap_horiz_rounded,
            onTap: blocked ? null : _openSwitchDashboard,
          ),
        StaffShellItem(
          label: 'Settings',
          selected: workspaceSelection == 'Settings',
          icon: Icons.settings_rounded,
          onTap: blocked ? null : _openOptions,
        ),
      ],
      body: workspaceBody(ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(contextData: contextData),
          const SizedBox(height: 16),
          _InfoBanner(
              icon: contextData.isOutsourced
                  ? Icons.local_shipping_outlined
                  : Icons.qr_code_scanner_rounded,
              title: 'Receive specimens or a transport bag',
              body: contextData.isOutsourced
                  ? 'Open the provider-labelled samples from the work queue. Corvia does not issue QR labels for outsourced collections. Every result still requires verification.'
                  : 'Scan a Corvia sample or bag label to match the collection to this laboratory. Every submitted result must be approved by a verifier.'),
          const SizedBox(height: 14),
          _LookupCard(
              controller: _containerController,
              working: _working,
              allowScan: !contextData.isOutsourced,
              onScan: _scanContainer,
              onLookup: _lookupContainer),
          if (_working && !_editingResult)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
          if (_specimen != null) ...[
            const SizedBox(height: 16),
            _SpecimenCard(
                specimen: _specimen!,
                working: _working,
                onReceive: _receiveSpecimen,
                onEnterResult: _enterResult),
          ],
          const SizedBox(height: 20),
          Text('Specimen work queue',
              style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_queueError != null) ...[
            Text('Could not load specimens: $_queueError'),
            TextButton(
                onPressed: _working ? null : _refreshQueue,
                child: const Text('Retry queue')),
          ] else if (_queue.isEmpty)
            const Text('No specimens awaiting receipt, testing or correction.')
          else
            ..._queue.map((specimen) => Card(
                    child: ListTile(
                  title: Text(specimen.code),
                  subtitle: Text(
                      '${specimen.type} · ${specimen.tests.any((test) => test.isReturned) ? 'Returned for correction' : specimen.status.replaceAll('_', ' ')}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _working ? null : () => _openQueuedSpecimen(specimen),
                ))),
        ],
      )),
    );
  }
}

class _LabContext {
  const _LabContext({
    required this.labName,
    required this.labType,
    this.signedInName = '',
  });
  final String labName;
  final String labType;
  final String signedInName;
  bool get isOutsourced => labType == 'private';

  factory _LabContext.fromJson(Map<String, dynamic> json) => _LabContext(
        labName: (json['lab_name']?.toString().trim().isNotEmpty ?? false)
            ? json['lab_name'].toString().trim()
            : 'Hospital Laboratory',
        labType: json['lab_type']?.toString().trim().toLowerCase() ?? '',
      );

  _LabContext copyWith({required String signedInName}) => _LabContext(
        labName: labName,
        labType: labType,
        signedInName: signedInName,
      );
}

class _Specimen {
  const _Specimen(
      {required this.id,
      required this.code,
      required this.type,
      required this.status,
      required this.tests});
  final String id;
  final String code;
  final String type;
  final String status;
  final List<_LabTest> tests;
  factory _Specimen.fromJson(Map<String, dynamic> json) => _Specimen(
        id: json['container_id'].toString(),
        code: json['container_code']?.toString() ?? 'Specimen container',
        type: json['specimen_type']?.toString() ?? 'Specimen',
        status: json['status']?.toString() ?? 'unknown',
        tests: (json['tests'] as List? ?? const [])
            .whereType<Map>()
            .map((test) => _LabTest.fromJson(Map<String, dynamic>.from(test)))
            .toList(),
      );
}

class _LabTest {
  const _LabTest(
      {required this.id,
      required this.name,
      required this.releaseStatus,
      required this.draftResult,
      required this.draftFileUrl,
      required this.returnReason,
      required this.submissionVersion});
  final String id;
  final String name;
  final String releaseStatus;
  final String draftResult;
  final String draftFileUrl;
  final String returnReason;
  final int submissionVersion;
  bool get isReturned => releaseStatus == 'pending' && returnReason.isNotEmpty;
  bool get canSubmit => releaseStatus == 'pending';
  factory _LabTest.fromJson(Map<String, dynamic> json) => _LabTest(
        id: json['lab_result_id'].toString(),
        name: json['test_name']?.toString() ?? 'Laboratory test',
        releaseStatus: json['result_release_status']?.toString() ?? 'pending',
        draftResult: json['draft_result']?.toString() ?? '',
        draftFileUrl: json['draft_file_url']?.toString() ?? '',
        returnReason: json['verification_return_reason']?.toString() ?? '',
        submissionVersion:
            (json['result_submission_version'] as num?)?.toInt() ?? 0,
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.contextData});
  final _LabContext contextData;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [CorviaColors.accentDark, CorviaColors.accent]),
            borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.biotech_rounded, color: Colors.white, size: 38),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(contextData.labName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Lab Technician · All results require verification',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                if (contextData.signedInName.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('Signed in as ${contextData.signedInName}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ])),
        ]),
      );
}

class _LookupCard extends StatelessWidget {
  const _LookupCard(
      {required this.controller,
      required this.working,
      required this.allowScan,
      required this.onScan,
      required this.onLookup});
  final TextEditingController controller;
  final bool working;
  final bool allowScan;
  final VoidCallback onScan;
  final VoidCallback onLookup;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.cDivider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
              controller: controller,
              enabled: !working,
              decoration: const InputDecoration(
                  labelText: 'Sample or bag ID / QR content',
                  hintText: 'Scan the label or paste its UUID',
                  prefixIcon: Icon(Icons.qr_code_2_rounded),
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (allowScan)
              FilledButton.icon(
                  onPressed: working ? null : onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan QR label')),
            OutlinedButton.icon(
                onPressed: working ? null : onLookup,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Look up specimen')),
          ]),
        ]),
      );
}

class _SpecimenCard extends StatelessWidget {
  const _SpecimenCard(
      {required this.specimen,
      required this.working,
      required this.onReceive,
      required this.onEnterResult});
  final _Specimen specimen;
  final bool working;
  final VoidCallback onReceive;
  final Future<void> Function(_LabTest) onEnterResult;
  bool get _canEnterResults =>
      specimen.status == 'received' || specimen.status == 'processing';
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.cDivider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.inventory_2_rounded, color: context.cAccentReadable),
            const SizedBox(width: 10),
            Expanded(
                child: Text(specimen.code,
                    style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold))),
            _StatusChip(value: specimen.status)
          ]),
          const SizedBox(height: 10),
          Text('Specimen type: ${specimen.type}',
              style: TextStyle(color: context.cTextSecondary)),
          if (specimen.status == 'collected') ...[
            const SizedBox(height: 14),
            FilledButton.icon(
                onPressed: working ? null : onReceive,
                icon: const Icon(Icons.inventory_2_rounded),
                label: const Text('Confirm receipt'))
          ],
          const SizedBox(height: 16),
          Text('Requested tests',
              style: TextStyle(
                  color: context.cTextPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (specimen.tests.isEmpty)
            Text('No tests are linked to this specimen.',
                style: TextStyle(color: context.cTextSecondary))
          else
            ...specimen.tests.map((test) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    tileColor: context.cBgPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    title: Text(test.name),
                    subtitle: Text(test.isReturned
                        ? 'Returned for correction: ${test.returnReason}'
                        : test.releaseStatus.replaceAll('_', ' ')),
                    trailing: FilledButton(
                        onPressed:
                            working || !_canEnterResults || !test.canSubmit
                                ? null
                                : () => onEnterResult(test),
                        child: Text(test.canSubmit
                            ? (test.isReturned
                                ? 'Correct result'
                                : 'Enter result')
                            : 'Submitted')),
                  ),
                )),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.value});
  final String value;
  @override
  Widget build(BuildContext context) =>
      Chip(label: Text(value.replaceAll('_', ' ')));
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(
      {required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: context.cAccentReadable.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    style:
                        TextStyle(color: context.cTextSecondary, height: 1.35))
              ]))
        ]),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline_rounded,
              color: CorviaColors.danger, size: 52),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary)),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'))
        ]),
      ));
}
