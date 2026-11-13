import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/hospital_structure_service.dart';
import '../../theme/app_theme.dart';

class HospitalBedBoardPage extends StatefulWidget {
  const HospitalBedBoardPage({
    super.key,
    this.initialHospitalId,
  });

  final String? initialHospitalId;

  @override
  State<HospitalBedBoardPage> createState() => _HospitalBedBoardPageState();
}

class _HospitalBedBoardPageState extends State<HospitalBedBoardPage> {
  final HospitalStructureService _service = HospitalStructureService();

  bool _loading = true;
  bool _updating = false;

  String? _error;
  String? _selectedHospitalId;
  String? _selectedWardId;
  String _selectedStatus = 'all';

  List<Map<String, dynamic>> _hospitals = [];
  List<HospitalBedBoardEntry> _entries = [];

  static const List<String> _statuses = [
    'all',
    'available',
    'reserved',
    'occupied',
    'cleaning',
    'maintenance',
    'blocked',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final hospitals = await _service.getAdminHospitals();

      if (hospitals.isEmpty) {
        throw Exception(
          'This admin account is not linked to a hospital.',
        );
      }

      final validInitial = hospitals.any(
        (hospital) => hospital['id']?.toString() == widget.initialHospitalId,
      );

      final hospitalId = validInitial
          ? widget.initialHospitalId
          : hospitals.first['id']?.toString();

      if (hospitalId == null || hospitalId.isEmpty) {
        throw Exception('No valid hospital ID was found.');
      }

      _hospitals = hospitals;
      _selectedHospitalId = hospitalId;

      await _loadBoard();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadBoard() async {
    final hospitalId = _selectedHospitalId;

    if (hospitalId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final entries = await _service.getBedBoard(hospitalId);

      if (!mounted) return;

      setState(() {
        _entries = entries;

        if (_selectedWardId != null &&
            !entries.any(
              (entry) => entry.wardId == _selectedWardId,
            )) {
          _selectedWardId = null;
        }

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<HospitalBedBoardEntry> get _filteredEntries {
    return _entries.where((entry) {
      final matchesWard =
          _selectedWardId == null || entry.wardId == _selectedWardId;

      final matchesStatus =
          _selectedStatus == 'all' || entry.bedStatus == _selectedStatus;

      return matchesWard && matchesStatus;
    }).toList();
  }

  List<HospitalBedBoardEntry> get _uniqueWards {
    final seen = <String>{};
    final wards = <HospitalBedBoardEntry>[];

    for (final entry in _entries) {
      final wardId = entry.wardId;

      if (wardId == null || seen.contains(wardId)) {
        continue;
      }

      seen.add(wardId);
      wards.add(entry);
    }

    wards.sort(
      (a, b) => a.wardName.toLowerCase().compareTo(
            b.wardName.toLowerCase(),
          ),
    );

    return wards;
  }

  int _countStatus(String status) {
    return _entries.where((entry) => entry.bedStatus == status).length;
  }

  String _humanize(String value) {
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'available':
        return CorviaColors.success;

      case 'reserved':
      case 'cleaning':
        return CorviaColors.warning;

      case 'occupied':
        return CorviaColors.danger;

      case 'maintenance':
      case 'blocked':
        return Colors.grey;

      default:
        return context.cAccentReadable;
    }
  }

  void _showSnack(
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

  Future<void> _changeBedStatus(
    HospitalBedBoardEntry entry,
    String newStatus,
  ) async {
    if (_updating) return;

    final details = await _statusDetails(entry, newStatus);
    if (details == null) return;

    setState(() => _updating = true);

    try {
      await _service.updateBedStatus(
        hospitalId: entry.hospitalId,
        bedId: entry.bedId,
        newStatus: newStatus,
        reason: details.reason,
        reservedUntil: details.reservedUntil,
        sanitationNotes: details.sanitationNotes,
      );

      _showSnack(
        '${entry.displayBedName} changed to ${_humanize(newStatus)}.',
      );

      await _loadBoard();
    } catch (e) {
      _showSnack(
        'Could not update bed status: $e',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<_BedStatusDetails?> _statusDetails(
    HospitalBedBoardEntry entry,
    String newStatus,
  ) async {
    final needsReason = newStatus == 'maintenance';
    final needsSanitation =
        newStatus == 'available' && entry.bedStatus == 'cleaning';
    final needsReservation = newStatus == 'reserved';

    if (!needsReason && !needsSanitation && !needsReservation) {
      return const _BedStatusDetails();
    }

    final reasonController = TextEditingController();
    final sanitationController = TextEditingController();
    final defaultExpiry = DateTime.now().add(const Duration(hours: 2));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('${_humanize(newStatus)} ${entry.displayBedName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (needsReservation)
                Text(
                  'This bed will be reserved for 2 hours and expire on the next board refresh.',
                  style: TextStyle(color: context.cTextSecondary),
                ),
              if (needsReason)
                TextField(
                  controller: reasonController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Maintenance reason',
                  ),
                ),
              if (needsSanitation)
                TextField(
                  controller: sanitationController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Sanitation notes',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (needsReason && reasonController.text.trim().isEmpty) {
                  return;
                }
                if (needsSanitation &&
                    sanitationController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    final result = confirmed == true
        ? _BedStatusDetails(
            reason: reasonController.text.trim().isEmpty
                ? null
                : reasonController.text.trim(),
            sanitationNotes: sanitationController.text.trim().isEmpty
                ? null
                : sanitationController.text.trim(),
            reservedUntil: needsReservation ? defaultExpiry : null,
          )
        : null;

    reasonController.dispose();
    sanitationController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: Column(
        children: [
          _buildHeader(),
          _buildSummary(),
          _buildFilters(),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Live Bed Board',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Monitor every ward, room, bed and current patient assignment.',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: compact ? constraints.maxWidth : 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedHospitalId,
                  decoration: _inputDecoration('Hospital'),
                  items: _hospitals.map((hospital) {
                    return DropdownMenuItem<String>(
                      value: hospital['id'].toString(),
                      child: Text(
                        hospital['name']?.toString() ?? 'Hospital',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: _loading
                      ? null
                      : (value) async {
                          if (value == null || value == _selectedHospitalId) {
                            return;
                          }

                          setState(() {
                            _selectedHospitalId = value;
                            _selectedWardId = null;
                          });

                          await _loadBoard();
                        },
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh bed board',
                onPressed: _loading ? null : _loadBoard,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 15),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 18),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummary() {
    final summary = [
      _SummaryItem(
        title: 'Total Beds',
        value: _entries.length,
        icon: Icons.bed_rounded,
        color: context.cAccentReadable,
      ),
      _SummaryItem(
        title: 'Available',
        value: _countStatus('available'),
        icon: Icons.check_circle_rounded,
        color: CorviaColors.success,
      ),
      _SummaryItem(
        title: 'Occupied',
        value: _countStatus('occupied'),
        icon: Icons.person_rounded,
        color: CorviaColors.danger,
      ),
      _SummaryItem(
        title: 'Cleaning',
        value: _countStatus('cleaning'),
        icon: Icons.cleaning_services_rounded,
        color: CorviaColors.warning,
      ),
      _SummaryItem(
        title: 'Reserved',
        value: _countStatus('reserved'),
        icon: Icons.bookmark_rounded,
        color: CorviaColors.warning,
      ),
      _SummaryItem(
        title: 'Unavailable',
        value: _countStatus('maintenance') + _countStatus('blocked'),
        icon: Icons.build_circle_rounded,
        color: Colors.grey,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget card(_SummaryItem item, double width) {
            return SizedBox(
              width: width,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.cDivider),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(item.icon, color: item.color),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.value.toString(),
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.cTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (constraints.maxWidth < 700) {
            return SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: summary.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) => card(summary[index], 180),
              ),
            );
          }

          final columns = constraints.maxWidth >= 1100 ? 6 : 3;

          const spacing = 10.0;

          final width =
              (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: summary.map((item) => card(item, width)).toList(),
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;

          final wardDropdown = DropdownButtonFormField<String?>(
            initialValue: _selectedWardId,
            decoration: _inputDecoration('Ward'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All wards'),
              ),
              ..._uniqueWards.map((entry) {
                return DropdownMenuItem<String?>(
                  value: entry.wardId,
                  child: Text(entry.wardName),
                );
              }),
            ],
            onChanged: (value) {
              setState(() => _selectedWardId = value);
            },
          );

          final statusDropdown = DropdownButtonFormField<String>(
            initialValue: _selectedStatus,
            decoration: _inputDecoration('Bed status'),
            items: _statuses.map((status) {
              return DropdownMenuItem<String>(
                value: status,
                child: Text(_humanize(status)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedStatus = value);
              }
            },
          );

          if (compact) {
            return Column(
              children: [
                wardDropdown,
                const SizedBox(height: 10),
                statusDropdown,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: wardDropdown),
              const SizedBox(width: 12),
              Expanded(child: statusDropdown),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _ErrorState(
            message: _error!,
            onRetry: _loadBoard,
          ),
        ),
      );
    }

    final entries = _filteredEntries;

    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadBoard,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            _EmptyState(
              icon: Icons.bed_outlined,
              title: 'No beds found',
              message:
                  'Add buildings, floors, wards, rooms and beds in Hospital Structure.',
            ),
          ],
        ),
      );
    }

    final wardGroups = <String, List<HospitalBedBoardEntry>>{};

    for (final entry in entries) {
      final key = entry.wardId ?? '${entry.buildingName}-${entry.wardName}';

      wardGroups.putIfAbsent(key, () => []).add(entry);
    }

    return RefreshIndicator(
      onRefresh: _loadBoard,
      color: context.cAccentReadable,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: wardGroups.entries.map((wardGroup) {
          final wardEntries = wardGroup.value;
          final first = wardEntries.first;

          final available = wardEntries
              .where(
                (entry) => entry.bedStatus == 'available',
              )
              .length;

          final occupied = wardEntries
              .where(
                (entry) => entry.bedStatus == 'occupied',
              )
              .length;

          final roomGroups = <String, List<HospitalBedBoardEntry>>{};

          for (final entry in wardEntries) {
            final roomKey =
                entry.roomId ?? '${entry.wardName}-${entry.roomNumber}';

            roomGroups.putIfAbsent(roomKey, () => []).add(entry);
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(
                14,
                0,
                14,
                14,
              ),
              leading: Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: context.cAccentReadable.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.local_hospital_rounded,
                  color: context.cAccentReadable,
                ),
              ),
              title: Text(
                first.wardName,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                '${first.buildingName} • ${first.floorName} • '
                '${_humanize(first.wardType)} • '
                '$available available • $occupied occupied',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 12,
                ),
              ),
              children: roomGroups.entries.map((roomGroup) {
                final roomEntries = roomGroup.value;
                final room = roomEntries.first;

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.cBgPrimary,
                    borderRadius: BorderRadius.circular(18),
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
                            Icons.meeting_room_rounded,
                            color: context.cAccentReadable,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              room.displayRoomName,
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            '${roomEntries.length} bed'
                            '${roomEntries.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: context.cTextSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900
                              ? 3
                              : constraints.maxWidth >= 560
                                  ? 2
                                  : 1;

                          const spacing = 10.0;

                          final width = (constraints.maxWidth -
                                  ((columns - 1) * spacing)) /
                              columns;

                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: roomEntries.map((entry) {
                              return SizedBox(
                                width: width,
                                child: _BedCard(
                                  entry: entry,
                                  statusColor: _statusColor(entry.bedStatus),
                                  humanize: _humanize,
                                  busy: _updating,
                                  onStatusChanged: (status) {
                                    _changeBedStatus(
                                      entry,
                                      status,
                                    );
                                  },
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: context.cBgPrimary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: context.cDivider,
        ),
      ),
    );
  }
}

class _BedCard extends StatelessWidget {
  const _BedCard({
    required this.entry,
    required this.statusColor,
    required this.humanize,
    required this.busy,
    required this.onStatusChanged,
  });

  final HospitalBedBoardEntry entry;
  final Color statusColor;
  final String Function(String value) humanize;
  final bool busy;
  final ValueChanged<String> onStatusChanged;

  String _formatDate(DateTime value) {
    return DateFormat('d MMM yyyy • HH:mm').format(value);
  }

  Widget _operationalDetail(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 14,
            color: context.cTextSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientName = entry.patientName ?? 'No patient assigned';

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 39,
                width: 39,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.bed_rounded,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.displayBedName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Change bed status',
                enabled: !busy && !entry.isOccupied,
                onSelected: onStatusChanged,
                itemBuilder: (_) {
                  return const [
                    PopupMenuItem(
                      value: 'available',
                      child: Text('Available'),
                    ),
                    PopupMenuItem(
                      value: 'reserved',
                      child: Text('Reserved'),
                    ),
                    PopupMenuItem(
                      value: 'cleaning',
                      child: Text('Cleaning'),
                    ),
                    PopupMenuItem(
                      value: 'maintenance',
                      child: Text('Maintenance'),
                    ),
                    PopupMenuItem(
                      value: 'blocked',
                      child: Text('Blocked'),
                    ),
                  ];
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              humanize(entry.bedStatus),
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            patientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            entry.patientNumber != null
                ? 'Patient: ${entry.patientNumber}'
                : entry.isOccupied
                    ? 'Patient number unavailable'
                    : 'Ready for assignment',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 11,
            ),
          ),
          if (entry.admissionNumber != null) ...[
            const SizedBox(height: 3),
            Text(
              'Admission: ${entry.admissionNumber}',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 11,
              ),
            ),
          ],
          if (entry.bedStatus == 'reserved' && entry.reservedUntil != null)
            _operationalDetail(
              context,
              icon: Icons.event_busy_rounded,
              text: 'Reserved until ${_formatDate(entry.reservedUntil!)}',
            ),
          if (entry.bedStatus == 'cleaning' && entry.cleaningStartedAt != null)
            _operationalDetail(
              context,
              icon: Icons.cleaning_services_rounded,
              text: 'Cleaning started '
                  '${_formatDate(entry.cleaningStartedAt!)}',
            ),
          if (entry.bedStatus == 'cleaning' && entry.evsNotifiedAt != null)
            _operationalDetail(
              context,
              icon: Icons.notifications_active_outlined,
              text: 'EVS notified ${_formatDate(entry.evsNotifiedAt!)}',
            ),
          if (entry.bedStatus == 'maintenance' &&
              entry.maintenanceReason?.trim().isNotEmpty == true)
            _operationalDetail(
              context,
              icon: Icons.build_outlined,
              text: entry.maintenanceReason!.trim(),
            ),
          if (entry.bedStatus == 'available' && entry.cleanedAt != null)
            _operationalDetail(
              context,
              icon: Icons.verified_outlined,
              text: 'Sanitised ${_formatDate(entry.cleanedAt!)}',
            ),
          if (entry.bedStatus == 'available' &&
              entry.sanitationNotes?.trim().isNotEmpty == true)
            _operationalDetail(
              context,
              icon: Icons.notes_rounded,
              text: entry.sanitationNotes!.trim(),
            ),
          if (!entry.bedActive) ...[
            const SizedBox(height: 8),
            const Text(
              'This bed is inactive.',
              style: TextStyle(
                color: CorviaColors.danger,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final int value;
  final IconData icon;
  final Color color;
}

class _BedStatusDetails {
  const _BedStatusDetails({
    this.reason,
    this.reservedUntil,
    this.sanitationNotes,
  });

  final String? reason;
  final DateTime? reservedUntil;
  final String? sanitationNotes;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: CorviaColors.danger.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: CorviaColors.danger,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            'Bed board could not load',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 48,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: context.cAccentReadable,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
