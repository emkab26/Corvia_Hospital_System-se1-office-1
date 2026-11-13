import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class PatientPharmacyStatusPage extends StatefulWidget {
  const PatientPharmacyStatusPage({
    super.key,
  });

  @override
  State<PatientPharmacyStatusPage> createState() =>
      _PatientPharmacyStatusPageState();
}

class _PatientPharmacyStatusPageState extends State<PatientPharmacyStatusPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;

  String? _error;

  String _selectedFilter = 'Active';

  List<_PatientPharmacyRecord> _records = [];

  static const List<String> _filters = [
    'Active',
    'Ready',
    'Collected',
    'Problems',
    'All',
  ];

  @override
  void initState() {
    super.initState();

    _loadPage();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _loadPage() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception(
          'No signed-in Corvia account was found.',
        );
      }

      final patient = await _supabase
          .from('patients')
          .select('id, profile_id, is_active')
          .eq('profile_id', user.id)
          .maybeSingle();

      if (patient == null) {
        throw Exception(
          'No patient record is linked to this account.',
        );
      }

      if (patient['is_active'] == false) {
        throw Exception(
          'This patient record is inactive.',
        );
      }

      final patientId = patient['id']?.toString().trim();

      if (patientId == null || patientId.isEmpty) {
        throw Exception(
          'The patient record does not contain a valid ID.',
        );
      }

      final dispenseResponse = await _supabase
          .from('prescription_dispenses')
          .select()
          .eq('patient_id', patientId)
          .order(
            'received_at',
            ascending: false,
          )
          .limit(250);

      final dispenseRows = _rows(dispenseResponse);

      final prescriptionIds = dispenseRows
          .map(
            (row) => _cleanId(
              row['prescription_id'],
            ),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final hospitalIds = dispenseRows
          .map(
            (row) => _cleanId(
              row['hospital_id'],
            ),
          )
          .whereType<String>()
          .toSet()
          .toList();

      final prescriptions = <String, Map<String, dynamic>>{};

      final hospitals = <String, Map<String, dynamic>>{};

      if (prescriptionIds.isNotEmpty) {
        try {
          final prescriptionResponse =
              await _supabase.from('prescriptions').select().inFilter(
                    'id',
                    prescriptionIds,
                  );

          for (final row in _rows(prescriptionResponse)) {
            final id = _cleanId(row['id']);

            if (id != null) {
              prescriptions[id] = row;
            }
          }
        } catch (error) {
          debugPrint(
            'Patient pharmacy prescription lookup failed: $error',
          );
        }
      }

      if (hospitalIds.isNotEmpty) {
        try {
          final hospitalResponse = await _supabase
              .from('hospitals')
              .select('id, name, address, phone')
              .inFilter(
                'id',
                hospitalIds,
              );

          for (final row in _rows(hospitalResponse)) {
            final id = _cleanId(row['id']);

            if (id != null) {
              hospitals[id] = row;
            }
          }
        } catch (error) {
          debugPrint(
            'Patient pharmacy hospital lookup failed: $error',
          );
        }
      }

      final loadedRecords = dispenseRows.map(
        (dispense) {
          final prescriptionId = _cleanId(
            dispense['prescription_id'],
          );

          final hospitalId = _cleanId(
            dispense['hospital_id'],
          );

          return _PatientPharmacyRecord(
            dispense: dispense,
            prescription:
                prescriptionId == null ? null : prescriptions[prescriptionId],
            hospital: hospitalId == null ? null : hospitals[hospitalId],
          );
        },
      ).toList();

      loadedRecords.sort(
        (first, second) {
          final firstDate = first.receivedAt ?? DateTime(1970);

          final secondDate = second.receivedAt ?? DateTime(1970);

          return secondDate.compareTo(firstDate);
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _records = loadedRecords;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _cleanError(error);
      });
    }
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(row),
        )
        .toList();
  }

  String? _cleanId(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  String _cleanError(Object error) {
    if (error is PostgrestException) {
      return error.message;
    }

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
  }

  List<_PatientPharmacyRecord> get _visibleRecords {
    final search = _searchController.text.trim().toLowerCase();

    return _records.where(
      (record) {
        bool matchesFilter;

        switch (_selectedFilter) {
          case 'Ready':
            matchesFilter = record.status == 'ready_for_collection';
            break;

          case 'Collected':
            matchesFilter = record.status == 'collected';
            break;

          case 'Problems':
            matchesFilter = record.status == 'unable_to_dispense' ||
                record.status == 'cancelled';
            break;

          case 'All':
            matchesFilter = true;
            break;

          case 'Active':
          default:
            matchesFilter = record.status != 'collected' &&
                record.status != 'cancelled' &&
                record.status != 'unable_to_dispense';
        }

        if (!matchesFilter) {
          return false;
        }

        if (search.isEmpty) {
          return true;
        }

        final searchable = [
          record.medicineName,
          record.hospitalName,
          record.collectionReference,
          record.statusLabel,
        ].join(' ').toLowerCase();

        return searchable.contains(search);
      },
    ).toList();
  }

  int _countStatus(String status) {
    return _records
        .where(
          (record) => record.status == status,
        )
        .length;
  }

  int get _activeCount {
    return _records.where(
      (record) {
        return record.status != 'collected' &&
            record.status != 'cancelled' &&
            record.status != 'unable_to_dispense';
      },
    ).length;
  }

  int get _problemCount {
    return _records.where(
      (record) {
        return record.status == 'unable_to_dispense' ||
            record.status == 'cancelled';
      },
    ).length;
  }

  Color _statusColor(String status) {
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
        return context.cAccentReadable;
    }
  }

  Future<void> _copyReference(
    String reference,
  ) async {
    if (reference.trim().isEmpty || reference == 'Not available') {
      return;
    }

    await Clipboard.setData(
      ClipboardData(
        text: reference,
      ),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Collection reference copied.',
          ),
        ),
      );
  }

  void _showDetails(
    _PatientPharmacyRecord record,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cBgSecondary,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.90,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                20,
                12,
                20,
                28,
              ),
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
                        color:
                            _statusColor(record.status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.local_pharmacy_outlined,
                        color: _statusColor(record.status),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.medicineName,
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            record.hospitalName,
                            style: TextStyle(
                              color: context.cTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(
                      label: record.statusLabel,
                      color: _statusColor(record.status),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _DetailSection(
                  title: 'Pharmacy Status',
                  children: [
                    _DetailRow(
                      label: 'Current status',
                      value: record.statusLabel,
                    ),
                    _DetailRow(
                      label: 'Collection reference',
                      value: record.collectionReference,
                      trailing: record.collectionReference == 'Not available'
                          ? null
                          : IconButton(
                              tooltip: 'Copy reference',
                              onPressed: () {
                                _copyReference(
                                  record.collectionReference,
                                );
                              },
                              icon: const Icon(
                                Icons.copy_outlined,
                              ),
                            ),
                    ),
                    _DetailRow(
                      label: 'Received',
                      value: _formatDateTime(
                        record.receivedAt,
                      ),
                    ),
                    _DetailRow(
                      label: 'Verified',
                      value: _formatDateTime(
                        record.verifiedAt,
                      ),
                    ),
                    _DetailRow(
                      label: 'Preparing',
                      value: _formatDateTime(
                        record.preparingAt,
                      ),
                    ),
                    _DetailRow(
                      label: 'Ready',
                      value: _formatDateTime(
                        record.readyAt,
                      ),
                    ),
                    _DetailRow(
                      label: 'Collected',
                      value: _formatDateTime(
                        record.collectedAt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DetailSection(
                  title: 'Prescription',
                  children: [
                    _DetailRow(
                      label: 'Medicine',
                      value: record.medicineName,
                    ),
                    _DetailRow(
                      label: 'Dosage',
                      value: record.dosageSummary,
                    ),
                    _DetailRow(
                      label: 'Instructions',
                      value: record.instructions,
                    ),
                    _DetailRow(
                      label: 'Prescription status',
                      value: record.prescriptionStatus,
                    ),
                    _DetailRow(
                      label: 'Issued',
                      value: _formatDateTime(
                        record.issuedAt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DetailSection(
                  title: 'Collection Details',
                  children: [
                    _DetailRow(
                      label: 'Collected by',
                      value: record.collectedByName,
                    ),
                    _DetailRow(
                      label: 'Relationship',
                      value: record.collectorRelationship,
                    ),
                    _DetailRow(
                      label: 'Collection notes',
                      value: record.collectionNotes,
                    ),
                  ],
                ),
                if (record.hasProblem) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: CorviaColors.danger.withValues(
                        alpha: 0.08,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: CorviaColors.danger.withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: CorviaColors.danger,
                            ),
                            const SizedBox(width: 9),
                            Text(
                              'Pharmacy problem',
                              style: TextStyle(
                                color: CorviaColors.danger,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          record.problemReason,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'The pharmacy status shows preparation and '
                  'collection progress. It does not replace the '
                  'instructions on the original prescription.',
                  style: TextStyle(
                    color: context.cTextMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime? date) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Pharmacy Status',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadPage,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: CorviaColors.accent,
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final visibleRecords = _visibleRecords;

    return RefreshIndicator(
      onRefresh: _loadPage,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Medication Collection',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Track pharmacy preparation, collection references '
            'and completed collections.',
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          const SizedBox(height: 20),
          _buildSummaryCards(),
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: 'Search medicine, hospital or reference',
              prefixIcon: const Icon(
                Icons.search,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();

                        setState(() {});
                      },
                      icon: const Icon(
                        Icons.clear,
                      ),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filters.map(
              (filter) {
                return ChoiceChip(
                  label: Text(filter),
                  selected: _selectedFilter == filter,
                  onSelected: (_) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                  },
                );
              },
            ).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            'Pharmacy Orders (${visibleRecords.length})',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (visibleRecords.isEmpty)
            _buildEmptyState()
          else
            ...visibleRecords.map(
              _buildRecordCard,
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final cards = [
      _SummaryData(
        label: 'Active',
        value: _activeCount,
        icon: Icons.pending_actions_outlined,
        color: Colors.blue.shade700,
      ),
      _SummaryData(
        label: 'Ready',
        value: _countStatus(
          'ready_for_collection',
        ),
        icon: Icons.inventory_2_outlined,
        color: Colors.green.shade700,
      ),
      _SummaryData(
        label: 'Collected',
        value: _countStatus(
          'collected',
        ),
        icon: Icons.check_circle_outline,
        color: Colors.teal.shade700,
      ),
      _SummaryData(
        label: 'Problems',
        value: _problemCount,
        icon: Icons.warning_amber_rounded,
        color: CorviaColors.danger,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final columns = constraints.maxWidth >= 850
            ? 4
            : constraints.maxWidth >= 470
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 112,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final item = cards[index];

            return Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: item.color.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.icon,
                      color: item.color,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.value.toString(),
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          item.label,
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

  Widget _buildRecordCard(
    _PatientPharmacyRecord record,
  ) {
    final statusColor = _statusColor(record.status);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 13,
      ),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.medication_outlined,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.medicineName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.hospitalName,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(
                label: record.statusLabel,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (!record.hasProblem) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: record.progress,
                backgroundColor: context.cDivider.withValues(
                  alpha: 0.55,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(
                  statusColor,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              record.progressLabel,
              style: TextStyle(
                color: context.cTextMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 13),
          ],
          Divider(
            color: context.cDivider,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 15,
            runSpacing: 9,
            children: [
              _SmallInfo(
                icon: Icons.qr_code_2,
                text: record.collectionReference,
              ),
              _SmallInfo(
                icon: Icons.schedule,
                text: _formatDateTime(
                  record.receivedAt,
                ),
              ),
            ],
          ),
          if (record.hasProblem) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CorviaColors.danger.withValues(
                  alpha: 0.08,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                record.problemReason,
                style: TextStyle(
                  color: CorviaColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _showDetails(record);
              },
              icon: const Icon(
                Icons.visibility_outlined,
              ),
              label: const Text(
                'View Pharmacy Details',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(34),
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
            Icons.local_pharmacy_outlined,
            size: 48,
            color: context.cAccentReadable,
          ),
          const SizedBox(height: 13),
          Text(
            'No pharmacy orders found',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Pharmacy preparation and collection records '
            'will appear here after a prescription reaches '
            'the hospital pharmacy.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 540,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_pharmacy_outlined,
                  size: 56,
                  color: CorviaColors.danger,
                ),
                const SizedBox(height: 16),
                Text(
                  'Pharmacy status could not load',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 11),
                SelectableText(
                  _error ?? 'Unknown pharmacy error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadPage,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Try Again',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientPharmacyRecord {
  const _PatientPharmacyRecord({
    required this.dispense,
    required this.prescription,
    required this.hospital,
  });

  final Map<String, dynamic> dispense;
  final Map<String, dynamic>? prescription;
  final Map<String, dynamic>? hospital;

  String get status {
    return _text(
      dispense['status'],
      fallback: 'received',
    ).toLowerCase();
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

  String get medicineName {
    final directName = _firstText(
      [
        prescription?['medication_name'],
        prescription?['medicine_name'],
        prescription?['medication'],
        prescription?['drug_name'],
        prescription?['name'],
      ],
      fallback: '',
    );

    if (directName.isNotEmpty) {
      return directName;
    }

    final medicines = prescription?['medicines'];

    if (medicines is List) {
      final names = medicines
          .whereType<Map>()
          .map(
            (medicine) {
              return _firstText(
                [
                  medicine['name'],
                  medicine['medication_name'],
                  medicine['medication'],
                ],
                fallback: '',
              );
            },
          )
          .where(
            (name) => name.isNotEmpty,
          )
          .toList();

      if (names.isNotEmpty) {
        return names.join(', ');
      }
    }

    return 'Prescription medication';
  }

  String get dosageSummary {
    final dosage = _firstText(
      [
        prescription?['dosage'],
        prescription?['dose'],
        prescription?['dosage_amount'],
      ],
      fallback: '',
    );

    final dosageUnit = _firstText(
      [
        prescription?['dosage_unit'],
      ],
      fallback: '',
    );

    final frequency = _firstText(
      [
        prescription?['frequency'],
        prescription?['frequency_code'],
      ],
      fallback: '',
    );

    final duration = _firstText(
      [
        prescription?['duration'],
        prescription?['duration_value'],
      ],
      fallback: '',
    );

    final durationUnit = _firstText(
      [
        prescription?['duration_unit'],
      ],
      fallback: '',
    );

    final doseText = [
      dosage,
      dosageUnit,
    ]
        .where(
          (value) => value.isNotEmpty,
        )
        .join(' ');

    final durationText = [
      duration,
      durationUnit,
    ]
        .where(
          (value) => value.isNotEmpty,
        )
        .join(' ');

    final parts = [
      doseText,
      frequency,
      durationText,
    ]
        .where(
          (value) => value.isNotEmpty,
        )
        .toList();

    return parts.isEmpty ? 'Not recorded' : parts.join(' • ');
  }

  String get instructions {
    return _firstText(
      [
        prescription?['instructions'],
        prescription?['notes'],
      ],
      fallback: 'No instructions recorded.',
    );
  }

  String get prescriptionStatus {
    return _pretty(
      _text(
        prescription?['status'],
        fallback: 'active',
      ),
    );
  }

  String get hospitalName {
    return _firstText(
      [
        hospital?['name'],
      ],
      fallback: 'Hospital pharmacy',
    );
  }

  String get collectionReference {
    return _firstText(
      [
        dispense['collection_reference'],
      ],
      fallback: 'Not available',
    );
  }

  String get collectedByName {
    return _firstText(
      [
        dispense['collected_by_name'],
      ],
      fallback: 'Not recorded',
    );
  }

  String get collectorRelationship {
    return _firstText(
      [
        dispense['collector_relationship'],
      ],
      fallback: 'Not recorded',
    );
  }

  String get collectionNotes {
    return _firstText(
      [
        dispense['collection_notes'],
      ],
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

  DateTime? get receivedAt {
    return _date(dispense['received_at']);
  }

  DateTime? get verifiedAt {
    return _date(dispense['verified_at']);
  }

  DateTime? get preparingAt {
    return _date(dispense['preparing_at']);
  }

  DateTime? get readyAt {
    return _date(dispense['ready_at']);
  }

  DateTime? get collectedAt {
    return _date(dispense['collected_at']);
  }

  DateTime? get issuedAt {
    return _date(
      prescription?['issued_at'] ?? prescription?['created_at'],
    );
  }

  double get progress {
    switch (status) {
      case 'received':
        return 0.20;

      case 'verified':
        return 0.40;

      case 'preparing':
        return 0.65;

      case 'ready_for_collection':
        return 0.85;

      case 'collected':
        return 1.0;

      default:
        return 0.0;
    }
  }

  String get progressLabel {
    switch (status) {
      case 'received':
        return 'The pharmacy received the prescription.';

      case 'verified':
        return 'The prescription was checked.';

      case 'preparing':
        return 'The medication is being prepared.';

      case 'ready_for_collection':
        return 'The medication is ready for collection.';

      case 'collected':
        return 'Collection was confirmed.';

      default:
        return statusLabel;
    }
  }

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

  static DateTime? _date(dynamic value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return DateTime.tryParse(text);
  }

  static String _pretty(String value) {
    final cleaned = value.trim().replaceAll('-', '_').replaceAll(' ', '_');

    return cleaned
        .split('_')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
      (word) {
        return '${word[0].toUpperCase()}'
            '${word.substring(1).toLowerCase()}';
      },
    ).join(' ');
  }
}

class _SummaryData {
  const _SummaryData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 165,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(
            alpha: 0.24,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SmallInfo extends StatelessWidget {
  const _SmallInfo({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: context.cTextSecondary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(17),
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
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
