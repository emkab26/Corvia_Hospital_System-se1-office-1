import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/prescription_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

enum _PrescriptionPageState {
  normal,
  patientNotLinked,
  loadFailed,
}

class MyPrescriptionsPage extends StatefulWidget {
  const MyPrescriptionsPage({super.key});

  @override
  State<MyPrescriptionsPage> createState() => _MyPrescriptionsPageState();
}

class _MyPrescriptionsPageState extends State<MyPrescriptionsPage> {
  static const Duration _requestTimeout = Duration(seconds: 15);

  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();

  List<Prescription> _prescriptions = [];
  List<Prescription> _filteredPrescriptions = [];

  Map<String, _PrescriptionPharmacyStatus> _pharmacyByPrescriptionId = {};

  String _selectedFilter = 'all';
  String? _currentPatientId;

  bool _loading = true;
  bool _refreshing = false;

  _PrescriptionPageState _pageState = _PrescriptionPageState.normal;

  Object? _lastError;

  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(
      _filterPrescriptions,
    );

    _initialisePage(
      showFullLoader: true,
    );
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(
        _filterPrescriptions,
      )
      ..dispose();

    super.dispose();
  }

  Future<void> _initialisePage({
    required bool showFullLoader,
  }) async {
    final generation = ++_loadGeneration;

    if (mounted) {
      setState(() {
        _lastError = null;
        _pageState = _PrescriptionPageState.normal;

        if (showFullLoader || _prescriptions.isEmpty) {
          _loading = true;
          _refreshing = false;
        } else {
          _refreshing = true;
        }
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw StateError(
          'You are not signed in.',
        );
      }

      final patientResponse = await _supabase
          .from('patients')
          .select()
          .eq(
            'profile_id',
            user.id,
          )
          .maybeSingle()
          .timeout(_requestTimeout);

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      if (patientResponse == null) {
        setState(() {
          _currentPatientId = null;
          _prescriptions = [];
          _filteredPrescriptions = [];
          _pharmacyByPrescriptionId = {};
          _pageState = _PrescriptionPageState.patientNotLinked;
        });

        return;
      }

      final patientId = patientResponse['id']?.toString().trim();

      if (patientId == null || patientId.isEmpty) {
        throw StateError(
          'The linked patient record has no valid patient ID.',
        );
      }

      _currentPatientId = patientId;

      await _loadPrescriptions(
        generation: generation,
      );
    } on TimeoutException {
      _handleLoadError(
        generation,
        'The server took too long to respond. '
        'Check your connection and try again.',
      );
    } catch (error) {
      _handleLoadError(
        generation,
        error,
      );
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _loadPrescriptions({
    required int generation,
  }) async {
    final patientId = _currentPatientId;

    if (patientId == null || patientId.isEmpty) {
      throw StateError(
        'Patient ID is unavailable.',
      );
    }

    final response = await _supabase
        .from('prescriptions')
        .select()
        .eq(
          'patient_id',
          patientId,
        )
        .order(
          'issued_at',
          ascending: false,
        )
        .timeout(_requestTimeout);

    final rows = _rows(response);

    final prescriptions = <Prescription>[];

    for (final row in rows) {
      try {
        prescriptions.add(
          Prescription.fromMap(row),
        );
      } catch (error) {
        debugPrint(
          'Could not parse prescription '
          '${row['id']}: $error',
        );
      }
    }

    final pharmacyByPrescriptionId = await _loadPharmacyStatuses(
      patientId,
    );

    if (!mounted || generation != _loadGeneration) {
      return;
    }

    setState(() {
      _prescriptions = prescriptions;
      _pharmacyByPrescriptionId = pharmacyByPrescriptionId;
      _pageState = _PrescriptionPageState.normal;
    });

    _filterPrescriptions();
  }

  Future<Map<String, _PrescriptionPharmacyStatus>> _loadPharmacyStatuses(
    String patientId,
  ) async {
    try {
      final response = await _supabase
          .from('prescription_dispenses')
          .select()
          .eq(
            'patient_id',
            patientId,
          )
          .order(
            'received_at',
            ascending: false,
          )
          .timeout(_requestTimeout);

      final latestRows = <String, Map<String, dynamic>>{};

      for (final row in _rows(response)) {
        final prescriptionId = row['prescription_id']?.toString().trim();

        if (prescriptionId == null || prescriptionId.isEmpty) {
          continue;
        }

        latestRows.putIfAbsent(
          prescriptionId,
          () => row,
        );
      }

      final hospitalIds = latestRows.values
          .map(
            (row) => row['hospital_id']?.toString().trim(),
          )
          .whereType<String>()
          .where(
            (id) => id.isNotEmpty,
          )
          .toSet()
          .toList();

      final hospitals = <String, Map<String, dynamic>>{};

      if (hospitalIds.isNotEmpty) {
        try {
          final hospitalResponse = await _supabase
              .from('hospitals')
              .select('id, name, address, phone')
              .inFilter(
                'id',
                hospitalIds,
              )
              .timeout(_requestTimeout);

          for (final hospital in _rows(hospitalResponse)) {
            final id = hospital['id']?.toString().trim();

            if (id != null && id.isNotEmpty) {
              hospitals[id] = hospital;
            }
          }
        } catch (error) {
          debugPrint(
            'Prescription pharmacy hospital lookup failed: $error',
          );
        }
      }

      return latestRows.map(
        (prescriptionId, dispense) {
          final hospitalId = dispense['hospital_id']?.toString().trim();

          return MapEntry(
            prescriptionId,
            _PrescriptionPharmacyStatus(
              dispense: dispense,
              hospital: hospitalId == null ? null : hospitals[hospitalId],
            ),
          );
        },
      );
    } catch (error) {
      debugPrint(
        'Prescription pharmacy status lookup failed: $error',
      );

      return {};
    }
  }

  List<Map<String, dynamic>> _rows(
    dynamic data,
  ) {
    if (data is! List) {
      return [];
    }

    return data
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(row),
        )
        .toList();
  }

  void _handleLoadError(
    int generation,
    Object error,
  ) {
    debugPrint(
      'Prescription page load failed: $error',
    );

    if (!mounted || generation != _loadGeneration) {
      return;
    }

    setState(() {
      _lastError = error;
      _pageState = _PrescriptionPageState.loadFailed;
    });
  }

  Future<void> _refresh() {
    return _initialisePage(
      showFullLoader: false,
    );
  }

  Future<void> _retryLoading() {
    return _initialisePage(
      showFullLoader: true,
    );
  }

  void _filterPrescriptions() {
    if (!mounted) {
      return;
    }

    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredPrescriptions = _prescriptions.where(
        (prescription) {
          final status = _normaliseStatus(
            prescription.status,
          );

          final matchesSearch = query.isEmpty ||
              prescription.medicationName.toLowerCase().contains(query) ||
              prescription.dosage.toLowerCase().contains(query) ||
              prescription.frequency.toLowerCase().contains(query) ||
              prescription.duration.toLowerCase().contains(query) ||
              (prescription.notes?.toLowerCase().contains(query) ?? false);

          final matchesFilter =
              _selectedFilter == 'all' || status == _selectedFilter;

          return matchesSearch && matchesFilter;
        },
      ).toList();
    });
  }

  String _normaliseStatus(
    String? value,
  ) {
    final status = (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    switch (status) {
      case '':
        return 'active';

      case 'stopped':
      case 'discontinued':
        return 'cancelled';

      case 'expired':
        return 'expired';

      case 'complete':
        return 'completed';

      default:
        return status;
    }
  }

  String _statusLabel(
    String? value,
  ) {
    final status = _normaliseStatus(value);

    return status
        .split('_')
        .where(
          (part) => part.isNotEmpty,
        )
        .map(
          (part) => '${part[0].toUpperCase()}'
              '${part.substring(1)}',
        )
        .join(' ');
  }

  Color _statusColor(
    String? value,
  ) {
    switch (_normaliseStatus(value)) {
      case 'active':
        return CorviaColors.success;

      case 'completed':
        return Colors.blue;

      case 'cancelled':
      case 'stopped':
        return CorviaColors.danger;

      case 'expired':
        return CorviaColors.warning;

      default:
        return context.cTextSecondary;
    }
  }

  bool _needsRefill(
    Prescription prescription,
  ) {
    final refillDate = prescription.refillDate;

    if (refillDate == null) {
      return false;
    }

    if (_normaliseStatus(
          prescription.status,
        ) !=
        'active') {
      return false;
    }

    final sevenDaysFromNow = DateTime.now().add(
      const Duration(days: 7),
    );

    return refillDate.isBefore(
      sevenDaysFromNow,
    );
  }

  int? _daysUntilRefill(
    Prescription prescription,
  ) {
    final refillDate = prescription.refillDate;

    if (refillDate == null) {
      return null;
    }

    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final refillDay = DateTime(
      refillDate.year,
      refillDate.month,
      refillDate.day,
    );

    return refillDay.difference(today).inDays;
  }

  List<Prescription> get _refillPrescriptions {
    return _prescriptions.where(_needsRefill).toList();
  }

  int _countByStatus(
    String status,
  ) {
    return _prescriptions.where(
      (prescription) {
        return _normaliseStatus(
              prescription.status,
            ) ==
            status;
      },
    ).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'My Prescriptions',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh prescriptions',
            onPressed: _loading || _refreshing ? null : _refresh,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildBody(),
          ),
          if (_refreshing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _prescriptions.isEmpty) {
      return StatusView.loading(
        message: 'Loading your prescriptions...',
      );
    }

    if (_pageState == _PrescriptionPageState.patientNotLinked &&
        _prescriptions.isEmpty) {
      return StatusView.empty(
        icon: Icons.medication_outlined,
        title: 'No patient record linked',
        subtitle: 'This login account does not '
            'have a linked patient record. '
            'Contact the hospital if this '
            'account should have patient access.',
        onRetry: _retryLoading,
      );
    }

    if (_pageState == _PrescriptionPageState.loadFailed &&
        _prescriptions.isEmpty) {
      return StatusView.error(
        friendlyMessage: "We couldn't load your prescriptions.",
        error: _friendlyError(
          _lastError,
        ),
        onRetry: _retryLoading,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              32,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1100,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_pageState == _PrescriptionPageState.loadFailed)
                        _buildRefreshWarning(),
                      if (_refillPrescriptions.isNotEmpty) ...[
                        _buildRefillAlert(
                          _refillPrescriptions,
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                      ],
                      _buildStatsOverview(),
                      const SizedBox(
                        height: 16,
                      ),
                      _buildFilterSection(),
                      const SizedBox(
                        height: 16,
                      ),
                      if (_filteredPrescriptions.isEmpty)
                        _buildEmptyState()
                      else
                        ..._filteredPrescriptions.map(
                          (prescription) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: 12,
                            ),
                            child: _buildPrescriptionCard(
                              prescription,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRefreshWarning() {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 16,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CorviaColors.warning.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CorviaColors.warning.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: CorviaColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The previous prescription '
              'list is still visible, but '
              'the latest refresh failed. '
              '${_friendlyError(_lastError)}',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefillAlert(
    List<Prescription> refillPrescriptions,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showRefillDetails(
          refillPrescriptions,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CorviaColors.warning.withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: CorviaColors.warning.withValues(
                alpha: 0.35,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: CorviaColors.warning.withValues(
                    alpha: 0.18,
                  ),
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                ),
                child: const Icon(
                  Icons.notification_important_outlined,
                  color: CorviaColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Refill Needed Soon',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      '${refillPrescriptions.length} '
                      'medication(s) have a '
                      'refill date within '
                      'seven days.',
                      style: TextStyle(
                        color: context.cTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.cTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsOverview() {
    final stats = [
      (
        title: 'Active',
        value: _countByStatus('active'),
        color: CorviaColors.success,
        icon: Icons.check_circle_outline,
      ),
      (
        title: 'Completed',
        value: _countByStatus('completed'),
        color: Colors.blue,
        icon: Icons.task_alt_outlined,
      ),
      (
        title: 'Cancelled',
        value: _countByStatus('cancelled'),
        color: CorviaColors.danger,
        icon: Icons.cancel_outlined,
      ),
      (
        title: 'Expired',
        value: _countByStatus('expired'),
        color: CorviaColors.warning,
        icon: Icons.history_toggle_off,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        int columns = 2;

        if (constraints.maxWidth >= 800) {
          columns = 4;
        } else if (constraints.maxWidth < 420) {
          columns = 1;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 105,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final stat = stats[index];

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(
                  16,
                ),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: stat.color.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: Icon(
                      stat.icon,
                      color: stat.color,
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stat.value.toString(),
                          style: TextStyle(
                            color: stat.color,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          stat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterSection() {
    const filters = <String, String>{
      'all': 'All',
      'active': 'Active',
      'completed': 'Completed',
      'cancelled': 'Cancelled',
      'expired': 'Expired',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search prescriptions...',
            prefixIcon: Icon(
              Icons.search_rounded,
              color: context.cAccentReadable,
            ),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                    },
                    icon: const Icon(
                      Icons.clear_rounded,
                    ),
                  ),
            filled: true,
            fillColor: context.cBgSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                14,
              ),
              borderSide: BorderSide(
                color: context.cDivider,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                14,
              ),
              borderSide: BorderSide(
                color: context.cDivider,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                14,
              ),
              borderSide: BorderSide(
                color: context.cAccentReadable,
                width: 1.5,
              ),
            ),
          ),
          style: TextStyle(
            color: context.cTextPrimary,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters.entries.map(
              (entry) {
                final selected = _selectedFilter == entry.key;

                return Padding(
                  padding: const EdgeInsets.only(
                    right: 8,
                  ),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: selected,
                    selectedColor: context.cAccentReadable.withValues(
                      alpha: 0.15,
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? context.cAccentReadable
                          : context.cTextSecondary,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedFilter = entry.key;
                      });

                      _filterPrescriptions();
                    },
                  ),
                );
              },
            ).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPrescriptionCard(
    Prescription prescription,
  ) {
    final status = _normaliseStatus(
      prescription.status,
    );

    final statusColor = _statusColor(status);

    final needsRefill = _needsRefill(prescription);

    final daysUntilRefill = _daysUntilRefill(
      prescription,
    );

    final pharmacyStatus = _pharmacyByPrescriptionId[prescription.id];

    final pharmacyColor = _pharmacyStatusColor(
      pharmacyStatus?.status,
    );

    return Card(
      color: context.cBgSecondary,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: context.cDivider,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16,
          ),
          leading: _buildMedicationImage(
            prescription,
            size: 50,
          ),
          title: Text(
            prescription.medicationName.trim().isEmpty
                ? 'Unnamed medication'
                : prescription.medicationName,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(
              top: 6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${prescription.dosage} • '
                  '${prescription.frequency}',
                  style: TextStyle(
                    color: context.cTextSecondary,
                  ),
                ),
                const SizedBox(
                  height: 7,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildStatusPill(
                      _statusLabel(status),
                      statusColor,
                    ),
                    _buildStatusPill(
                      pharmacyStatus == null
                          ? 'Pharmacy: Not Sent'
                          : 'Pharmacy: ${pharmacyStatus.statusLabel}',
                      pharmacyColor,
                    ),
                    if (needsRefill)
                      _buildStatusPill(
                        daysUntilRefill != null && daysUntilRefill < 0
                            ? 'Refill overdue'
                            : 'Refill soon',
                        CorviaColors.warning,
                      ),
                  ],
                ),
              ],
            ),
          ),
          children: [
            Divider(
              color: context.cDivider,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (
                context,
                constraints,
              ) {
                final showImage = constraints.maxWidth >= 600;

                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      'Dosage',
                      prescription.dosage,
                    ),
                    _buildDetailRow(
                      'Frequency',
                      prescription.frequency,
                    ),
                    _buildDetailRow(
                      'Duration',
                      prescription.duration,
                    ),
                    if (prescription.notes?.trim().isNotEmpty ?? false)
                      _buildDetailRow(
                        'Notes',
                        prescription.notes!,
                      ),
                    _buildDetailRow(
                      'Issued',
                      _formatDate(
                        prescription.issuedAt,
                      ),
                    ),
                    _buildDetailRow(
                      'Status',
                      _statusLabel(status),
                      valueColor: statusColor,
                    ),
                    _buildDetailRow(
                      'Pharmacy',
                      pharmacyStatus?.statusLabel ?? 'Not Sent to Pharmacy',
                      valueColor: pharmacyColor,
                    ),
                    if (prescription.refillDate != null)
                      _buildDetailRow(
                        'Refill date',
                        _formatDate(
                          prescription.refillDate!,
                        ),
                      ),
                    if (daysUntilRefill != null)
                      _buildDetailRow(
                        'Days until refill',
                        daysUntilRefill < 0
                            ? '${daysUntilRefill.abs()} '
                                'day(s) overdue'
                            : '$daysUntilRefill '
                                'day(s)',
                        valueColor:
                            daysUntilRefill <= 7 ? CorviaColors.warning : null,
                      ),
                  ],
                );

                if (!showImage) {
                  return details;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: details,
                    ),
                    const SizedBox(
                      width: 20,
                    ),
                    _buildMedicationImage(
                      prescription,
                      size: 90,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildPrescriptionActions(
              prescription,
              pharmacyStatus,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _pharmacyStatusColor(
    String? status,
  ) {
    switch (status) {
      case 'received':
        return Colors.orange.shade800;

      case 'verified':
        return Colors.blue.shade700;

      case 'preparing':
        return Colors.deepPurple;

      case 'ready_for_collection':
        return Colors.green.shade700;

      case 'collected':
        return Colors.teal.shade700;

      case 'unable_to_dispense':
        return CorviaColors.danger;

      case 'cancelled':
        return Colors.grey.shade700;

      default:
        return context.cTextMuted;
    }
  }

  Widget _buildPrescriptionActions(
    Prescription prescription,
    _PrescriptionPharmacyStatus? pharmacyStatus,
  ) {
    final pharmacyButton = FilledButton.tonalIcon(
      onPressed: () => _showPharmacyDetails(
        prescription,
        pharmacyStatus,
      ),
      icon: const Icon(
        Icons.local_pharmacy_outlined,
      ),
      label: const Text(
        'Pharmacy Status & Collection',
      ),
    );

    // Share, export and the prescription QR code were placeholders, so they
    // stay hidden until they do something real (#242).
    return SizedBox(
      width: double.infinity,
      child: pharmacyButton,
    );
  }

  void _showPharmacyDetails(
    Prescription prescription,
    _PrescriptionPharmacyStatus? pharmacyStatus,
  ) {
    final statusColor = _pharmacyStatusColor(
      pharmacyStatus?.status,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cBgSecondary,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: pharmacyStatus == null ? 0.58 : 0.90,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.cDivider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.local_pharmacy_outlined,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prescription.medicationName.trim().isEmpty
                                ? 'Prescription medication'
                                : prescription.medicationName,
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildStatusPill(
                            pharmacyStatus?.statusLabel ??
                                'Not Sent to Pharmacy',
                            statusColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (pharmacyStatus == null)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.cBgPrimary,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: context.cDivider,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.hourglass_empty_rounded,
                          size: 42,
                          color: context.cTextMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No pharmacy tracking record yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The pharmacy status and collection details will '
                          'appear here after this prescription reaches the '
                          'hospital pharmacy.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.cTextSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      pharmacyStatus.statusMessage,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildPharmacyDetailSection(
                    title: 'Pharmacy Status',
                    children: [
                      _buildDetailRow(
                        'Status',
                        pharmacyStatus.statusLabel,
                        valueColor: statusColor,
                      ),
                      _buildDetailRow(
                        'Received',
                        _formatDateTime(pharmacyStatus.receivedAt),
                      ),
                      _buildDetailRow(
                        'Verified',
                        _formatDateTime(pharmacyStatus.verifiedAt),
                      ),
                      _buildDetailRow(
                        'Preparing',
                        _formatDateTime(pharmacyStatus.preparingAt),
                      ),
                      _buildDetailRow(
                        'Ready',
                        _formatDateTime(pharmacyStatus.readyAt),
                      ),
                      _buildDetailRow(
                        'Collected',
                        _formatDateTime(pharmacyStatus.collectedAt),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildPharmacyDetailSection(
                    title: 'Collection Details',
                    children: [
                      _buildDetailRow(
                        'Reference',
                        pharmacyStatus.collectionReference,
                      ),
                      _buildDetailRow(
                        'Hospital',
                        pharmacyStatus.hospitalName,
                      ),
                      _buildDetailRow(
                        'Address',
                        pharmacyStatus.hospitalAddress,
                      ),
                      _buildDetailRow(
                        'Phone',
                        pharmacyStatus.hospitalPhone,
                      ),
                      _buildDetailRow(
                        'Collected by',
                        pharmacyStatus.collectedByName,
                      ),
                      _buildDetailRow(
                        'Relationship',
                        pharmacyStatus.collectorRelationship,
                      ),
                      _buildDetailRow(
                        'Notes',
                        pharmacyStatus.collectionNotes,
                      ),
                    ],
                  ),
                  if (pharmacyStatus.hasProblem) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: CorviaColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: CorviaColors.danger.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: CorviaColors.danger,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              pharmacyStatus.problemReason,
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPharmacyDetailSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMedicationImage(
    Prescription prescription, {
    required double size,
  }) {
    final imageUrl = prescription.imageUrl;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl.trim().isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (
                context,
                child,
                progress,
              ) {
                if (progress == null) {
                  return child;
                }

                return Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress.expectedTotalBytes == null
                          ? null
                          : progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!,
                    ),
                  ),
                );
              },
              errorBuilder: (
                context,
                error,
                stackTrace,
              ) {
                return _buildImagePlaceholder(
                  size,
                );
              },
            )
          : _buildImagePlaceholder(
              size,
            ),
    );
  }

  Widget _buildImagePlaceholder(
    double size,
  ) {
    return Center(
      child: Icon(
        Icons.medication_outlined,
        size: size >= 80 ? 36 : 25,
        color: context.cTextSecondary,
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    Color? valueColor,
  }) {
    final safeValue = value.trim().isEmpty ? 'Not provided' : value.trim();

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 9,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              '$label:',
              style: TextStyle(
                color: context.cAccentReadable,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              safeValue,
              style: TextStyle(
                color: valueColor ?? context.cTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilters =
        _searchController.text.trim().isNotEmpty || _selectedFilter != 'all';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.medication_outlined,
            size: 60,
            color: context.cTextSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            hasFilters ? 'No Matching Prescriptions' : 'No Prescriptions Yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            hasFilters
                ? 'Try a different search '
                    'or clear the selected '
                    'filter.'
                : 'Prescriptions issued by '
                    'your doctor will appear '
                    'here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();

                setState(() {
                  _selectedFilter = 'all';
                });

                _filterPrescriptions();
              },
              icon: const Icon(
                Icons.clear_all_rounded,
              ),
              label: const Text(
                'Clear Search and Filters',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _friendlyError(
    Object? error,
  ) {
    if (error == null) {
      return 'Unknown error.';
    }

    if (error is TimeoutException) {
      return 'The server took too long '
          'to respond.';
    }

    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains(
          'permission denied',
        ) ||
        lower.contains(
          'row-level security',
        ) ||
        lower.contains('42501')) {
      return 'Your account does not have '
          'permission to view these '
          'prescriptions.';
    }

    if (lower.contains(
      'not signed in',
    )) {
      return 'You are not signed in.';
    }

    return message
        .replaceFirst(
          'Exception: ',
          '',
        )
        .replaceFirst(
          'Bad state: ',
          '',
        );
  }

  String _formatDate(
    DateTime date,
  ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatDateTime(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Not recorded';
    }

    final local = date.toLocal();

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _showRefillDetails(
    List<Prescription> prescriptions,
  ) {
    showDialog<void>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          backgroundColor: context.cBgSecondary,
          title: Text(
            'Medications Needing Refill',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 520,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: prescriptions.length,
              separatorBuilder: (
                context,
                index,
              ) =>
                  Divider(
                color: context.cDivider,
              ),
              itemBuilder: (
                context,
                index,
              ) {
                final prescription = prescriptions[index];

                final days = _daysUntilRefill(
                  prescription,
                );

                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _buildMedicationImage(
                      prescription,
                      size: 46,
                    ),
                    title: Text(
                      prescription.medicationName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      prescription.refillDate == null
                          ? 'No refill date'
                          : days != null && days < 0
                              ? 'Refill was due '
                                  '${days.abs()} '
                                  'day(s) ago'
                              : 'Refill due in '
                                  '${days ?? 0} '
                                  'day(s)',
                      style: TextStyle(
                        color: CorviaColors.warning,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _PrescriptionPharmacyStatus {
  const _PrescriptionPharmacyStatus({
    required this.dispense,
    required this.hospital,
  });

  final Map<String, dynamic> dispense;
  final Map<String, dynamic>? hospital;

  String get status {
    return _text(
      dispense['status'],
      fallback: 'received',
    )
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String get statusLabel {
    switch (status) {
      case 'received':
        return 'Received';

      case 'verified':
        return 'Verified';

      case 'preparing':
        return 'Preparing';

      case 'ready_for_collection':
        return 'Ready for Collection';

      case 'collected':
        return 'Collected';

      case 'unable_to_dispense':
        return 'Unable to Dispense';

      case 'cancelled':
        return 'Cancelled';

      default:
        return _pretty(status);
    }
  }

  String get statusMessage {
    switch (status) {
      case 'received':
        return 'The pharmacy has received this prescription.';

      case 'verified':
        return 'The pharmacy has checked this prescription.';

      case 'preparing':
        return 'The pharmacy is preparing this medication.';

      case 'ready_for_collection':
        return 'This medication is ready for collection.';

      case 'collected':
        return 'Collection of this medication was confirmed.';

      case 'unable_to_dispense':
        return 'The pharmacy could not dispense this medication.';

      case 'cancelled':
        return 'This pharmacy order was cancelled.';

      default:
        return 'Current pharmacy status: $statusLabel.';
    }
  }

  String get collectionReference {
    return _text(
      dispense['collection_reference'],
      fallback: 'Not available',
    );
  }

  String get hospitalName {
    return _text(
      hospital?['name'],
      fallback: 'Hospital pharmacy',
    );
  }

  String get hospitalAddress {
    return _text(
      hospital?['address'],
      fallback: 'Not recorded',
    );
  }

  String get hospitalPhone {
    return _text(
      hospital?['phone'],
      fallback: 'Not recorded',
    );
  }

  String get collectedByName {
    return _text(
      dispense['collected_by_name'],
      fallback: 'Not recorded',
    );
  }

  String get collectorRelationship {
    return _text(
      dispense['collector_relationship'],
      fallback: 'Not recorded',
    );
  }

  String get collectionNotes {
    return _text(
      dispense['collection_notes'],
      fallback: 'No collection notes.',
    );
  }

  String get problemReason {
    return _firstText(
      [
        dispense['unavailable_reason'],
        dispense['pharmacist_notes'],
      ],
      fallback: 'The pharmacy could not complete this order.',
    );
  }

  bool get hasProblem {
    return status == 'unable_to_dispense' || status == 'cancelled';
  }

  DateTime? get receivedAt => _date(dispense['received_at']);

  DateTime? get verifiedAt => _date(dispense['verified_at']);

  DateTime? get preparingAt => _date(dispense['preparing_at']);

  DateTime? get readyAt => _date(dispense['ready_at']);

  DateTime? get collectedAt => _date(dispense['collected_at']);

  static String _text(
    dynamic value, {
    required String fallback,
  }) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }

  static String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return fallback;
  }

  static String _pretty(
    String value,
  ) {
    return value
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  static DateTime? _date(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text);
  }
}
