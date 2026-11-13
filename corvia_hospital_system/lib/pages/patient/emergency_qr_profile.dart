import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/qr_scanner_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../widgets/status_view.dart';

class EmergencyQrProfilePage extends StatefulWidget {
  const EmergencyQrProfilePage({super.key});

  @override
  State<EmergencyQrProfilePage> createState() => _EmergencyQrProfilePageState();
}

class _EmergencyQrProfilePageState extends State<EmergencyQrProfilePage> {
  final _patientNameController = TextEditingController();
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _currentMedicationsController = TextEditingController();
  final _medicalConditionsController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _medicalAidProviderController = TextEditingController();
  final _medicalAidMemberNumberController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _organDonor = false;
  String? _loadError;

  String? _patientId;

  /// Empty until the patient is known. The value is derived from the patient id
  /// rather than read back from the row - see [_loadEmergencyProfile].
  String _qrValue = '';

  @override
  void initState() {
    super.initState();
    _loadEmergencyProfile();
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _currentMedicationsController.dispose();
    _medicalConditionsController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _medicalAidProviderController.dispose();
    _medicalAidMemberNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadEmergencyProfile() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final patientId = await SupabaseService.currentPatientId();

      if (patientId == null) {
        throw Exception('Patient profile not found.');
      }

      _patientId = patientId;
      _qrValue = QrPayload.emergencyProfile(patientId);

      final patient = await SupabaseService.client
          .from('patients')
          .select(
            'id, profile_id, first_name, surname, email, blood_type, allergies, medical_conditions, emergency_contact_name, emergency_contact_phone, medical_aid_provider, medical_aid_member_number',
          )
          .eq('id', patientId)
          .maybeSingle();

      Map<String, dynamic> patientMap = {};
      Map<String, dynamic> profileMap = {};

      if (patient != null) {
        patientMap = Map<String, dynamic>.from(patient);

        final profileId = patientMap['profile_id']?.toString();

        if (profileId != null && profileId.isNotEmpty) {
          try {
            final profile = await SupabaseService.client
                .from('profiles')
                .select('user_id, first_name, surname, email')
                .eq('user_id', profileId)
                .maybeSingle();

            if (profile != null) {
              profileMap = Map<String, dynamic>.from(profile);
            }
          } catch (e) {
            debugPrint('Could not load emergency profile linked profile: $e');
          }
        }
      }

      final emergency = await SupabaseService.client
          .from('emergency_profiles')
          .select()
          .eq('patient_id', patientId)
          .maybeSingle();

      final emergencyMap = emergency == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(emergency);

      final firstName = _firstNonEmpty([
        patientMap['first_name'],
        profileMap['first_name'],
      ]);

      final surname = _firstNonEmpty([
        patientMap['surname'],
        profileMap['surname'],
      ]);

      final email = _firstNonEmpty([patientMap['email'], profileMap['email']]);

      var defaultName = '$firstName $surname'.trim();

      if (defaultName.isEmpty) {
        defaultName = _nameFromEmail(email);
      }

      _patientNameController.text = _firstNonEmpty([
        emergencyMap['patient_name'],
        defaultName,
        'Not provided',
      ]);

      _bloodTypeController.text = _firstNonEmpty([
        emergencyMap['blood_type'],
        patientMap['blood_type'],
      ]);

      _allergiesController.text = _cleanDefault(
        _firstNonEmpty([
          emergencyMap['allergies'],
          _allergiesText(
            patientMap['allergies'],
          ),
          'Not provided',
        ]),
      );

      _currentMedicationsController.text = _cleanDefault(
        _firstNonEmpty([emergencyMap['current_medications'], 'Not provided']),
      );

      _medicalConditionsController.text = _cleanDefault(
        _firstNonEmpty([
          emergencyMap['medical_conditions'],
          patientMap['medical_conditions'],
          'Not provided',
        ]),
      );

      _emergencyContactNameController.text = _firstNonEmpty([
        emergencyMap['emergency_contact_name'],
        patientMap['emergency_contact_name'],
      ]);

      _emergencyContactPhoneController.text = _firstNonEmpty([
        emergencyMap['emergency_contact_phone'],
        patientMap['emergency_contact_phone'],
      ]);

      _medicalAidProviderController.text = _firstNonEmpty([
        emergencyMap['medical_aid_provider'],
        patientMap['medical_aid_provider'],
      ]);

      _medicalAidMemberNumberController.text = _firstNonEmpty([
        emergencyMap['medical_aid_member_number'],
        patientMap['medical_aid_member_number'],
      ]);

      _organDonor = emergencyMap['organ_donor'] == true;

      // qr_code_value is deliberately not read back. It is derived entirely from
      // the patient id, so the stored copy can only ever agree with what we just
      // built or be stale - and every row written before this format was fixed
      // is stale. Preferring it is what would keep those rows unscannable. The
      // column is still written on save so the row carries the current value;
      // rotating or revoking codes would need a real reason to trust it again.

      if (!mounted) return;

      setState(() {
        _loadError = null;
      });
    } catch (e) {
      debugPrint('Emergency QR load failed: $e');

      if (mounted) {
        final message = friendlyErrorMessage(
          e,
          whatFailed: "Couldn't load your emergency QR profile.",
        );

        setState(() {
          _loadError = message;
        });

        _snack(message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveEmergencyProfile() async {
    final patientId = _patientId;

    if (patientId == null) {
      _snack('Patient profile not found.');
      return;
    }

    final patientName = _patientNameController.text.trim();

    if (patientName.isEmpty) {
      _snack('Patient name is required.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final qrValue = QrPayload.emergencyProfile(patientId);

      await SupabaseService.client.from('emergency_profiles').upsert({
        'patient_id': patientId,
        'patient_name': patientName,
        'blood_type': _nullIfEmpty(_bloodTypeController.text),
        'allergies': _emptyFallback(
          _allergiesController.text,
          'No allergies listed',
        ),
        'current_medications': _emptyFallback(
          _currentMedicationsController.text,
          'No medication listed',
        ),
        'medical_conditions': _emptyFallback(
          _medicalConditionsController.text,
          'No conditions listed',
        ),
        'emergency_contact_name': _nullIfEmpty(
          _emergencyContactNameController.text,
        ),
        'emergency_contact_phone': _nullIfEmpty(
          _emergencyContactPhoneController.text,
        ),
        'medical_aid_provider': _nullIfEmpty(
          _medicalAidProviderController.text,
        ),
        'medical_aid_member_number': _nullIfEmpty(
          _medicalAidMemberNumberController.text,
        ),
        'organ_donor': _organDonor,
        'qr_code_value': qrValue,
        'is_active': true,
        'updated_at': now,
      }, onConflict: 'patient_id');

      try {
        await SupabaseService.client.from('patients').update({
          'blood_type': _nullIfEmpty(_bloodTypeController.text),
          'allergies': _allergyValues(
            _allergiesController.text,
          ),
          'medical_conditions': _nullIfEmpty(
            _medicalConditionsController.text,
          ),
          'emergency_contact_name': _nullIfEmpty(
            _emergencyContactNameController.text,
          ),
          'emergency_contact_phone': _nullIfEmpty(
            _emergencyContactPhoneController.text,
          ),
          'medical_aid_provider': _nullIfEmpty(
            _medicalAidProviderController.text,
          ),
          'medical_aid_member_number': _nullIfEmpty(
            _medicalAidMemberNumberController.text,
          ),
          'updated_at': now,
        }).eq('id', patientId);
      } catch (error, stackTrace) {
        debugPrint(
          'Emergency profile saved but patient sync failed: '
          '$error\n$stackTrace',
        );

        if (!mounted) {
          return;
        }

        Navigator.pop(context);
        _snack(
          'Emergency QR profile saved, but some linked patient details '
          'could not be synchronized.',
        );
        return;
      }

      _qrValue = qrValue;

      if (!mounted) return;

      Navigator.pop(context);
      _snack('Emergency QR profile saved.');

      setState(() {});
    } catch (e) {
      debugPrint('Emergency QR save failed: $e');

      if (mounted) {
        _snack(
          friendlyErrorMessage(
            e,
            whatFailed: "Couldn't save your emergency QR profile.",
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return '';
  }

  String _cleanDefault(String value) {
    final text = value.trim();

    if (text.toLowerCase() == 'not provided') return '';

    return text;
  }

  String _allergiesText(
    dynamic value,
  ) {
    if (value is List) {
      return value
          .map(
            (item) => item.toString().trim(),
          )
          .where(
            (item) => item.isNotEmpty,
          )
          .join(', ');
    }

    return value?.toString().trim() ?? '';
  }

  List<String>? _allergyValues(
    String value,
  ) {
    final items = value
        .split(
          RegExp(r'[,;\n]+'),
        )
        .map(
          (item) => item.trim(),
        )
        .where(
          (item) => item.isNotEmpty,
        )
        .toSet()
        .toList();

    return items.isEmpty ? null : items;
  }

  String _nameFromEmail(String email) {
    final beforeAt = email.split('@').first.trim();

    if (beforeAt.isEmpty) return '';

    return beforeAt
        .split(RegExp(r'[._\-\s]+'))
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
      final lower = part.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    }).join(' ');
  }

  String? _nullIfEmpty(String text) {
    final value = text.trim();
    return value.isEmpty ? null : value;
  }

  String _emptyFallback(String text, String fallback) {
    final value = text.trim();
    return value.isEmpty ? fallback : value;
  }

  void _snack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _displayPatientName {
    return _firstNonEmpty([_patientNameController.text, 'Not provided']);
  }

  String get _displayBloodType {
    return _firstNonEmpty([_bloodTypeController.text, 'Not provided']);
  }

  String get _displayAllergies {
    return _firstNonEmpty([_allergiesController.text, 'No allergies listed']);
  }

  String get _displayCurrentMedication {
    return _firstNonEmpty([
      _currentMedicationsController.text,
      'No medication listed',
    ]);
  }

  String get _displayMedicalConditions {
    return _firstNonEmpty([
      _medicalConditionsController.text,
      'No conditions listed',
    ]);
  }

  String get _displayEmergencyContact {
    final name = _emergencyContactNameController.text.trim();
    final phone = _emergencyContactPhoneController.text.trim();

    if (name.isEmpty && phone.isEmpty) return 'No emergency contact listed';
    if (name.isEmpty) return phone;
    if (phone.isEmpty) return name;

    return '$name • $phone';
  }

  String get _displayMedicalAid {
    final provider = _medicalAidProviderController.text.trim();
    final member = _medicalAidMemberNumberController.text.trim();

    if (provider.isEmpty && member.isEmpty) return 'No medical aid listed';
    if (provider.isEmpty) return member;
    if (member.isEmpty) return provider;

    return '$provider • $member';
  }

  void _showEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cBgPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        height: 4,
                        width: 44,
                        decoration: BoxDecoration(
                          color: context.cTextMuted,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Edit Emergency QR Profile',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _field(
                        controller: _patientNameController,
                        label: 'Patient Name',
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _bloodTypeController,
                        label: 'Blood Type',
                        hint: 'e.g. O+, A-, B+',
                        icon: Icons.bloodtype,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _allergiesController,
                        label: 'Allergies',
                        hint: 'e.g. Penicillin, peanuts',
                        icon: Icons.warning_amber,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _currentMedicationsController,
                        label: 'Current Medication',
                        hint: 'e.g. Metformin, inhaler',
                        icon: Icons.medication,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _medicalConditionsController,
                        label: 'Medical Conditions',
                        hint: 'e.g. Asthma, diabetes',
                        icon: Icons.local_hospital,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _emergencyContactNameController,
                        label: 'Emergency Contact Name',
                        icon: Icons.contact_emergency,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _emergencyContactPhoneController,
                        label: 'Emergency Contact Phone',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _medicalAidProviderController,
                        label: 'Medical Aid Provider',
                        icon: Icons.health_and_safety,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _medicalAidMemberNumberController,
                        label: 'Medical Aid Member Number',
                        icon: Icons.badge,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _organDonor,
                        activeThumbColor: CorviaColors.accent,
                        onChanged: (value) {
                          setState(() {
                            _organDonor = value;
                          });
                          setSheetState(() {});
                        },
                        title: Text(
                          'Organ Donor',
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          _organDonor ? 'Yes' : 'No',
                          style: TextStyle(color: context.cTextSecondary),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveEmergencyProfile,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(_saving ? 'Saving...' : 'Save Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(
        color: context.cTextPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: CorviaColors.accent,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: context.cTextSecondary),
        hintStyle: TextStyle(color: context.cTextMuted),
        prefixIcon: Icon(icon, color: CorviaColors.accentLight),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Emergency QR Profile'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadEmergencyProfile,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _loading || _loadError != null || _patientId == null
                ? null
                : _showEditSheet,
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Emergency Profile',
          ),
        ],
      ),
      body: _loading
          ? StatusView.loading(message: 'Loading your emergency QR profile...')
          : _loadError != null
              ? StatusView.error(
                  friendlyMessage: _loadError!,
                  onRetry: _loadEmergencyProfile,
                )
              : RefreshIndicator(
                  onRefresh: _loadEmergencyProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: context.cBgSecondary,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: CorviaColors.divider),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                // Never draw a code for an empty payload: it would
                                // scan as a valid QR carrying nothing, which is
                                // worse than showing no code at all.
                                child: _qrValue.isEmpty
                                    ? const SizedBox(
                                        width: 190,
                                        height: 190,
                                        child: Center(
                                          child: Text(
                                            'QR unavailable',
                                            style: TextStyle(
                                                color: Colors.black54),
                                          ),
                                        ),
                                      )
                                    : QrImageView(
                                        data: _qrValue,
                                        version: QrVersions.auto,
                                        size: 190,
                                        backgroundColor: Colors.white,
                                      ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Emergency Medical QR',
                                style: TextStyle(
                                  color: context.cTextPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Emergency staff can scan this to view important patient information.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.cTextSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _InfoTile(
                          icon: Icons.person,
                          title: 'Patient Name',
                          value: _displayPatientName,
                        ),
                        _InfoTile(
                          icon: Icons.bloodtype,
                          title: 'Blood Type',
                          value: _displayBloodType,
                        ),
                        _InfoTile(
                          icon: Icons.warning_amber,
                          title: 'Allergies',
                          value: _displayAllergies,
                        ),
                        _InfoTile(
                          icon: Icons.medication,
                          title: 'Current Medication',
                          value: _displayCurrentMedication,
                        ),
                        _InfoTile(
                          icon: Icons.local_hospital,
                          title: 'Medical Conditions',
                          value: _displayMedicalConditions,
                        ),
                        _InfoTile(
                          icon: Icons.phone,
                          title: 'Emergency Contact',
                          value: _displayEmergencyContact,
                        ),
                        _InfoTile(
                          icon: Icons.health_and_safety,
                          title: 'Medical Aid',
                          value: _displayMedicalAid,
                        ),
                        _InfoTile(
                          icon: Icons.volunteer_activism,
                          title: 'Organ Donor',
                          value: _organDonor ? 'Yes' : 'No',
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _showEditSheet,
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit Emergency Details'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CorviaColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: CorviaColors.accentLight, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: context.cTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
