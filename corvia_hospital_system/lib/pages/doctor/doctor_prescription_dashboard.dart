import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/prescription_model.dart';
import '../../repositories/prescription_repository.dart';
import '../../responsive_layout.dart';
import '../../theme/app_theme.dart';

/// A comprehensive dashboard for doctors to manage patient prescriptions.
/// Allows viewing all prescriptions, filtering by patient or status,
/// and creating new ones.
class DoctorPrescriptionDashboard extends StatefulWidget {
  final String doctorName;
  final String doctorSpecialization;
  final String doctorLocation;

  const DoctorPrescriptionDashboard({
    super.key,
    this.doctorName = 'Dr. Smith',
    this.doctorSpecialization = 'General Practitioner',
    this.doctorLocation = 'Corvia Medical Center',
  });

  @override
  State<DoctorPrescriptionDashboard> createState() =>
      _DoctorPrescriptionDashboardState();
}

class _DoctorPrescriptionDashboardState
    extends State<DoctorPrescriptionDashboard> {
  final List<Prescription> _prescriptions = [];
  final List<Patient> _patients = [];

  Patient? _selectedPatient;

  String _searchQuery = '';
  String _sortBy = 'date';
  bool _sortAscending = false;
  String _statusFilter = 'all';

  final PrescriptionRepository _prescriptionRepository =
      PrescriptionRepository();

  final SupabaseClient _supabase = Supabase.instance.client;

  String? _currentDoctorId;
  bool _isLoading = true;
  bool _patientsLoadError = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final doctorData = await _supabase
          .from('doctors')
          .select('id')
          .eq('profile_id', user.id)
          .single();

      _currentDoctorId = doctorData['id']?.toString();

      if (_currentDoctorId == null || _currentDoctorId!.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      await _prescriptionRepository.autoCompleteExpired(
        _currentDoctorId!,
      );

      await Future.wait([
        _loadPatients(),
        _loadPrescriptions(),
      ]);
    } catch (e) {
      debugPrint('Error initializing prescription data: $e');

      if (!mounted) {
        return;
      }

      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPatients() async {
    if (_currentDoctorId == null) {
      return;
    }

    if (mounted) {
      setState(() => _patientsLoadError = false);
    }

    try {
      final results = await Future.wait([
        _supabase
            .from('prescriptions')
            .select('patient_id')
            .eq('doctor_id', _currentDoctorId!),
        _supabase
            .from('appointments')
            .select('patient_id')
            .eq('doctor_id', _currentDoctorId!),
      ]);

      final rxRows = results[0] as List;
      final appointmentRows = results[1] as List;

      final patientIds = <String>{
        for (final row in rxRows) row['patient_id']?.toString() ?? '',
        for (final row in appointmentRows) row['patient_id']?.toString() ?? '',
      }..remove('');

      if (patientIds.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _patients.clear();
          _selectedPatient = null;
        });
        return;
      }

      final patientRows = await _supabase
          .from('patients')
          .select(
            'id, profile_id, date_of_birth, gender, primary_condition',
          )
          .inFilter(
            'id',
            patientIds.toList(),
          );

      final profileUserIds = <String>{
        for (final row in patientRows as List)
          row['profile_id']?.toString() ?? '',
      }..remove('');

      final profilesByUserId = <String, Map<String, dynamic>>{};

      if (profileUserIds.isNotEmpty) {
        final profileRows = await _supabase
            .from('profiles')
            .select(
              'user_id, first_name, surname',
            )
            .inFilter(
              'user_id',
              profileUserIds.toList(),
            );

        for (final row in profileRows as List) {
          final userId = row['user_id']?.toString() ?? '';

          if (userId.isNotEmpty) {
            profilesByUserId[userId] = Map<String, dynamic>.from(row);
          }
        }
      }

      final loadedPatients = <Patient>[];

      for (final row in patientRows as List) {
        final patient = Map<String, dynamic>.from(row);

        final patientId = patient['id']?.toString() ?? '';

        final profileId = patient['profile_id']?.toString() ?? '';

        final profile = profilesByUserId[profileId];

        final firstName = profile?['first_name']?.toString().trim() ?? '';

        final surname = profile?['surname']?.toString().trim() ?? '';

        final fullName = '$firstName $surname'.trim();

        final dateOfBirthRaw = patient['date_of_birth']?.toString();

        final birthDate = dateOfBirthRaw == null
            ? null
            : DateTime.tryParse(
                dateOfBirthRaw,
              );

        final condition = patient['primary_condition']?.toString().trim() ?? '';

        loadedPatients.add(
          Patient(
            id: patientId,
            name: fullName.isEmpty ? 'Unknown Patient' : fullName,
            age: birthDate == null ? 0 : _calculateAge(birthDate),
            gender: patient['gender']?.toString() ?? 'Unknown',
            lastVisit: DateTime.now(),
            condition: condition.isEmpty ? 'No condition specified' : condition,
            imageUrl: '',
          ),
        );
      }

      loadedPatients.sort(
        (first, second) => first.name.compareTo(second.name),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _patients
          ..clear()
          ..addAll(loadedPatients);

        if (_selectedPatient != null) {
          final selectedPatientId = _selectedPatient!.id;

          final matches = _patients.where(
            (patient) => patient.id == selectedPatientId,
          );

          _selectedPatient = matches.isEmpty ? null : matches.first;
        }
      });
    } catch (e) {
      debugPrint(
        'Error loading prescription patients: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() => _patientsLoadError = true);
    }
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();

    var age = now.year - birthDate.year;

    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }

    return age < 0 ? 0 : age;
  }

  Future<void> _loadPrescriptions() async {
    try {
      if (_currentDoctorId == null) {
        return;
      }

      final prescriptionsData = await _supabase
          .from('prescriptions')
          .select()
          .eq(
            'doctor_id',
            _currentDoctorId!,
          )
          .order(
            'issued_at',
            ascending: false,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _prescriptions
          ..clear()
          ..addAll(
            (prescriptionsData as List).map(
              (data) => Prescription.fromMap(
                Map<String, dynamic>.from(data),
              ),
            ),
          );

        _isLoading = false;
      });
    } catch (e) {
      debugPrint(
        'Error loading prescriptions: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't load prescriptions - please try again.",
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshPage() async {
    await Future.wait([
      _loadPatients(),
      _loadPrescriptions(),
    ]);
  }

  void _handlePrescriptionAdded(
    Prescription prescription,
  ) async {
    try {
      await _prescriptionRepository.createPrescription(
        prescription,
      );

      await _refreshPage();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Prescription created for '
            '${prescription.medicationName}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint(
        'createPrescription failed: '
        '$e\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _prescriptionSaveError(
              e,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _prescriptionSaveError(
    Object error,
  ) {
    final cleaned = error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Failed to create prescription: ', '')
        .trim();
    final lower = cleaned.toLowerCase();

    if (lower.contains('row-level security') ||
        lower.contains('permission denied') ||
        lower.contains('not authorized') ||
        lower.contains('not authorised')) {
      return 'You do not have permission to create prescriptions for this '
          'patient. Confirm the doctor, hospital and patient link.';
    }

    if (lower.contains('another hospital') ||
        lower.contains('hospital id is missing')) {
      return 'This prescription cannot be created because the doctor and '
          'patient are not linked to the same hospital.';
    }

    if (lower.contains('doctor record') || lower.contains('doctor id')) {
      return 'Your signed-in account is not linked to a valid active doctor '
          'record.';
    }

    if (lower.contains('must start as active')) {
      return 'A new prescription must have Active status.';
    }

    if (lower.contains('repeatable prescription')) {
      return 'Enter at least one allowed refill for a repeatable prescription.';
    }

    if (cleaned.isNotEmpty) {
      return "We couldn't save that prescription: $cleaned";
    }

    return "We couldn't save that prescription. Please try again.";
  }

  void _handlePrescriptionEdited(
    Prescription prescription,
  ) async {
    try {
      await _prescriptionRepository.updatePrescription(
        prescription,
      );

      await _loadPrescriptions();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Prescription updated',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint(
        'updatePrescription failed: '
        '$e\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "We couldn't update that prescription. "
            'Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleFulfillRefill(
    Prescription prescription,
  ) async {
    if (prescription.id.trim().isEmpty) {
      _showMessage(
        'This prescription has no valid ID.',
        isError: true,
      );
      return;
    }

    if (prescription.refillsRemaining <= 0) {
      _showMessage(
        'There are no refills remaining.',
        isError: true,
      );
      return;
    }

    try {
      await _prescriptionRepository.fulfillRefill(
        prescriptionId: prescription.id,
      );

      await _loadPrescriptions();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Refill fulfilled',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint(
        'fulfillRefill failed: '
        '$e\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "We couldn't fulfil that refill. "
            'Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleDeclineRefill(
    String prescriptionId,
  ) async {
    if (prescriptionId.trim().isEmpty) {
      _showMessage(
        'This prescription has no valid ID.',
        isError: true,
      );
      return;
    }

    try {
      await _prescriptionRepository.declineRefill(
        prescriptionId,
      );

      await _loadPrescriptions();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Refill request declined',
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint(
        'declineRefill failed: '
        '$e\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "We couldn't decline that refill. "
            'Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleStatusUpdated(
    String prescriptionId,
    String status,
  ) async {
    final doctorId = _currentDoctorId;

    if (doctorId == null || doctorId.isEmpty || prescriptionId.trim().isEmpty) {
      _showMessage(
        'The prescription or doctor record is invalid.',
        isError: true,
      );
      return;
    }

    try {
      await _prescriptionRepository.updatePrescriptionStatus(
        prescriptionId: prescriptionId,
        status: status,
        performedBy: doctorId,
      );

      await _loadPrescriptions();
    } catch (e, stackTrace) {
      debugPrint(
        'updatePrescriptionStatus failed '
        '($prescriptionId → $status): '
        '$e\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "We couldn't update that prescription. "
            'Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handlePrescriptionDeleted(
    String prescriptionId,
  ) async {
    if (prescriptionId.trim().isEmpty) {
      _showMessage(
        'This prescription has no valid ID.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete Prescription',
          ),
          content: const Text(
            'Are you sure you want to delete this '
            'prescription? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: CorviaColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(
                Icons.delete_outline_rounded,
              ),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _prescriptionRepository.deletePrescription(
        prescriptionId,
      );

      await _loadPrescriptions();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Prescription deleted successfully',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint(
        'deletePrescription failed '
        '($prescriptionId): '
        '$e\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "We couldn't delete that prescription. "
            'Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Prescription> get _filteredPrescriptions {
    final query = _searchQuery.toLowerCase();

    final filtered = _prescriptions.where((prescription) {
      final matchesPatient = _selectedPatient == null ||
          prescription.patientId == _selectedPatient!.id;

      final matchesSearch = query.isEmpty ||
          prescription.medicationName.toLowerCase().contains(query) ||
          prescription.dosage.toLowerCase().contains(query);

      final matchesStatus = _statusFilter == 'all' ||
          prescription.effectiveStatus == _statusFilter;

      return matchesPatient && matchesSearch && matchesStatus;
    }).toList();

    filtered.sort((first, second) {
      late int comparison;

      switch (_sortBy) {
        case 'name':
          comparison = first.medicationName.compareTo(
            second.medicationName,
          );
          break;

        case 'status':
          comparison = first.status.compareTo(
            second.status,
          );
          break;

        case 'date':
        default:
          comparison = first.issuedAt.compareTo(
            second.issuedAt,
          );
      }

      return _sortAscending ? comparison : -comparison;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context);

    final isTablet = ResponsiveLayout.isTablet(context);

    final screenPadding = ResponsiveLayout.getScreenPadding(context);

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          'Prescription Management',
          style: TextStyle(
            color: context.cTextPrimary,
            fontSize: ResponsiveLayout.responsiveValue(
              context,
              mobile: 18.0,
              tablet: 20.0,
              desktop: 22.0,
            ),
          ),
        ),
        backgroundColor: context.cBgSecondary,
        foregroundColor: context.cTextPrimary,
        actions: [
          IconButton(
            tooltip: 'Refresh prescriptions',
            onPressed: _isLoading ? null : _refreshPage,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
          if (_selectedPatient != null)
            IconButton(
              icon: Icon(
                Icons.add,
                size: ResponsiveLayout.getIconSize(
                  context,
                ),
              ),
              onPressed: _showCreatePrescriptionDialog,
              tooltip: 'New Prescription',
            ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.sort,
              size: ResponsiveLayout.getIconSize(
                context,
              ),
            ),
            onSelected: (value) {
              setState(() {
                if (value == 'toggle_sort') {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = value;
                }
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: _sortBy == 'date' ? Colors.blue : null,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Date'),
                    if (_sortBy == 'date') ...[
                      const SizedBox(width: 8),
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(
                      Icons.medication,
                      color: _sortBy == 'name' ? Colors.blue : null,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Sort by Medication',
                    ),
                    if (_sortBy == 'name') ...[
                      const SizedBox(width: 8),
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'status',
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      color: _sortBy == 'status' ? Colors.blue : null,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Sort by Status',
                    ),
                    if (_sortBy == 'status') ...[
                      const SizedBox(width: 8),
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'toggle_sort',
                child: Row(
                  children: [
                    Icon(
                      _sortAscending
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _sortAscending ? 'Descending' : 'Ascending',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Row(
              children: [
                if (isDesktop || isTablet) _buildPatientSidebar(context),
                Expanded(
                  // A plain Column overflowed on phones: the header, patient
                  // picker and search are fixed height and together fill the
                  // screen. As header slivers they scroll away instead.
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverToBoxAdapter(
                        child: Container(
                          width: double.infinity,
                          padding: screenPadding,
                          decoration: BoxDecoration(
                            color: context.cBgSecondary,
                            border: Border(
                              bottom: BorderSide(
                                color: context.cDivider,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: context.cCardShadow,
                                blurRadius: 10,
                                offset: const Offset(
                                  0,
                                  4,
                                ),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome, '
                                '${widget.doctorName}',
                                style: TextStyle(
                                  color: context.cTextPrimary,
                                  fontSize: ResponsiveLayout.responsiveValue(
                                    context,
                                    mobile: 22.0,
                                    tablet: 24.0,
                                    desktop: 26.0,
                                  ),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                '${widget.doctorSpecialization} • '
                                '${widget.doctorLocation}',
                                style: TextStyle(
                                  color: context.cTextSecondary,
                                  fontSize: ResponsiveLayout.responsiveValue(
                                    context,
                                    mobile: 14.0,
                                    tablet: 15.0,
                                    desktop: 16.0,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 16,
                              ),
                              _buildStatsOverview(),
                            ],
                          ),
                        ),
                      ),
                      if (!isDesktop && !isTablet)
                        SliverToBoxAdapter(
                          child: _buildMobilePatientSelection(),
                        ),
                      if (_selectedPatient != null)
                        SliverToBoxAdapter(
                          child: _buildSearchSection(),
                        ),
                    ],
                    body: _selectedPatient == null
                        ? _buildNoPatientSelected()
                        : _filteredPrescriptions.isEmpty
                            ? _buildEmptyState()
                            : _buildPrescriptionsList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPatientSidebar(
    BuildContext context,
  ) {
    return Container(
      width: ResponsiveLayout.responsiveValue(
        context,
        mobile: 280.0,
        tablet: 300.0,
        desktop: 320.0,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        border: Border(
          right: BorderSide(
            color: context.cDivider,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select Patient',
              style: TextStyle(
                color: context.cAccentReadable,
                fontSize: ResponsiveLayout.responsiveValue(
                  context,
                  mobile: 18.0,
                  tablet: 19.0,
                  desktop: 20.0,
                ),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: _buildPatientSelectionVertical(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobilePatientSelection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: context.cBgSecondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Patient',
            style: TextStyle(
              color: context.cAccentReadable,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildPatientSelectionVertical(),
        ],
      ),
    );
  }

  Widget _buildStatsOverview() {
    final patientCount = _patients.length;

    if (_selectedPatient == null) {
      return SizedBox(
        height: ResponsiveLayout.getCardHeight(
          context,
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                'Patients',
                patientCount.toString(),
                Colors.blueAccent,
              ),
            ),
          ],
        ),
      );
    }

    final patientPrescriptions = _prescriptions
        .where(
          (item) => item.patientId == _selectedPatient!.id,
        )
        .toList();

    final activeCount = patientPrescriptions
        .where(
          (item) => item.effectiveStatus == 'active',
        )
        .length;

    final completedCount = patientPrescriptions
        .where(
          (item) => item.effectiveStatus == 'completed',
        )
        .length;

    final cancelledCount = patientPrescriptions
        .where(
          (item) => item.effectiveStatus == 'cancelled',
        )
        .length;

    return SizedBox(
      height: ResponsiveLayout.getCardHeight(
        context,
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              'Patients',
              patientCount.toString(),
              Colors.blueAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatItem(
              'Active',
              activeCount.toString(),
              Colors.greenAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatItem(
              'Completed',
              completedCount.toString(),
              Colors.blueAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatItem(
              'Cancelled',
              cancelledCount.toString(),
              Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String title,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(
            alpha: 0.22,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: ResponsiveLayout.responsiveValue(
                context,
                mobile: 16.0,
                tablet: 17.0,
                desktop: 18.0,
              ),
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: ResponsiveLayout.responsiveValue(
                context,
                mobile: 10.0,
                tablet: 11.0,
                desktop: 12.0,
              ),
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPatientSelectionVertical() {
    if (_patientsLoadError) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              color: context.cTextSecondary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              "Couldn't load patients.\n"
              'Check your connection.',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadPatients,
              icon: Icon(
                Icons.refresh,
                size: 16,
                color: context.cAccentReadable,
              ),
              label: Text(
                'Retry',
                style: TextStyle(
                  color: context.cAccentReadable,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_patients.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              color: context.cTextSecondary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              'No patients yet.\n'
              'Patients appear here once you have a '
              'prescription or appointment with them.',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: ResponsiveLayout.responsiveValue(
        context,
        mobile: 200.0,
        tablet: 250.0,
        desktop: 300.0,
      ),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          10,
          4,
          10,
          16,
        ),
        itemCount: _patients.length,
        itemBuilder: (context, index) {
          final patient = _patients[index];

          final isSelected = _selectedPatient?.id == patient.id;

          final condition = patient.condition.trim().isEmpty
              ? 'No condition specified'
              : patient.condition.trim();

          return Padding(
            padding: const EdgeInsets.only(
              bottom: 8,
            ),
            child: Material(
              color: isSelected ? CorviaColors.accent : context.cBgPrimary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _selectedPatient = isSelected ? null : patient;

                    _searchQuery = '';
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(
                    12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                    border: Border.all(
                      color:
                          isSelected ? CorviaColors.accent : context.cDivider,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      _PatientAvatar(
                        patient: patient,
                        radius: ResponsiveLayout.responsiveValue(
                          context,
                          mobile: 18.0,
                          tablet: 20.0,
                          desktop: 22.0,
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patient.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : context.cTextPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: ResponsiveLayout.responsiveValue(
                                  context,
                                  mobile: 14.0,
                                  tablet: 15.0,
                                  desktop: 16.0,
                                ),
                              ),
                            ),
                            const SizedBox(
                              height: 2,
                            ),
                            Text(
                              '${patient.age} years • '
                              '${patient.gender}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white.withValues(
                                        alpha: 0.85,
                                      )
                                    : context.cTextSecondary,
                                fontSize: ResponsiveLayout.responsiveValue(
                                  context,
                                  mobile: 11.0,
                                  tablet: 12.0,
                                  desktop: 13.0,
                                ),
                              ),
                            ),
                            const SizedBox(
                              height: 2,
                            ),
                            Text(
                              condition,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white.withValues(
                                        alpha: 0.90,
                                      )
                                    : context.cAccentReadable,
                                fontSize: ResponsiveLayout.responsiveValue(
                                  context,
                                  mobile: 10.0,
                                  tablet: 11.0,
                                  desktop: 12.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(
                          width: 8,
                        ),
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: ResponsiveLayout.getIconSize(
                            context,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchSection() {
    final isDesktop = ResponsiveLayout.isDesktop(context);

    return Container(
      padding: const EdgeInsets.all(16),
      color: context.cBgSecondary,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: ResponsiveLayout.getButtonHeight(
                context,
              ),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search prescriptions...',
                  hintStyle: TextStyle(
                    color: context.cTextSecondary,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: context.cTextSecondary,
                  ),
                  filled: true,
                  fillColor: context.cBgPrimary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.cDivider,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.cDivider,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.cAccentReadable,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                  ),
                ),
                style: TextStyle(
                  color: context.cTextPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (isDesktop) ...[
            Container(
              decoration: BoxDecoration(
                color: context.cBgPrimary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: PopupMenuButton<String>(
                icon: Icon(
                  _statusFilter == 'all'
                      ? Icons.filter_list
                      : Icons.filter_list_alt,
                  color: _statusFilter == 'all'
                      ? context.cTextSecondary
                      : context.cAccentReadable,
                ),
                tooltip: _statusFilter == 'all'
                    ? 'Filter by status'
                    : 'Filter: $_statusFilter',
                onSelected: (value) {
                  setState(() {
                    _statusFilter = value;
                  });
                },
                itemBuilder: (context) => [
                  _filterItem(
                    'all',
                    'All Prescriptions',
                    Icons.list_alt,
                  ),
                  _filterItem(
                    'active',
                    'Active Only',
                    Icons.check_circle,
                    Colors.green,
                  ),
                  _filterItem(
                    'completed',
                    'Completed Only',
                    Icons.verified,
                    Colors.blue,
                  ),
                  _filterItem(
                    'cancelled',
                    'Cancelled Only',
                    Icons.cancel,
                    Colors.red,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<String> _filterItem(
    String value,
    String label,
    IconData icon, [
    Color? color,
  ]) {
    final isSelected = _statusFilter == value;

    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: color ?? context.cTextSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label),
          ),
          if (isSelected)
            Icon(
              Icons.check,
              size: 18,
              color: context.cAccentReadable,
            ),
        ],
      ),
    );
  }

  Widget _buildNoPatientSelected() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  color: context.cTextSecondary,
                  size: ResponsiveLayout.responsiveValue(
                    context,
                    mobile: 60.0,
                    tablet: 70.0,
                    desktop: 80.0,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select a Patient',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: ResponsiveLayout.responsiveValue(
                      context,
                      mobile: 18.0,
                      tablet: 20.0,
                      desktop: 22.0,
                    ),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                  ),
                  child: Text(
                    'Choose a patient from the list above to view\n'
                    'and manage their prescriptions',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: ResponsiveLayout.responsiveValue(
                        context,
                        mobile: 14.0,
                        tablet: 15.0,
                        desktop: 16.0,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrescriptionsList() {
    return ListView.builder(
      padding: ResponsiveLayout.getScreenPadding(
        context,
      ),
      itemCount: _filteredPrescriptions.length,
      itemBuilder: (context, index) {
        return _buildPrescriptionItem(
          _filteredPrescriptions[index],
        );
      },
    );
  }

  Widget _buildPrescriptionItem(
    Prescription prescription,
  ) {
    final patient = _patients.firstWhere(
      (item) => item.id == prescription.patientId,
      orElse: () => Patient(
        id: '',
        name: 'Unknown',
        age: 0,
        gender: '',
        lastVisit: DateTime.now(),
        condition: '',
        imageUrl: '',
      ),
    );

    final medicineCount = prescription.allMedicines.length;

    final title = medicineCount > 1
        ? '$medicineCount medications'
        : prescription.medicationName;

    final subtitleMedicines = medicineCount > 1
        ? prescription.allMedicines
            .map(
              (item) => item.name,
            )
            .join(', ')
        : '${prescription.dosage} • '
            '${prescription.frequency}';

    return Card(
      color: context.cBgSecondary,
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _getStatusColor(
                    prescription.effectiveStatus,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(
                title,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitleMedicines,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'For: ${patient.name}',
                    style: TextStyle(
                      color: context.cAccentReadable,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    'Issued: '
                    '${_formatDate(prescription.issuedAt)}'
                    '${prescription.refillable ? ' • ${prescription.refillsRemaining} refill(s) left' : ''}',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: context.cTextSecondary,
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditPrescriptionDialog(
                      prescription,
                    );
                  } else if (value == 'delete') {
                    _handlePrescriptionDeleted(
                      prescription.id,
                    );
                  } else if (value.startsWith('status_')) {
                    _handleStatusUpdated(
                      prescription.id,
                      value.replaceFirst(
                        'status_',
                        '',
                      ),
                    );
                  }
                },
                itemBuilder: (context) {
                  // The repository rejects a change to the status the row
                  // already has, so do not offer it. Compare the stored
                  // status, not effectiveStatus: an expired course shows as
                  // completed but is stored as active and can still be completed.
                  final currentStatus =
                      prescription.status.trim().toLowerCase();

                  return [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit,
                            color: Colors.blueAccent,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    if (currentStatus != 'active')
                      const PopupMenuItem(
                        value: 'status_active',
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text('Mark Active'),
                          ],
                        ),
                      ),
                    if (currentStatus != 'completed')
                      const PopupMenuItem(
                        value: 'status_completed',
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified,
                              color: Colors.blue,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Mark Completed',
                            ),
                          ],
                        ),
                      ),
                    if (currentStatus != 'cancelled')
                      const PopupMenuItem(
                        value: 'status_cancelled',
                        child: Row(
                          children: [
                            Icon(
                              Icons.cancel,
                              color: Colors.red,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Mark Cancelled',
                            ),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
              onTap: () {
                _showPrescriptionDetails(
                  prescription,
                  patient,
                );
              },
            ),
            if (prescription.refillRequested)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  12,
                ),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CorviaColors.warning.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: CorviaColors.warning.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.autorenew,
                      color: CorviaColors.warning,
                      size: 18,
                    ),
                    Text(
                      'Refill requested by patient',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 12,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _handleDeclineRefill(
                          prescription.id,
                        );
                      },
                      child: const Text('Decline'),
                    ),
                    ElevatedButton(
                      onPressed: prescription.refillsRemaining > 0
                          ? () {
                              _handleFulfillRefill(
                                prescription,
                              );
                            }
                          : null,
                      child: const Text('Fulfil'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.medication_outlined,
                  color: context.cTextSecondary,
                  size: ResponsiveLayout.responsiveValue(
                    context,
                    mobile: 60.0,
                    tablet: 70.0,
                    desktop: 80.0,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Prescriptions for '
                  '${_selectedPatient?.name}',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: ResponsiveLayout.responsiveValue(
                      context,
                      mobile: 18.0,
                      tablet: 20.0,
                      desktop: 22.0,
                    ),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create the first prescription '
                  'for this patient',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: ResponsiveLayout.responsiveValue(
                      context,
                      mobile: 14.0,
                      tablet: 15.0,
                      desktop: 16.0,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Create Prescription',
                  ),
                  onPressed: _showCreatePrescriptionDialog,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreatePrescriptionDialog() {
    final patient = _selectedPatient;
    final doctorId = _currentDoctorId;

    if (patient == null || doctorId == null || doctorId.isEmpty) {
      _showMessage(
        'Select a patient first.',
        isError: true,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => CreatePrescriptionDialog(
        patient: patient,
        doctorId: doctorId,
        onSaved: _handlePrescriptionAdded,
      ),
    );
  }

  void _showEditPrescriptionDialog(
    Prescription existing,
  ) {
    final doctorId = _currentDoctorId;

    if (doctorId == null || doctorId.isEmpty) {
      _showMessage(
        'The doctor record is unavailable.',
        isError: true,
      );
      return;
    }

    final patient = _patients.firstWhere(
      (item) => item.id == existing.patientId,
      orElse: () =>
          _selectedPatient ??
          Patient(
            id: existing.patientId,
            name: 'Patient',
            age: 0,
            gender: '',
            lastVisit: DateTime.now(),
            condition: '',
            imageUrl: '',
          ),
    );

    showDialog(
      context: context,
      builder: (context) => CreatePrescriptionDialog(
        patient: patient,
        doctorId: doctorId,
        existing: existing,
        onSaved: _handlePrescriptionEdited,
      ),
    );
  }

  void _showPrescriptionDetails(
    Prescription prescription,
    Patient patient,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          prescription.medicationName,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                'Patient:',
                patient.name,
              ),
              _buildDetailRow(
                'Dosage:',
                prescription.dosage,
              ),
              _buildDetailRow(
                'Frequency:',
                prescription.frequency,
              ),
              _buildDetailRow(
                'Duration:',
                prescription.duration,
              ),
              if (prescription.notes != null)
                _buildDetailRow(
                  'Notes:',
                  prescription.notes!,
                ),
              _buildDetailRow(
                'Status:',
                prescription.status,
              ),
              _buildDetailRow(
                'Issued:',
                _formatDate(
                  prescription.issuedAt,
                ),
              ),
              if (prescription.refillDate != null)
                _buildDetailRow(
                  'Refill Date:',
                  _formatDate(
                    prescription.refillDate!,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.cAccentReadable,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(
    String status,
  ) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/'
        '${date.month}/'
        '${date.year}';
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? CorviaColors.danger : null,
          content: Text(message),
        ),
      );
  }
}

class CreatePrescriptionDialog extends StatefulWidget {
  final Patient patient;
  final String doctorId;
  final Prescription? existing;
  final Function(Prescription) onSaved;

  const CreatePrescriptionDialog({
    super.key,
    required this.patient,
    required this.doctorId,
    required this.onSaved,
    this.existing,
  });

  bool get isEditing => existing != null;

  @override
  State<CreatePrescriptionDialog> createState() =>
      _CreatePrescriptionDialogState();
}

class _CreatePrescriptionDialogState extends State<CreatePrescriptionDialog> {
  final List<_MedicineGroup> _medicines = [];

  final TextEditingController _notesController = TextEditingController();

  final TextEditingController _refillsController =
      TextEditingController(text: '0');

  String _selectedStatus = 'active';

  bool _refillable = false;

  DateTime? _endDate;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    if (existing != null) {
      for (final medicine in existing.allMedicines) {
        _medicines.add(
          _MedicineGroup(
            name: medicine.name,
            dosage: medicine.dosage,
            frequency: medicine.frequency,
            duration: medicine.duration,
          ),
        );
      }

      if (_medicines.isEmpty) {
        _medicines.add(
          _MedicineGroup(),
        );
      }

      _notesController.text = existing.notes ?? '';

      _selectedStatus = existing.status;

      _refillable = existing.refillable;

      _refillsController.text = existing.refillsAllowed.toString();

      _endDate = existing.endDate;
    } else {
      _medicines.add(
        _MedicineGroup(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isEditing ? 'Edit Prescription' : 'Create New Prescription',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'For: ${widget.patient.name}',
            style: TextStyle(
              color: context.cAccentReadable,
              fontSize: 14,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...List.generate(
                _medicines.length,
                (index) {
                  return _buildMedicineGroup(
                    index,
                    _medicines[index],
                  );
                },
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _medicines.add(
                      _MedicineGroup(),
                    );
                  });
                },
                icon: const Icon(
                  Icons.add_circle_outline,
                ),
                label: const Text(
                  'Add another medicine',
                ),
              ),
              const SizedBox(height: 8),
              _buildField(
                controller: _notesController,
                label: 'Notes (Optional)',
                hint: 'Additional instructions or warnings',
                icon: Icons.note_outlined,
              ),
              const SizedBox(height: 12),
              _buildEndDatePicker(),
              const SizedBox(height: 12),
              _buildRefillControls(),
              const SizedBox(height: 12),
              _buildStatusDropdown(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(
            widget.isEditing ? 'Save Changes' : 'Create Prescription',
          ),
        ),
      ],
    );
  }

  Widget _buildEndDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Course ends (optional)',
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final now = DateTime.now();

            final picked = await showDatePicker(
              context: context,
              initialDate: _endDate ??
                  now.add(
                    const Duration(
                      days: 7,
                    ),
                  ),
              firstDate: now.subtract(
                const Duration(days: 1),
              ),
              lastDate: now.add(
                const Duration(days: 365),
              ),
            );

            if (picked != null) {
              setState(() {
                _endDate = picked;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: context.cBgPrimary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  color: context.cAccentReadable,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _endDate == null
                        ? "No end date - won't auto-complete"
                        : '${_endDate!.day.toString().padLeft(2, '0')}/'
                            '${_endDate!.month.toString().padLeft(2, '0')}/'
                            '${_endDate!.year}',
                    style: TextStyle(
                      color: _endDate == null
                          ? context.cTextSecondary
                          : context.cTextPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (_endDate != null)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _endDate = null;
                      });
                    },
                    child: Icon(
                      Icons.clear,
                      color: context.cTextSecondary,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRefillControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.autorenew,
                color: context.cAccentReadable,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Repeatable prescription',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              Switch(
                value: _refillable,
                onChanged: (value) {
                  setState(() {
                    _refillable = value;
                  });
                },
              ),
            ],
          ),
          if (_refillable) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Refills allowed',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _refillsController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.cTextPrimary,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicineGroup(
    int index,
    _MedicineGroup medicine,
  ) {
    final isOnlyMedicine = _medicines.length == 1;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Medicine ${index + 1}',
                style: TextStyle(
                  color: context.cAccentReadable,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (!isOnlyMedicine)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      medicine.dispose();
                      _medicines.removeAt(
                        index,
                      );
                    });
                  },
                  child: Icon(
                    Icons.remove_circle_outline,
                    color: CorviaColors.danger,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildField(
            controller: medicine.nameCtrl,
            label: 'Medication Name',
            hint: 'e.g., Amoxicillin',
            icon: Icons.medication,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildField(
                  controller: medicine.dosageCtrl,
                  label: 'Dosage',
                  hint: 'e.g., 500mg',
                  icon: Icons.science_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildField(
                  controller: medicine.durationCtrl,
                  label: 'Duration',
                  hint: 'e.g., 7 days',
                  icon: Icons.calendar_today_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildField(
            controller: medicine.freqCtrl,
            label: 'Frequency',
            hint: 'e.g., 3 times daily',
            icon: Icons.schedule_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        TextField(
          controller: controller,
          style: TextStyle(
            color: context.cTextPrimary,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
            prefixIcon: Icon(
              icon,
              color: context.cAccentReadable,
              size: 18,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status',
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        DropdownButtonFormField<String>(
          initialValue: _selectedStatus,
          items: const [
            DropdownMenuItem(
              value: 'active',
              child: Text('Active'),
            ),
            DropdownMenuItem(
              value: 'completed',
              child: Text('Completed'),
            ),
            DropdownMenuItem(
              value: 'cancelled',
              child: Text('Cancelled'),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _selectedStatus = value;
            });
          },
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            isDense: true,
          ),
        ),
      ],
    );
  }

  void _save() {
    final validMedicines = _medicines.where(
      (item) => item.nameCtrl.text.trim().isNotEmpty,
    );

    if (validMedicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please enter at least one medication name',
          ),
          backgroundColor: CorviaColors.danger,
        ),
      );
      return;
    }

    final medicines = validMedicines
        .map(
          (item) => MedicineItem(
            name: item.nameCtrl.text.trim(),
            dosage: item.dosageCtrl.text.trim(),
            frequency: item.freqCtrl.text.trim(),
            duration: item.durationCtrl.text.trim(),
          ),
        )
        .toList();

    final firstMedicine = medicines.first;

    final refillsAllowed = _refillable
        ? int.tryParse(
              _refillsController.text.trim(),
            ) ??
            0
        : 0;

    final existing = widget.existing;

    final prescription = Prescription(
      id: existing?.id ?? '',
      patientId: widget.patient.id,
      doctorId: widget.doctorId,
      medicationName: firstMedicine.name,
      dosage: firstMedicine.dosage,
      frequency: firstMedicine.frequency,
      duration: firstMedicine.duration,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      issuedAt: existing?.issuedAt ?? DateTime.now(),
      status: _selectedStatus,
      refillDate: existing?.refillDate,
      imageUrl: existing?.imageUrl,
      medicines: medicines,
      endDate: _endDate,
      refillable: _refillable,
      refillsAllowed: refillsAllowed,
      refillsUsed: existing?.refillsUsed ?? 0,
      refillRequested: existing?.refillRequested ?? false,
      refillRequestedAt: existing?.refillRequestedAt,
    );

    widget.onSaved(prescription);

    Navigator.pop(context);
  }

  @override
  void dispose() {
    for (final medicine in _medicines) {
      medicine.dispose();
    }

    _notesController.dispose();
    _refillsController.dispose();

    super.dispose();
  }
}

class _MedicineGroup {
  final TextEditingController nameCtrl;
  final TextEditingController dosageCtrl;
  final TextEditingController freqCtrl;
  final TextEditingController durationCtrl;

  _MedicineGroup({
    String name = '',
    String dosage = '',
    String frequency = '',
    String duration = '',
  })  : nameCtrl = TextEditingController(
          text: name,
        ),
        dosageCtrl = TextEditingController(
          text: dosage,
        ),
        freqCtrl = TextEditingController(
          text: frequency,
        ),
        durationCtrl = TextEditingController(
          text: duration,
        );

  void dispose() {
    nameCtrl.dispose();
    dosageCtrl.dispose();
    freqCtrl.dispose();
    durationCtrl.dispose();
  }
}

class Patient {
  final String id;
  final String name;
  final int age;
  final String gender;
  final DateTime lastVisit;
  final String condition;
  final String imageUrl;

  const Patient({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.lastVisit,
    required this.condition,
    required this.imageUrl,
  });
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({
    required this.patient,
    required this.radius,
  });

  final Patient patient;
  final double radius;

  String get _initials {
    final parts = patient.name
        .trim()
        .split(RegExp(r'\s+'))
        .where(
          (part) => part.isNotEmpty,
        )
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}'
            '${parts.last[0]}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = patient.imageUrl.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: CorviaColors.accent.withValues(
        alpha: 0.18,
      ),
      backgroundImage: hasPhoto
          ? NetworkImage(
              patient.imageUrl,
            )
          : null,
      child: hasPhoto
          ? null
          : Text(
              _initials,
              style: TextStyle(
                color: context.cAccentReadable,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.85,
              ),
            ),
    );
  }
}
