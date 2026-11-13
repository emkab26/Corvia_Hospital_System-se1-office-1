import 'package:flutter/material.dart';

import '../../services/hospital_structure_service.dart';
import '../../theme/app_theme.dart';
import 'hospital_bed_board_page.dart';

class HospitalStructurePage extends StatefulWidget {
  const HospitalStructurePage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<HospitalStructurePage> createState() => _HospitalStructurePageState();
}

class _HospitalStructurePageState extends State<HospitalStructurePage>
    with SingleTickerProviderStateMixin {
  final HospitalStructureService _service = HospitalStructureService();

  late final TabController _tabController;

  bool _loading = true;
  bool _actionBusy = false;

  String? _error;
  String? _selectedHospitalId;

  late int _selectedTab;

  List<Map<String, dynamic>> _hospitals = [];
  List<Map<String, dynamic>> _buildings = [];
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _wards = [];
  List<Map<String, dynamic>> _visitorRules = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _beds = [];

  static const List<String> _wardTypes = [
    'general',
    'medical',
    'surgical',
    'paediatric',
    'maternity',
    'neonatal',
    'icu',
    'high_care',
    'isolation',
    'psychiatric',
    'oncology',
    'renal',
    'emergency_observation',
    'day_ward',
    'theatre_recovery',
  ];

  static const List<String> _visitorModes = [
    'visitors_allowed',
    'family_only',
    'approved_visitors_only',
    'primary_contact_only',
    'ward_approval_required',
    'icu_approval_required',
    'temporarily_restricted',
    'infection_isolation',
    'no_visitors',
    'security_restricted',
    'end_of_life_exception',
  ];

  static const List<String> _roomTypes = [
    'general',
    'private',
    'semi_private',
    'isolation',
    'icu',
    'high_care',
    'maternity',
    'paediatric',
    'emergency_observation',
    'recovery',
  ];

  static const List<String> _genderPolicies = [
    'any',
    'male',
    'female',
    'paediatric',
    'maternity',
    'private',
  ];

  static const List<String> _bedTypes = [
    'standard',
    'electric',
    'paediatric',
    'cot',
    'maternity',
    'icu',
    'high_care',
    'isolation',
    'recovery',
    'observation',
  ];

  @override
  void initState() {
    super.initState();

    _selectedTab = widget.initialTab.clamp(0, 4);

    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: _selectedTab,
    );

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;

      if (mounted) {
        setState(() {
          _selectedTab = _tabController.index;
        });
      }
    });

    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
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

      final hospitalId =
          _selectedHospitalId ?? hospitals.first['id']?.toString();

      if (hospitalId == null || hospitalId.trim().isEmpty) {
        throw Exception('No valid hospital ID was found.');
      }

      _hospitals = hospitals;
      _selectedHospitalId = hospitalId;

      await _loadStructure();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadStructure() async {
    final hospitalId = _selectedHospitalId;

    if (hospitalId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await _service.loadSnapshot(hospitalId);

      if (!mounted) return;

      setState(() {
        _buildings = snapshot.buildings;
        _floors = snapshot.floors;
        _wards = snapshot.wards;
        _visitorRules = snapshot.visitorRules;
        _rooms = snapshot.rooms;
        _beds = snapshot.beds;
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

  String get _hospitalName {
    for (final hospital in _hospitals) {
      if (hospital['id']?.toString() == _selectedHospitalId) {
        return hospital['name']?.toString() ?? 'Hospital';
      }
    }

    return 'Hospital';
  }

  int get _availableBeds {
    return _beds.where((bed) {
      return bed['status'] == 'available' && bed['is_active'] != false;
    }).length;
  }

  int get _occupiedBeds {
    return _beds.where((bed) => bed['status'] == 'occupied').length;
  }

  String _humanize(dynamic value) {
    final raw = value?.toString() ?? '';

    if (raw.isEmpty) return 'Not set';

    return raw
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String _buildingName(dynamic id) {
    for (final building in _buildings) {
      if (building['id']?.toString() == id?.toString()) {
        return building['name']?.toString() ?? 'Unknown Building';
      }
    }

    return 'Unknown Building';
  }

  String _floorName(dynamic id) {
    for (final floor in _floors) {
      if (floor['id']?.toString() == id?.toString()) {
        return floor['name']?.toString() ?? 'Unknown Floor';
      }
    }

    return 'Unknown Floor';
  }

  String _wardName(dynamic id) {
    for (final ward in _wards) {
      if (ward['id']?.toString() == id?.toString()) {
        return ward['name']?.toString() ?? 'Unknown Ward';
      }
    }

    return 'Unknown Ward';
  }

  String _roomName(dynamic id) {
    for (final room in _rooms) {
      if (room['id']?.toString() == id?.toString()) {
        final roomName = room['room_name']?.toString().trim() ?? '';

        if (roomName.isNotEmpty) {
          return '$roomName • Room ${room['room_number']}';
        }

        return 'Room ${room['room_number']}';
      }
    }

    return 'Unknown Room';
  }

  Map<String, dynamic>? _visitorRuleForWard(
    dynamic wardId,
  ) {
    for (final rule in _visitorRules) {
      if (rule['ward_id']?.toString() == wardId?.toString()) {
        return rule;
      }
    }

    return null;
  }

  String _timeText(dynamic value) {
    final raw = value?.toString() ?? '';

    if (raw.length >= 5) {
      return raw.substring(0, 5);
    }

    return raw;
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

  String get _addLabel {
    switch (_selectedTab) {
      case 0:
        return 'Add Building';

      case 1:
        return 'Add Floor';

      case 2:
        return 'Add Ward';

      case 3:
        return 'Add Room';

      case 4:
        return 'Add Bed';

      default:
        return 'Add';
    }
  }

  Future<void> _openAddDialog() async {
    switch (_selectedTab) {
      case 0:
        await _showBuildingDialog();
        break;

      case 1:
        await _showFloorDialog();
        break;

      case 2:
        await _showWardDialog();
        break;

      case 3:
        await _showRoomDialog();
        break;

      case 4:
        await _showBedDialog();
        break;
    }
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
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

  Future<void> _showBuildingDialog({
    Map<String, dynamic>? existing,
  }) async {
    final nameController = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );

    final codeController = TextEditingController(
      text: existing?['code']?.toString() ?? '',
    );

    final descriptionController = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );

    final addressController = TextEditingController(
      text: existing?['address_note']?.toString() ?? '',
    );

    final receptionController = TextEditingController(
      text: existing?['reception_location']?.toString() ?? '',
    );

    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: Text(
                existing == null
                    ? 'Add Hospital Building'
                    : 'Edit Hospital Building',
              ),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: _inputDecoration(
                          'Building name',
                          hint: 'Main Building',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeController,
                        decoration: _inputDecoration(
                          'Building code',
                          hint: 'MAIN',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: receptionController,
                        decoration: _inputDecoration(
                          'Reception location',
                          hint: 'Ground-floor main entrance',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addressController,
                        decoration: _inputDecoration(
                          'Address or access note',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        decoration: _inputDecoration('Description'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (nameController.text.trim().isEmpty) {
                            _showSnack(
                              'Building name is required.',
                              error: true,
                            );
                            return;
                          }

                          setDialogState(() => saving = true);

                          try {
                            if (existing == null) {
                              await _service.addBuilding(
                                hospitalId: _selectedHospitalId!,
                                name: nameController.text,
                                code: codeController.text,
                                description: descriptionController.text,
                                addressNote: addressController.text,
                                receptionLocation: receptionController.text,
                              );
                            } else {
                              await _service.updateBuilding(
                                hospitalId: _selectedHospitalId!,
                                buildingId: existing['id'].toString(),
                                name: nameController.text,
                                code: codeController.text,
                                description: descriptionController.text,
                                addressNote: addressController.text,
                                receptionLocation: receptionController.text,
                              );
                            }

                            if (!dialogContext.mounted) return;

                            Navigator.pop(dialogContext);

                            _showSnack(
                              existing == null
                                  ? 'Building added successfully.'
                                  : 'Building updated successfully.',
                            );

                            await _loadStructure();
                          } catch (e) {
                            _showSnack(
                              'Could not save building: $e',
                              error: true,
                            );

                            setDialogState(() => saving = false);
                          }
                        },
                  icon: Icon(
                    existing == null
                        ? Icons.add_business_rounded
                        : Icons.save_rounded,
                  ),
                  label: Text(
                    existing == null ? 'Add Building' : 'Save Changes',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    codeController.dispose();
    descriptionController.dispose();
    addressController.dispose();
    receptionController.dispose();
  }

  Future<void> _showFloorDialog({
    Map<String, dynamic>? existing,
  }) async {
    if (_buildings.isEmpty) {
      _showSnack(
        'Add a building before adding floors.',
        error: true,
      );
      return;
    }

    final nameController = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );

    final numberController = TextEditingController(
      text: existing?['floor_number']?.toString() ?? '',
    );

    final codeController = TextEditingController(
      text: existing?['code']?.toString() ?? '',
    );

    final descriptionController = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );

    var selectedBuildingId = existing?['building_id']?.toString() ??
        _buildings.first['id'].toString();

    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: Text(
                existing == null ? 'Add Hospital Floor' : 'Edit Hospital Floor',
              ),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedBuildingId,
                        decoration: _inputDecoration('Building'),
                        items: _buildings.map((building) {
                          return DropdownMenuItem<String>(
                            value: building['id'].toString(),
                            child: Text(
                              building['name']?.toString() ?? 'Building',
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedBuildingId = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: _inputDecoration(
                          'Floor name',
                          hint: 'Ground Floor',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: numberController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          'Floor number',
                          hint: '0',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeController,
                        decoration: _inputDecoration(
                          'Floor code',
                          hint: 'GF',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        decoration: _inputDecoration('Description'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (nameController.text.trim().isEmpty) {
                            _showSnack(
                              'Floor name is required.',
                              error: true,
                            );
                            return;
                          }

                          final numberText = numberController.text.trim();

                          final floorNumber = numberText.isEmpty
                              ? null
                              : int.tryParse(numberText);

                          if (numberText.isNotEmpty && floorNumber == null) {
                            _showSnack(
                              'Floor number must be valid.',
                              error: true,
                            );
                            return;
                          }

                          setDialogState(() => saving = true);

                          try {
                            if (existing == null) {
                              await _service.addFloor(
                                hospitalId: _selectedHospitalId!,
                                buildingId: selectedBuildingId,
                                name: nameController.text,
                                floorNumber: floorNumber,
                                code: codeController.text,
                                description: descriptionController.text,
                              );
                            } else {
                              await _service.updateFloor(
                                hospitalId: _selectedHospitalId!,
                                floorId: existing['id'].toString(),
                                buildingId: selectedBuildingId,
                                name: nameController.text,
                                floorNumber: floorNumber,
                                code: codeController.text,
                                description: descriptionController.text,
                              );
                            }

                            if (!dialogContext.mounted) return;

                            Navigator.pop(dialogContext);

                            _showSnack(
                              existing == null
                                  ? 'Floor added successfully.'
                                  : 'Floor updated successfully.',
                            );

                            await _loadStructure();
                          } catch (e) {
                            _showSnack(
                              'Could not save floor: $e',
                              error: true,
                            );

                            setDialogState(() => saving = false);
                          }
                        },
                  icon: Icon(
                    existing == null
                        ? Icons.layers_rounded
                        : Icons.save_rounded,
                  ),
                  label: Text(
                    existing == null ? 'Add Floor' : 'Save Changes',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    numberController.dispose();
    codeController.dispose();
    descriptionController.dispose();
  }

  Future<void> _showWardDialog({
    Map<String, dynamic>? existing,
  }) async {
    if (_floors.isEmpty) {
      _showSnack(
        'Add a building and floor before adding wards.',
        error: true,
      );
      return;
    }

    final existingRule =
        existing == null ? null : _visitorRuleForWard(existing['id']);

    final nameController = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );

    final codeController = TextEditingController(
      text: existing?['code']?.toString() ?? '',
    );

    final descriptionController = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );

    final extensionController = TextEditingController(
      text: existing?['phone_extension']?.toString() ?? '',
    );

    final nurseStationController = TextEditingController(
      text: existing?['nurse_station_location']?.toString() ?? '',
    );

    final startController = TextEditingController(
      text: _timeText(existingRule?['visiting_start']),
    );

    final endController = TextEditingController(
      text: _timeText(existingRule?['visiting_end']),
    );

    final maximumController = TextEditingController(
      text: existingRule?['maximum_visitors']?.toString() ?? '2',
    );

    final instructionsController = TextEditingController(
      text: existingRule?['special_instructions']?.toString() ?? '',
    );

    var selectedBuildingId = existing?['building_id']?.toString() ??
        _floors.first['building_id'].toString();

    var selectedFloorId =
        existing?['floor_id']?.toString() ?? _floors.first['id'].toString();

    var selectedWardType = existing?['ward_type']?.toString() ?? 'general';

    var selectedVisitorMode =
        existingRule?['visitor_mode']?.toString() ?? 'ward_approval_required';

    var requiresStaffApproval =
        existingRule?['requires_staff_approval'] == true;

    var showRoomNumber = existingRule?['show_room_number'] ?? true;

    var showBedLabel = existingRule?['show_bed_label'] ?? false;

    var saving = false;

    List<Map<String, dynamic>> filteredFloors() {
      return _floors.where((floor) {
        return floor['building_id']?.toString() == selectedBuildingId;
      }).toList();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final availableFloors = filteredFloors();

            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: Text(
                existing == null ? 'Add Hospital Ward' : 'Edit Hospital Ward',
              ),
              content: SizedBox(
                width: 590,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedBuildingId,
                        decoration: _inputDecoration('Building'),
                        items: _buildings.map((building) {
                          return DropdownMenuItem<String>(
                            value: building['id'].toString(),
                            child: Text(
                              building['name']?.toString() ?? 'Building',
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;

                                setDialogState(() {
                                  selectedBuildingId = value;

                                  final matches = filteredFloors();

                                  if (matches.isNotEmpty) {
                                    selectedFloorId =
                                        matches.first['id'].toString();
                                  }
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          '$selectedBuildingId-$selectedFloorId',
                        ),
                        initialValue: availableFloors.any(
                          (floor) => floor['id']?.toString() == selectedFloorId,
                        )
                            ? selectedFloorId
                            : null,
                        decoration: _inputDecoration('Floor'),
                        items: availableFloors.map((floor) {
                          return DropdownMenuItem<String>(
                            value: floor['id'].toString(),
                            child: Text(
                              floor['name']?.toString() ?? 'Floor',
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedFloorId = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: _inputDecoration(
                          'Ward name',
                          hint: 'Surgical Ward A',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeController,
                        decoration: _inputDecoration(
                          'Ward code',
                          hint: 'SURG-A',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedWardType,
                        decoration: _inputDecoration('Ward type'),
                        items: _wardTypes.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(_humanize(type)),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;

                                setDialogState(() {
                                  selectedWardType = value;

                                  if (value == 'icu' || value == 'high_care') {
                                    selectedVisitorMode =
                                        'icu_approval_required';
                                    requiresStaffApproval = true;
                                    showRoomNumber = false;
                                    showBedLabel = false;
                                  } else if (value == 'isolation') {
                                    selectedVisitorMode = 'infection_isolation';
                                    requiresStaffApproval = true;
                                    showRoomNumber = false;
                                    showBedLabel = false;
                                  }
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(selectedVisitorMode),
                        initialValue: selectedVisitorMode,
                        decoration: _inputDecoration(
                          'Visitor access rule',
                        ),
                        items: _visitorModes.map((mode) {
                          return DropdownMenuItem<String>(
                            value: mode,
                            child: Text(_humanize(mode)),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedVisitorMode = value;

                                    requiresStaffApproval = {
                                      'approved_visitors_only',
                                      'primary_contact_only',
                                      'ward_approval_required',
                                      'icu_approval_required',
                                      'infection_isolation',
                                      'security_restricted',
                                    }.contains(value);
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: startController,
                              decoration: _inputDecoration(
                                'Visiting starts',
                                hint: '15:00',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: endController,
                              decoration: _inputDecoration(
                                'Visiting ends',
                                hint: '17:00',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: maximumController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          'Maximum visitors',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: requiresStaffApproval,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Staff approval required'),
                        onChanged: saving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  requiresStaffApproval = value;
                                });
                              },
                      ),
                      SwitchListTile.adaptive(
                        value: showRoomNumber,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Show room number to approved visitors',
                        ),
                        onChanged: saving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  showRoomNumber = value;
                                });
                              },
                      ),
                      SwitchListTile.adaptive(
                        value: showBedLabel,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Show bed label to approved visitors',
                        ),
                        onChanged: saving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  showBedLabel = value;
                                });
                              },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nurseStationController,
                        decoration: _inputDecoration(
                          'Nurses’ station location',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: extensionController,
                        decoration: _inputDecoration(
                          'Ward phone extension',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: instructionsController,
                        maxLines: 3,
                        decoration: _inputDecoration(
                          'Visitor instructions',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        decoration: _inputDecoration('Description'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (nameController.text.trim().isEmpty) {
                            _showSnack(
                              'Ward name is required.',
                              error: true,
                            );
                            return;
                          }

                          final maximumVisitors = int.tryParse(
                            maximumController.text.trim(),
                          );

                          if (maximumVisitors == null || maximumVisitors < 0) {
                            _showSnack(
                              'Maximum visitors must be valid.',
                              error: true,
                            );
                            return;
                          }

                          setDialogState(() => saving = true);

                          try {
                            if (existing == null) {
                              await _service.addWard(
                                hospitalId: _selectedHospitalId!,
                                buildingId: selectedBuildingId,
                                floorId: selectedFloorId,
                                name: nameController.text,
                                wardType: selectedWardType,
                                visitorMode: selectedVisitorMode,
                                maximumVisitors: maximumVisitors,
                                requiresStaffApproval: requiresStaffApproval,
                                showRoomNumber: showRoomNumber,
                                showBedLabel: showBedLabel,
                                code: codeController.text,
                                description: descriptionController.text,
                                phoneExtension: extensionController.text,
                                nurseStationLocation:
                                    nurseStationController.text,
                                visitingStart: startController.text,
                                visitingEnd: endController.text,
                                visitorInstructions:
                                    instructionsController.text,
                              );
                            } else {
                              await _service.updateWard(
                                hospitalId: _selectedHospitalId!,
                                wardId: existing['id'].toString(),
                                buildingId: selectedBuildingId,
                                floorId: selectedFloorId,
                                name: nameController.text,
                                wardType: selectedWardType,
                                visitorMode: selectedVisitorMode,
                                maximumVisitors: maximumVisitors,
                                requiresStaffApproval: requiresStaffApproval,
                                showRoomNumber: showRoomNumber,
                                showBedLabel: showBedLabel,
                                code: codeController.text,
                                description: descriptionController.text,
                                phoneExtension: extensionController.text,
                                nurseStationLocation:
                                    nurseStationController.text,
                                visitingStart: startController.text,
                                visitingEnd: endController.text,
                                visitorInstructions:
                                    instructionsController.text,
                              );
                            }

                            if (!dialogContext.mounted) return;

                            Navigator.pop(dialogContext);

                            _showSnack(
                              existing == null
                                  ? 'Ward added successfully.'
                                  : 'Ward updated successfully.',
                            );

                            await _loadStructure();
                          } catch (e) {
                            _showSnack(
                              'Could not save ward: $e',
                              error: true,
                            );

                            setDialogState(() => saving = false);
                          }
                        },
                  icon: Icon(
                    existing == null
                        ? Icons.local_hospital_rounded
                        : Icons.save_rounded,
                  ),
                  label: Text(
                    existing == null ? 'Add Ward' : 'Save Changes',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    codeController.dispose();
    descriptionController.dispose();
    extensionController.dispose();
    nurseStationController.dispose();
    startController.dispose();
    endController.dispose();
    maximumController.dispose();
    instructionsController.dispose();
  }

  Future<void> _showRoomDialog({
    Map<String, dynamic>? existing,
  }) async {
    if (_wards.isEmpty) {
      _showSnack(
        'Add a ward before adding rooms.',
        error: true,
      );
      return;
    }

    final numberController = TextEditingController(
      text: existing?['room_number']?.toString() ?? '',
    );

    final nameController = TextEditingController(
      text: existing?['room_name']?.toString() ?? '',
    );

    final capacityController = TextEditingController(
      text: existing?['capacity']?.toString() ?? '1',
    );

    final notesController = TextEditingController(
      text: existing?['notes']?.toString() ?? '',
    );

    var selectedWardId =
        existing?['ward_id']?.toString() ?? _wards.first['id'].toString();

    var selectedRoomType = existing?['room_type']?.toString() ?? 'general';

    var selectedGenderPolicy = existing?['gender_policy']?.toString() ?? 'any';

    var isIsolation = existing?['is_isolation'] == true;

    var visitorAccessAllowed = existing?['visitor_access_allowed'] != false;

    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: Text(
                existing == null ? 'Add Hospital Room' : 'Edit Hospital Room',
              ),
              content: SizedBox(
                width: 550,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedWardId,
                        decoration: _inputDecoration('Ward'),
                        items: _wards.map((ward) {
                          return DropdownMenuItem<String>(
                            value: ward['id'].toString(),
                            child: Text(
                              '${ward['name']} • '
                              '${_humanize(ward['ward_type'])}',
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedWardId = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: numberController,
                        decoration: _inputDecoration(
                          'Room number',
                          hint: '312',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: _inputDecoration(
                          'Room name',
                          hint: 'Private Room',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRoomType,
                        decoration: _inputDecoration('Room type'),
                        items: _roomTypes.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(_humanize(type)),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedRoomType = value;
                                    isIsolation = value == 'isolation';
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: capacityController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('Room capacity'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedGenderPolicy,
                        decoration: _inputDecoration(
                          'Gender policy',
                        ),
                        items: _genderPolicies.map((policy) {
                          return DropdownMenuItem<String>(
                            value: policy,
                            child: Text(_humanize(policy)),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedGenderPolicy = value;
                                  });
                                }
                              },
                      ),
                      SwitchListTile.adaptive(
                        value: isIsolation,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Isolation room'),
                        onChanged: saving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  isIsolation = value;

                                  if (value) {
                                    selectedRoomType = 'isolation';
                                  }
                                });
                              },
                      ),
                      SwitchListTile.adaptive(
                        value: visitorAccessAllowed,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Visitor access allowed'),
                        subtitle: const Text(
                          'Ward and patient rules still apply.',
                        ),
                        onChanged: saving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  visitorAccessAllowed = value;
                                });
                              },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: _inputDecoration('Room notes'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (numberController.text.trim().isEmpty) {
                            _showSnack(
                              'Room number is required.',
                              error: true,
                            );
                            return;
                          }

                          final capacity = int.tryParse(
                            capacityController.text.trim(),
                          );

                          if (capacity == null || capacity < 1) {
                            _showSnack(
                              'Room capacity must be at least 1.',
                              error: true,
                            );
                            return;
                          }

                          setDialogState(() => saving = true);

                          try {
                            if (existing == null) {
                              await _service.addRoom(
                                hospitalId: _selectedHospitalId!,
                                wardId: selectedWardId,
                                roomNumber: numberController.text,
                                roomName: nameController.text,
                                roomType: selectedRoomType,
                                capacity: capacity,
                                genderPolicy: selectedGenderPolicy,
                                isIsolation: isIsolation,
                                visitorAccessAllowed: visitorAccessAllowed,
                                notes: notesController.text,
                              );
                            } else {
                              await _service.updateRoom(
                                hospitalId: _selectedHospitalId!,
                                roomId: existing['id'].toString(),
                                wardId: selectedWardId,
                                roomNumber: numberController.text,
                                roomName: nameController.text,
                                roomType: selectedRoomType,
                                capacity: capacity,
                                genderPolicy: selectedGenderPolicy,
                                isIsolation: isIsolation,
                                visitorAccessAllowed: visitorAccessAllowed,
                                notes: notesController.text,
                              );
                            }

                            if (!dialogContext.mounted) return;

                            Navigator.pop(dialogContext);

                            _showSnack(
                              existing == null
                                  ? 'Room added successfully.'
                                  : 'Room updated successfully.',
                            );

                            await _loadStructure();
                          } catch (e) {
                            _showSnack(
                              'Could not save room: $e',
                              error: true,
                            );

                            setDialogState(() => saving = false);
                          }
                        },
                  icon: Icon(
                    existing == null
                        ? Icons.meeting_room_rounded
                        : Icons.save_rounded,
                  ),
                  label: Text(
                    existing == null ? 'Add Room' : 'Save Changes',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    numberController.dispose();
    nameController.dispose();
    capacityController.dispose();
    notesController.dispose();
  }

  Future<void> _showBedDialog({
    Map<String, dynamic>? existing,
  }) async {
    if (_rooms.isEmpty) {
      _showSnack(
        'Add a room before adding beds.',
        error: true,
      );
      return;
    }

    final numberController = TextEditingController(
      text: existing?['bed_number']?.toString() ?? '',
    );

    final labelController = TextEditingController(
      text: existing?['bed_label']?.toString() ?? '',
    );

    final notesController = TextEditingController(
      text: existing?['notes']?.toString() ?? '',
    );

    var selectedRoomId =
        existing?['room_id']?.toString() ?? _rooms.first['id'].toString();

    var selectedBedType = existing?['bed_type']?.toString() ?? 'standard';

    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cBgSecondary,
              title: Text(
                existing == null ? 'Add Hospital Bed' : 'Edit Hospital Bed',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedRoomId,
                        decoration: _inputDecoration('Room'),
                        items: _rooms.map((room) {
                          return DropdownMenuItem<String>(
                            value: room['id'].toString(),
                            child: Text(
                              '${_wardName(room['ward_id'])} • '
                              'Room ${room['room_number']}',
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedRoomId = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: numberController,
                        decoration: _inputDecoration(
                          'Bed number',
                          hint: 'A',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: labelController,
                        decoration: _inputDecoration(
                          'Bed label',
                          hint: '312-A',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedBedType,
                        decoration: _inputDecoration('Bed type'),
                        items: _bedTypes.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(_humanize(type)),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedBedType = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: _inputDecoration('Bed notes'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (numberController.text.trim().isEmpty) {
                            _showSnack(
                              'Bed number is required.',
                              error: true,
                            );
                            return;
                          }

                          final room = _rooms.firstWhere(
                            (item) => item['id']?.toString() == selectedRoomId,
                          );

                          final wardId = room['ward_id']?.toString();

                          if (wardId == null || wardId.isEmpty) {
                            _showSnack(
                              'Selected room has no valid ward.',
                              error: true,
                            );
                            return;
                          }

                          final bedNumber = numberController.text.trim();
                          final duplicate = _beds.any(
                            (bed) =>
                                bed['id']?.toString() !=
                                    existing?['id']?.toString() &&
                                bed['bed_number']
                                        ?.toString()
                                        .trim()
                                        .toLowerCase() ==
                                    bedNumber.toLowerCase(),
                          );

                          if (duplicate) {
                            _showSnack(
                              'Bed number $bedNumber is already in use at this hospital.',
                              error: true,
                            );
                            return;
                          }

                          final capacity = int.tryParse(
                                  room['capacity']?.toString() ?? '') ??
                              0;
                          final bedsInRoom = _beds.where(
                            (bed) =>
                                bed['room_id']?.toString() == selectedRoomId &&
                                bed['id']?.toString() !=
                                    existing?['id']?.toString() &&
                                bed['is_active'] != false,
                          );

                          if (capacity > 0 && bedsInRoom.length >= capacity) {
                            _showSnack(
                              'This room is full ($capacity of $capacity beds). Increase the room capacity or choose another room.',
                              error: true,
                            );
                            return;
                          }

                          setDialogState(() => saving = true);

                          try {
                            if (existing == null) {
                              await _service.addBed(
                                hospitalId: _selectedHospitalId!,
                                wardId: wardId,
                                roomId: selectedRoomId,
                                bedNumber: numberController.text,
                                bedLabel: labelController.text,
                                bedType: selectedBedType,
                                notes: notesController.text,
                              );
                            } else {
                              await _service.updateBed(
                                hospitalId: _selectedHospitalId!,
                                bedId: existing['id'].toString(),
                                wardId: wardId,
                                roomId: selectedRoomId,
                                bedNumber: numberController.text,
                                bedLabel: labelController.text,
                                bedType: selectedBedType,
                                notes: notesController.text,
                              );
                            }

                            if (!dialogContext.mounted) return;

                            Navigator.pop(dialogContext);

                            _showSnack(
                              existing == null
                                  ? 'Bed added successfully.'
                                  : 'Bed updated successfully.',
                            );

                            await _loadStructure();
                          } catch (e) {
                            _showSnack(
                              'Could not save bed: $e',
                              error: true,
                            );

                            setDialogState(() => saving = false);
                          }
                        },
                  icon: Icon(
                    existing == null ? Icons.bed_rounded : Icons.save_rounded,
                  ),
                  label: Text(
                    existing == null ? 'Add Bed' : 'Save Changes',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    numberController.dispose();
    labelController.dispose();
    notesController.dispose();
  }

  Future<void> _toggleActive({
    required String table,
    required Map<String, dynamic> record,
  }) async {
    if (_actionBusy || _selectedHospitalId == null) return;

    final id = record['id']?.toString();

    if (id == null || id.isEmpty) return;

    final newValue = record['is_active'] == false;

    setState(() => _actionBusy = true);

    try {
      await _service.setActive(
        table: table,
        recordId: id,
        hospitalId: _selectedHospitalId!,
        active: newValue,
      );

      _showSnack(
        newValue
            ? 'Record activated successfully.'
            : 'Record deactivated successfully.',
      );

      await _loadStructure();
    } catch (e) {
      _showSnack(
        'Could not update record: $e',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _hospitals.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      );
    }

    if (_error != null && _hospitals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _ErrorState(
            message: _error!,
            onRetry: _loadInitialData,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: Column(
        children: [
          _buildHeader(),
          _buildSummary(),
          _buildTabs(),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBuildings(),
                    _buildFloors(),
                    _buildWards(),
                    _buildRooms(),
                    _buildBeds(),
                  ],
                ),
                if (_loading)
                  Positioned.fill(
                    child: ColoredBox(
                      color: context.cBgPrimary.withValues(
                        alpha: 0.58,
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: context.cAccentReadable,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _actionBusy ? null : _openAddDialog,
        icon: const Icon(Icons.add_rounded),
        label: Text(_addLabel),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;

          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hospital Structure',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Configure each hospital’s own buildings, floors, wards, rooms and beds.',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          );

          final controls = Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: compact ? constraints.maxWidth : 290,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedHospitalId,
                  decoration: _inputDecoration('Current hospital'),
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
                          });

                          await _loadStructure();
                        },
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HospitalBedBoardPage(
                        initialHospitalId: _selectedHospitalId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.bed_rounded),
                label: const Text('Live Bed Board'),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _loadStructure,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 15),
                controls,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 18),
              controls,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummary() {
    final items = [
      _SummaryItem(
        label: 'Buildings',
        value: _buildings.length,
        icon: Icons.apartment_rounded,
      ),
      _SummaryItem(
        label: 'Floors',
        value: _floors.length,
        icon: Icons.layers_rounded,
      ),
      _SummaryItem(
        label: 'Wards',
        value: _wards.length,
        icon: Icons.local_hospital_rounded,
      ),
      _SummaryItem(
        label: 'Rooms',
        value: _rooms.length,
        icon: Icons.meeting_room_rounded,
      ),
      _SummaryItem(
        label: 'Available Beds',
        value: _availableBeds,
        icon: Icons.bed_rounded,
      ),
      _SummaryItem(
        label: 'Occupied Beds',
        value: _occupiedBeds,
        icon: Icons.person_rounded,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                        color: context.cAccentReadable.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(item.icon, color: context.cAccentReadable),
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
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            item.label,
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
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) => card(items[index], 180),
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
            children: items.map((item) => card(item, width)).toList(),
          );
        },
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabs: const [
          Tab(
            icon: Icon(Icons.apartment_rounded),
            text: 'Buildings',
          ),
          Tab(
            icon: Icon(Icons.layers_rounded),
            text: 'Floors',
          ),
          Tab(
            icon: Icon(Icons.local_hospital_rounded),
            text: 'Wards',
          ),
          Tab(
            icon: Icon(Icons.meeting_room_rounded),
            text: 'Rooms',
          ),
          Tab(
            icon: Icon(Icons.bed_rounded),
            text: 'Beds',
          ),
        ],
      ),
    );
  }

  Widget _buildBuildings() {
    if (_buildings.isEmpty) {
      return _emptyTab(
        icon: Icons.apartment_outlined,
        title: 'No buildings added',
        message:
            'Add the hospital’s main building, wings or specialist blocks.',
      );
    }

    return _listTab(
      children: _buildings.map((building) {
        return _StructureCard(
          icon: Icons.apartment_rounded,
          title: building['name']?.toString() ?? 'Building',
          subtitle: [
            if (building['code'] != null) 'Code: ${building['code']}',
            if (building['reception_location'] != null)
              'Reception: ${building['reception_location']}',
          ].join(' • '),
          active: building['is_active'] != false,
          onEdit: () => _showBuildingDialog(
            existing: building,
          ),
          onToggle: () => _toggleActive(
            table: 'hospital_buildings',
            record: building,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFloors() {
    if (_floors.isEmpty) {
      return _emptyTab(
        icon: Icons.layers_outlined,
        title: 'No floors added',
        message: 'Add floors under the correct hospital building.',
      );
    }

    return _listTab(
      children: _floors.map((floor) {
        return _StructureCard(
          icon: Icons.layers_rounded,
          title: floor['name']?.toString() ?? 'Floor',
          subtitle: [
            _buildingName(floor['building_id']),
            if (floor['floor_number'] != null)
              'Number: ${floor['floor_number']}',
            if (floor['code'] != null) 'Code: ${floor['code']}',
          ].join(' • '),
          active: floor['is_active'] != false,
          onEdit: () => _showFloorDialog(existing: floor),
          onToggle: () => _toggleActive(
            table: 'hospital_floors',
            record: floor,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWards() {
    if (_wards.isEmpty) {
      return _emptyTab(
        icon: Icons.local_hospital_outlined,
        title: 'No wards added',
        message: 'Create general, surgical, ICU, maternity and other wards.',
      );
    }

    return _listTab(
      children: _wards.map((ward) {
        final rule = _visitorRuleForWard(ward['id']);

        return _StructureCard(
          icon: Icons.local_hospital_rounded,
          title: ward['name']?.toString() ?? 'Ward',
          subtitle: [
            _buildingName(ward['building_id']),
            _floorName(ward['floor_id']),
            _humanize(ward['ward_type']),
            'Visitors: ${_humanize(rule?['visitor_mode'])}',
          ].join(' • '),
          active: ward['is_active'] != false,
          onEdit: () => _showWardDialog(existing: ward),
          onToggle: () => _toggleActive(
            table: 'hospital_wards',
            record: ward,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRooms() {
    if (_rooms.isEmpty) {
      return _emptyTab(
        icon: Icons.meeting_room_outlined,
        title: 'No rooms added',
        message: 'Add private, shared, ICU and isolation rooms.',
      );
    }

    return _listTab(
      children: _rooms.map((room) {
        final name = room['room_name']?.toString().trim() ?? '';

        return _StructureCard(
          icon: Icons.meeting_room_rounded,
          title: name.isEmpty
              ? 'Room ${room['room_number']}'
              : '$name — ${room['room_number']}',
          subtitle: [
            _wardName(room['ward_id']),
            _humanize(room['room_type']),
            'Capacity: ${room['capacity']}',
            if (room['is_isolation'] == true) 'Isolation',
          ].join(' • '),
          active: room['is_active'] != false,
          onEdit: () => _showRoomDialog(existing: room),
          onToggle: () => _toggleActive(
            table: 'hospital_rooms',
            record: room,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBeds() {
    if (_beds.isEmpty) {
      return _emptyTab(
        icon: Icons.bed_outlined,
        title: 'No beds added',
        message: 'Add individual beds under each hospital room.',
      );
    }

    return _listTab(
      children: _beds.map((bed) {
        final label = bed['bed_label']?.toString().trim() ?? '';

        return _StructureCard(
          icon: Icons.bed_rounded,
          title: label.isEmpty ? 'Bed ${bed['bed_number']}' : label,
          subtitle: [
            _roomName(bed['room_id']),
            _wardName(bed['ward_id']),
            _humanize(bed['bed_type']),
          ].join(' • '),
          status: bed['status']?.toString(),
          active: bed['is_active'] != false,
          onEdit: () => _showBedDialog(existing: bed),
          onToggle: () => _toggleActive(
            table: 'hospital_beds',
            record: bed,
          ),
        );
      }).toList(),
    );
  }

  Widget _listTab({
    required List<Widget> children,
  }) {
    return RefreshIndicator(
      onRefresh: _loadStructure,
      color: context.cAccentReadable,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
        children: [
          Text(
            _hospitalName,
            style: TextStyle(
              color: context.cTextSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _emptyTab({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return RefreshIndicator(
      onRefresh: _loadStructure,
      color: context.cAccentReadable,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 100),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 48,
            ),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(24),
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
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _openAddDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(_addLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;
}

class _StructureCard extends StatelessWidget {
  const _StructureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onEdit,
    required this.onToggle,
    this.status,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final String? status;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  Color _statusColor(
    BuildContext context,
    String? status,
  ) {
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

  String _humanize(String value) {
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              color: color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle.isEmpty ? 'No additional details' : subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _humanize(status!),
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Record actions',
            onSelected: (value) {
              if (value == 'edit') {
                onEdit();
              } else if (value == 'toggle') {
                onToggle();
              }
            },
            itemBuilder: (_) {
              return [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.edit_rounded),
                    title: Text('Edit'),
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      active
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                    title: Text(
                      active ? 'Deactivate' : 'Activate',
                    ),
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
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
            size: 44,
            color: CorviaColors.danger,
          ),
          const SizedBox(height: 12),
          Text(
            'Hospital structure could not load',
            textAlign: TextAlign.center,
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
