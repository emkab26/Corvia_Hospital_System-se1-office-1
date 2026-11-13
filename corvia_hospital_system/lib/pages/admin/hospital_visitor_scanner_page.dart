import 'package:flutter/material.dart';

import '../../services/hospital_visitor_service.dart';
import '../../theme/app_theme.dart';

class HospitalVisitorScannerPage extends StatefulWidget {
  const HospitalVisitorScannerPage({
    super.key,
    this.initialQrToken,
  });

  final String? initialQrToken;

  @override
  State<HospitalVisitorScannerPage> createState() =>
      _HospitalVisitorScannerPageState();
}

class _HospitalVisitorScannerPageState
    extends State<HospitalVisitorScannerPage> {
  final HospitalVisitorService _service = HospitalVisitorService();

  final TextEditingController _qrController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  bool _busy = false;
  bool _identityVerified = false;

  String _verificationMethod = 'visual_confirmation';
  String _checkinMethod = 'qr';

  VisitorPassEvaluation? _evaluation;
  VisitorCheckinResult? _checkinResult;

  @override
  void initState() {
    super.initState();

    _qrController.text = widget.initialQrToken?.trim() ?? '';
  }

  @override
  void dispose() {
    _qrController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? CorviaColors.danger : CorviaColors.accentDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _lookupPass() async {
    final token = _qrController.text.trim();

    if (token.isEmpty) {
      _showMessage(
        'Enter or scan a visitor QR token.',
        error: true,
      );
      return;
    }

    setState(() {
      _busy = true;
      _evaluation = null;
      _checkinResult = null;
    });

    try {
      final result = await _service.lookupVisitorPassByQr(
        qrToken: token,
        identityVerified: _identityVerified,
      );

      if (!mounted) return;

      setState(() {
        _evaluation = result;
      });
    } catch (error) {
      _showMessage(
        'Visitor pass lookup failed: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _checkInVisitor() async {
    final token = _qrController.text.trim();

    if (token.isEmpty) {
      _showMessage(
        'Enter or scan a visitor QR token.',
        error: true,
      );
      return;
    }

    final evaluation = _evaluation;

    if (evaluation == null) {
      _showMessage(
        'Verify the visitor pass before checking in.',
        error: true,
      );
      return;
    }

    if (!evaluation.allowed) {
      _showMessage(
        evaluation.reason,
        error: true,
      );
      return;
    }

    setState(() {
      _busy = true;
      _checkinResult = null;
    });

    try {
      final result = await _service.checkinVisitor(
        qrToken: token,
        identityVerified: _identityVerified,
        verificationMethod:
            _identityVerified ? _verificationMethod : 'not_required',
        checkinMethod: _checkinMethod,
        notes: _notesController.text,
      );

      if (!mounted) return;

      setState(() {
        _checkinResult = result;
      });

      if (result.success) {
        _showMessage(
          'Visitor checked in successfully.',
        );
      } else {
        _showMessage(
          result.reason ?? 'Visitor could not be checked in.',
          error: true,
        );
      }
    } catch (error) {
      _showMessage(
        'Visitor check-in failed: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _clearScanner() {
    setState(() {
      _qrController.clear();
      _notesController.clear();
      _identityVerified = false;
      _verificationMethod = 'visual_confirmation';
      _checkinMethod = 'qr';
      _evaluation = null;
      _checkinResult = null;
    });
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    return '${value.year}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String _humanize(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Not available';
    }

    final words = value.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));

    return words.map((word) {
      if (word.isEmpty) return word;

      return '${word[0].toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  Color _evaluationColor(
    VisitorPassEvaluation evaluation,
  ) {
    return evaluation.allowed ? CorviaColors.success : CorviaColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 900,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildScannerPanel(),
                  if (_evaluation != null) ...[
                    const SizedBox(height: 18),
                    _buildEvaluationPanel(
                      _evaluation!,
                    ),
                  ],
                  if (_checkinResult != null) ...[
                    const SizedBox(height: 18),
                    _buildCheckinResult(
                      _checkinResult!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Material(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(14),
          child: IconButton(
            tooltip: 'Back',
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: Icon(
              Icons.arrow_back_rounded,
              color: context.cAccentReadable,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Visitor Pass Scanner',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Verify a visitor pass, confirm identity and complete check-in.',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Clear scanner',
          onPressed: _busy ? null : _clearScanner,
          icon: Icon(
            Icons.restart_alt_rounded,
            color: context.cAccentReadable,
          ),
        ),
      ],
    );
  }

  Widget _buildScannerPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: context.cAccentReadable.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: context.cAccentReadable,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan or enter QR token',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'The token is verified securely through Supabase.',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _qrController,
            enabled: !_busy,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Visitor QR token',
              hintText: 'Paste the scanned visitor token here',
              prefixIcon: Icon(
                Icons.qr_code_2_rounded,
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _identityVerified,
            onChanged: _busy
                ? null
                : (value) {
                    setState(() {
                      _identityVerified = value;
                    });
                  },
            title: const Text(
              'Visitor identity verified',
            ),
            subtitle: const Text(
              'Confirm that the visitor’s physical identification matches the pass.',
            ),
          ),
          if (_identityVerified) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _verificationMethod,
              decoration: const InputDecoration(
                labelText: 'Verification method',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'visual_confirmation',
                  child: Text(
                    'Visual confirmation',
                  ),
                ),
                DropdownMenuItem(
                  value: 'south_african_id',
                  child: Text(
                    'South African ID',
                  ),
                ),
                DropdownMenuItem(
                  value: 'passport',
                  child: Text('Passport'),
                ),
                DropdownMenuItem(
                  value: 'drivers_licence',
                  child: Text(
                    'Driver’s licence',
                  ),
                ),
                DropdownMenuItem(
                  value: 'birth_certificate',
                  child: Text(
                    'Birth certificate',
                  ),
                ),
                DropdownMenuItem(
                  value: 'temporary_document',
                  child: Text(
                    'Temporary document',
                  ),
                ),
                DropdownMenuItem(
                  value: 'staff_override',
                  child: Text(
                    'Staff override',
                  ),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value == null) return;

                      setState(() {
                        _verificationMethod = value;
                      });
                    },
            ),
          ],
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _checkinMethod,
            decoration: const InputDecoration(
              labelText: 'Check-in method',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'qr',
                child: Text('QR scanner'),
              ),
              DropdownMenuItem(
                value: 'manual',
                child: Text('Manual'),
              ),
              DropdownMenuItem(
                value: 'reception',
                child: Text('Reception'),
              ),
              DropdownMenuItem(
                value: 'security_desk',
                child: Text('Security desk'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;

                    setState(() {
                      _checkinMethod = value;
                    });
                  },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notesController,
            enabled: !_busy,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Check-in notes',
              hintText: 'Optional security or reception notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _lookupPass,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.verified_rounded,
                    ),
              label: const Text(
                'Verify Visitor Pass',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvaluationPanel(
    VisitorPassEvaluation evaluation,
  ) {
    final color = _evaluationColor(evaluation);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  evaluation.allowed
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evaluation.allowed ? 'Access Approved' : 'Access Denied',
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      evaluation.reason,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _detail(
            'Pass number',
            evaluation.passNumber,
          ),
          _detail(
            'Pass status',
            _humanize(
              evaluation.passStatus,
            ),
          ),
          _detail(
            'Pass type',
            _humanize(
              evaluation.passType,
            ),
          ),
          _detail(
            'Visitor',
            evaluation.visitorName,
          ),
          _detail(
            'Visitor ID type',
            _humanize(
              evaluation.visitorIdType,
            ),
          ),
          _detail(
            'Patient',
            evaluation.patientName,
          ),
          _detail(
            'Patient number',
            evaluation.patientNumber,
          ),
          _detail(
            'Relationship',
            _humanize(
              evaluation.relationshipToPatient,
            ),
          ),
          _detail(
            'Ward',
            evaluation.wardName,
          ),
          if (evaluation.showRoomNumber)
            _detail(
              'Room',
              evaluation.roomNumber,
            ),
          if (evaluation.showBedLabel)
            _detail(
              'Bed',
              evaluation.bedLabel,
            ),
          _detail(
            'Valid from',
            _formatDate(
              evaluation.validFrom,
            ),
          ),
          _detail(
            'Valid until',
            _formatDate(
              evaluation.validUntil,
            ),
          ),
          _detail(
            'Entries used',
            evaluation.maxEntries == null
                ? '${evaluation.entriesUsed}'
                : '${evaluation.entriesUsed} / '
                    '${evaluation.maxEntries}',
          ),
          _detail(
            'Visitors currently inside',
            '${evaluation.currentOpenVisitors} / '
                '${evaluation.maximumVisitors}',
          ),
          if (evaluation.specialInstructions != null)
            _detail(
              'Special instructions',
              evaluation.specialInstructions,
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || !evaluation.allowed ? null : _checkInVisitor,
              icon: const Icon(
                Icons.login_rounded,
              ),
              label: const Text(
                'Check Visitor In',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckinResult(
    VisitorCheckinResult result,
  ) {
    final color = result.success ? CorviaColors.success : CorviaColors.danger;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: color.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          Icon(
            result.success ? Icons.how_to_reg_rounded : Icons.error_rounded,
            color: color,
            size: 34,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.success ? 'Visitor Checked In' : 'Check-in Failed',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  result.success
                      ? 'Check-in ID: '
                          '${result.checkinId ?? 'Created'}'
                      : result.reason ?? 'Visitor could not be checked in.',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(
    String label,
    String? value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 165,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value == null || value.trim().isEmpty ? 'Not available' : value,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
