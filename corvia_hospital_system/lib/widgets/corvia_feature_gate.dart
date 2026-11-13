import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class CorviaFeatureKeys {
  static const billing = 'billing';
  static const subscriptionManagement = 'subscription_management';

  static const patientManagement = 'patient_management';
  static const medicalRecords = 'medical_records';
  static const appointments = 'appointments';
  static const emergencyAccess = 'emergency_access';
  static const basicPrescriptions = 'basic_prescriptions';

  static const aiNurse = 'ai_nurse';
  static const pharmacyWorkflow = 'pharmacy_workflow';
  static const visitorManagement = 'visitor_management';
  static const hospitalTransfers = 'hospital_transfers';
  static const bedManagement = 'bed_management';
  static const advancedForms = 'advanced_forms';
  static const doctorMessaging = 'doctor_messaging';
  static const telehealth = 'telehealth';
  static const advancedReports = 'advanced_reports';
  static const multiHospital = 'multi_hospital';
  static const bloodBank = 'blood_bank';
  static const emsFleet = 'ems_fleet';
  static const paramedicWorkspace = 'paramedic_workspace';
}

class CorviaFeatureGate extends StatefulWidget {
  const CorviaFeatureGate({
    super.key,
    required this.hospitalId,
    required this.feature,
    required this.child,
    this.title = 'Corvia Full feature',
    this.description =
        'This feature requires an active Corvia Full subscription.',
    this.onUpgrade,
  });

  final String hospitalId;
  final String feature;

  final Widget child;

  final String title;
  final String description;

  final VoidCallback? onUpgrade;

  @override
  State<CorviaFeatureGate> createState() =>
      _CorviaFeatureGateState();
}

class _CorviaFeatureGateState
    extends State<CorviaFeatureGate> {
  final SupabaseClient _supabase =
      Supabase.instance.client;

  bool _loading = true;
  bool _allowed = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(
    covariant CorviaFeatureGate oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.hospitalId != widget.hospitalId ||
        oldWidget.feature != widget.feature) {
      _check();
    }
  }

  Future<void> _check() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await _supabase.rpc(
        'corvia_hospital_has_feature',
        params: {
          'p_hospital_id': widget.hospitalId,
          'p_feature': widget.feature,
        },
      );

      if (!mounted) return;

      setState(() {
        _allowed = result == true;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _allowed = false;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_allowed) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Corvia'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 560,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.outlineVariant,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 34,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 22),

                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    widget.description,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Core clinical and emergency access remains available.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Access could not be verified. Please try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _check,
                        icon: const Icon(
                          Icons.refresh_rounded,
                        ),
                        label: const Text(
                          'Check again',
                        ),
                      ),

                      if (widget.onUpgrade != null)
                        FilledButton.icon(
                          onPressed: widget.onUpgrade,
                          icon: const Icon(
                            Icons.workspace_premium_rounded,
                          ),
                          label: const Text(
                            'View Corvia plans',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}