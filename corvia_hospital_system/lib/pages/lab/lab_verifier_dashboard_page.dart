import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/role_choice_page.dart';
import '../../services/account_mode_service.dart';
import '../../services/lab_verifier_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../shared/settings.dart';
import '../../widgets/staff_workspace_shell.dart';
import '../../widgets/workspace_navigation.dart';

/// Independent review only: no specimen receipt or original result entry.
class LabVerifierDashboardPage extends StatefulWidget {
  const LabVerifierDashboardPage({super.key});
  @override
  State<LabVerifierDashboardPage> createState() =>
      _LabVerifierDashboardPageState();
}

class _LabVerifierDashboardPageState extends State<LabVerifierDashboardPage>
    with WorkspaceNavigation<LabVerifierDashboardPage> {
  final _service = LabVerifierService(Supabase.instance.client);
  Map<String, dynamic>? _context;
  List<LabVerificationSubmission> _pending = [], _returned = [];
  bool _loading = true, _working = false, _patient = false;
  String? _error;
  String _signedInName = '';
  String _signedInEmail = '';

  @override
  void initState() {
    super.initState();
    _load();
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
      final contextData = await _service.context();
      final queues = await Future.wait([
        _service.queue(returned: false),
        _service.queue(returned: true),
      ]);
      var patient = false;
      var signedInName = '';
      var signedInEmail =
          Supabase.instance.client.auth.currentUser?.email ?? '';
      try {
        patient = (await AccountModeService.current()).hasPatientAccess;
      } catch (_) {}
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('first_name, surname, email')
            .eq('user_id', Supabase.instance.client.auth.currentUser?.id ?? '')
            .maybeSingle();
        if (profile != null) {
          signedInName = [
            profile['first_name']?.toString().trim() ?? '',
            profile['surname']?.toString().trim() ?? '',
          ].where((part) => part.isNotEmpty).join(' ');
          signedInEmail = profile['email']?.toString().trim() ?? signedInEmail;
        }
      } catch (_) {
        // Identity is presentational and must not block verifier access.
      }
      if (mounted) {
        setState(() {
          _context = contextData;
          _pending = queues[0];
          _returned = queues[1];
          _patient = patient;
          _signedInName = signedInName;
          _signedInEmail = signedInEmail;
        });
      }
    } catch (error) {
      // Never leave stale review controls usable when permission refresh fails.
      if (mounted) {
        setState(() {
          _context = null;
          _pending = [];
          _returned = [];
          _error = _clean(error);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Time unavailable';
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _document(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _message('The submission does not contain a valid HTTPS document link.');
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _message('Could not open the result document.');
      }
    } catch (_) {
      _message('Could not open the result document.');
    }
  }

  Future<void> _review(LabVerificationSubmission submission) async {
    if (_working || _loading) return;
    setState(() => _working = true);
    String reason = '';
    final form = GlobalKey<FormState>();
    try {
      final action = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: CorviaColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.fact_check_outlined,
                        color: context.cAccentReadable),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(submission.testName,
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.bold)),
                      const Text('Independent result review',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.normal)),
                    ],
                  )),
                ]),
                content: SizedBox(
                    width: 620,
                    child: SingleChildScrollView(
                        child: Form(
                            key: form,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: context.cBgPrimary,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: context.cDivider),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                          '${submission.data['patient_name'] ?? 'Patient'} · Reference: ${submission.data['patient_id']}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 6),
                                      Text(
                                          'Submitted by ${submission.technician} · ${_date(submission.data['result_entered_at'])}'),
                                      const SizedBox(height: 3),
                                      Text(
                                          'Specimen: ${submission.data['container_label'] ?? 'Not recorded'} · ${submission.data['specimen_type'] ?? 'Not recorded'}'),
                                      const SizedBox(height: 3),
                                      Text(
                                          'Submission version ${submission.version}'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text('Submitted result',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: context.cBgSecondary,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: context.cDivider),
                                  ),
                                  child: SelectableText(submission.result,
                                      style: const TextStyle(height: 1.45)),
                                ),
                                if ((submission.data['draft_file_url']
                                            ?.toString() ??
                                        '')
                                    .isNotEmpty)
                                  TextButton.icon(
                                      onPressed: () => _document(submission
                                          .data['draft_file_url']
                                          .toString()),
                                      icon: const Icon(Icons.open_in_new),
                                      label: const Text(
                                          'Open submitted document')),
                                const SizedBox(height: 16),
                                Text(submission.requiresDoctorReview
                                    ? 'Approval sends the verified result to the ordering doctor. It is not released to the patient yet.'
                                    : 'Approval releases the verified result to the patient, as chosen by the ordering doctor.'),
                                if (!submission.canReview &&
                                    submission.data['result_release_status'] ==
                                        'awaiting_verification') ...[
                                  const SizedBox(height: 12),
                                  const Text(
                                      'You cannot review your own submission. Another verifier must review it.'),
                                ],
                                if (submission.data['return_reason'] !=
                                    null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                      'Correction requested: ${submission.data['return_reason']}'),
                                  Text(
                                      'Returned ${_date(submission.data['returned_at'])}'),
                                ],
                                if (submission.canReview) ...[
                                  const SizedBox(height: 16),
                                  TextFormField(
                                      maxLines: 3,
                                      maxLength: 2000,
                                      onChanged: (value) => reason = value,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Reason for return (required only when returning)',
                                          border: OutlineInputBorder()),
                                      validator: (value) => (value
                                                      ?.trim()
                                                      .length ??
                                                  0) <
                                              3
                                          ? 'Explain the correction needed (at least 3 characters).'
                                          : null),
                                ],
                              ],
                            )))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close')),
                  if (submission.canReview) ...[
                    OutlinedButton(
                        onPressed: () {
                          if (form.currentState!.validate()) {
                            Navigator.pop(dialogContext, 'return');
                          }
                        },
                        child: const Text('Return for correction')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(dialogContext, 'approve'),
                        child: const Text('Approve result')),
                  ],
                ],
              ));
      if (action == null || !mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text(action == 'approve'
                    ? 'Approve this submission?'
                    : 'Return for correction?'),
                content: Text(action == 'approve'
                    ? 'Confirm that you have reviewed submission version ${submission.version} of ${submission.testName}. The ordering doctor’s release choice will be respected.'
                    : 'Send this correction request back to the technician?\n\n${reason.trim()}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Confirm'))
                ],
              ));
      if (confirmed != true || !mounted) return;
      if (action == 'approve') {
        final status = await _service.approve(submission);
        _message(status == 'awaiting_doctor_review'
            ? 'Verified. Awaiting release by the ordering doctor.'
            : 'Verified and released to the patient.');
      } else {
        await _service.returnForCorrection(submission, reason);
        _message('Returned to the technician for correction.');
      }
      await _load();
    } catch (error) {
      _message(_clean(error));
      await _load();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _signOut() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await Supabase.instance.client.auth.signOut();
      SettingsService.instance.sessionUnlocked = false;
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      _message('Sign out failed: ${_clean(error)}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _queue(List<LabVerificationSubmission> queue, bool returned) =>
      RefreshIndicator(
        onRefresh: _working ? () async {} : _load,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.cDivider),
                ),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: CorviaColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      returned
                          ? Icons.assignment_return_outlined
                          : Icons.fact_check_outlined,
                      color: context.cAccentReadable,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        returned
                            ? 'Waiting for technician corrections'
                            : 'Results awaiting verification',
                        style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        returned
                            ? 'Previously reviewed results that need corrected submissions.'
                            : 'Oldest submissions are shown first for independent review.',
                        style: TextStyle(
                            color: context.cTextSecondary, height: 1.35),
                      ),
                    ],
                  )),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: context.cBgPrimary,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: context.cDivider),
                    ),
                    child: Text('${queue.length}',
                        style: TextStyle(
                            color: context.cTextPrimary,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              if (queue.isEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
                  decoration: BoxDecoration(
                    color: context.cBgSecondary,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.cDivider),
                  ),
                  child: Column(children: [
                    Icon(Icons.task_alt_rounded,
                        size: 42, color: context.cTextMuted),
                    const SizedBox(height: 10),
                    Text(
                        returned
                            ? 'No results waiting for correction'
                            : 'Verification queue is clear',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: context.cTextPrimary,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        returned
                            ? 'Returned results will remain here until a technician submits a correction.'
                            : 'New technician submissions will appear here automatically after refresh.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.cTextSecondary)),
                  ]),
                ),
              for (final submission in queue)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: context.cBgSecondary,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _working || _loading
                          ? null
                          : () => _review(submission),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: context.cDivider),
                        ),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: (returned
                                          ? CorviaColors.warning
                                          : CorviaColors.accent)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                    returned
                                        ? Icons.undo_rounded
                                        : Icons.science_outlined,
                                    color: returned
                                        ? CorviaColors.warning
                                        : context.cAccentReadable),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(submission.testName,
                                        style: TextStyle(
                                            color: context.cTextPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 5),
                                    Text(
                                        submission.data['patient_name']
                                                ?.toString() ??
                                            'Patient',
                                        style: TextStyle(
                                            color: context.cTextSecondary,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text(
                                        'Submitted by ${submission.technician} · ${_date(submission.data['result_entered_at'])}',
                                        style: TextStyle(
                                            color: context.cTextMuted,
                                            fontSize: 12)),
                                    const SizedBox(height: 10),
                                    Wrap(spacing: 7, runSpacing: 7, children: [
                                      _StatusPill(
                                        label: returned
                                            ? 'Correction requested'
                                            : submission.canReview
                                                ? 'Ready for review'
                                                : 'Another verifier required',
                                        icon: returned
                                            ? Icons.edit_note_rounded
                                            : submission.canReview
                                                ? Icons.fact_check_outlined
                                                : Icons.person_off_outlined,
                                        warning:
                                            returned || !submission.canReview,
                                      ),
                                      _StatusPill(
                                        label: submission.requiresDoctorReview
                                            ? 'Doctor releases'
                                            : 'Release after approval',
                                        icon: submission.requiresDoctorReview
                                            ? Icons.medical_services_outlined
                                            : Icons.person_outline_rounded,
                                      ),
                                    ]),
                                  ])),
                              const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Icon(Icons.chevron_right)),
                            ]),
                      ),
                    ),
                  ),
                ),
            ]),
      );

  Widget _identityBar() {
    final displayName = _signedInName.isNotEmpty
        ? _signedInName
        : _signedInEmail.isNotEmpty
            ? _signedInEmail
            : 'Lab Verifier';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [CorviaColors.accentDark, CorviaColors.accent]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: CorviaColors.accent.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 7))
        ],
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15)),
          child: const Icon(Icons.verified_user_outlined,
              color: Colors.white, size: 29),
        ),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Signed in as',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          Text(displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text('${_context?['lab_name'] ?? 'Laboratory'} · Lab Verifier',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield_outlined, color: Colors.white, size: 15),
            SizedBox(width: 5),
            Text('Review only',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  int _section = 0;

  Future<void> _openSettings() => pushWorkspace<void>(
        MaterialPageRoute<void>(
            builder: (_) => const SettingsPage(showAppBar: false)),
        label: 'Settings',
      );

  @override
  Widget build(BuildContext context) {
    final returned = _section == 1;
    return StaffWorkspaceShell(
      workspaceName: 'Laboratory',
      breadcrumb: 'Lab Verifier',
      pageTitle: workspaceTitle ??
          (returned ? 'Returned for correction' : 'Awaiting verification'),
      subtitle: 'Review submitted results, then approve them or return '
          'them for correction.',
      onSignOut: _working ? null : _signOut,
      headerActions: [
        if (workspaceCanPop)
          workspaceBackButton
        else
          OutlinedButton.icon(
            onPressed: _working || _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
      ],
      items: [
        StaffShellItem(
          label: 'Awaiting verification',
          icon: Icons.fact_check_outlined,
          selected: !workspaceCanPop && !returned,
          onTap: () {
            workspaceHome();
            setState(() => _section = 0);
          },
        ),
        StaffShellItem(
          label: 'Returned for correction',
          icon: Icons.assignment_return_outlined,
          selected: !workspaceCanPop && returned,
          onTap: () {
            workspaceHome();
            setState(() => _section = 1);
          },
        ),
        if (_patient)
          StaffShellItem(
            label: 'Switch to patient',
            icon: Icons.swap_horiz_rounded,
            onTap: _working
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const RoleChoicePage())),
          ),
        StaffShellItem(
          label: 'Settings',
          selected: workspaceSelection == 'Settings',
          icon: Icons.settings_rounded,
          onTap: _working ? null : _openSettings,
        ),
      ],
      body: workspaceBody(Column(children: [
        if (_loading || _working) const LinearProgressIndicator(),
        if (_context != null) _identityBar(),
        Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton(
                              onPressed: _loading || _working ? null : _load,
                              child: const Text('Retry'))
                        ])))
                : _context == null
                    ? const Center(child: CircularProgressIndicator())
                    : returned
                        ? _queue(_returned, true)
                        : _queue(_pending, false)),
      ])),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.icon,
    this.warning = false,
  });

  final String label;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? CorviaColors.warning : context.cAccentReadable;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
