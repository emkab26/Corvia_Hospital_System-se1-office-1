import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalPharmacistsPage extends StatefulWidget {
  const HospitalPharmacistsPage({
    super.key,
  });

  @override
  State<HospitalPharmacistsPage> createState() =>
      _HospitalPharmacistsPageState();
}

class _HospitalPharmacistsPageState extends State<HospitalPharmacistsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String? _error;
  String _selectedFilter = 'All';

  List<_HospitalPharmacist> _pharmacists = [];

  static const List<String> _filters = [
    'All',
    'Active',
    'Inactive',
    'Pending Review',
    'Verified',
  ];

  @override
  void initState() {
    super.initState();

    _loadPharmacists();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _loadPharmacists() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _supabase.rpc(
        'corvia_admin_list_pharmacists',
      );

      final rows = response is List
          ? response
              .whereType<Map>()
              .map(
                (row) => Map<String, dynamic>.from(row),
              )
              .toList()
          : <Map<String, dynamic>>[];

      final pharmacists = rows.map(_HospitalPharmacist.fromMap).toList();

      pharmacists.sort(
        (first, second) {
          if (first.isActive != second.isActive) {
            return first.isActive ? -1 : 1;
          }

          return first.displayName.toLowerCase().compareTo(
                second.displayName.toLowerCase(),
              );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _pharmacists = pharmacists;
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

  String _cleanError(Object error) {
    if (error is PostgrestException) {
      final details = error.details?.toString().trim() ?? '';

      if (details.isNotEmpty &&
          details.toLowerCase() != 'null' &&
          details != error.message) {
        return '${error.message} $details';
      }

      return error.message;
    }

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
  }

  List<_HospitalPharmacist> get _visiblePharmacists {
    final search = _searchController.text.trim().toLowerCase();

    return _pharmacists.where(
      (pharmacist) {
        bool matchesFilter;

        switch (_selectedFilter) {
          case 'Active':
            matchesFilter = pharmacist.isActive;
            break;

          case 'Inactive':
            matchesFilter = !pharmacist.isActive;
            break;

          case 'Pending Review':
            matchesFilter = pharmacist.licenseStatus == 'pending_review';
            break;

          case 'Verified':
            matchesFilter = pharmacist.licenseStatus == 'verified';
            break;

          case 'All':
          default:
            matchesFilter = true;
        }

        if (!matchesFilter) {
          return false;
        }

        if (search.isEmpty) {
          return true;
        }

        final searchable = [
          pharmacist.displayName,
          pharmacist.email,
          pharmacist.employeeNumber,
          pharmacist.licenseNumber,
          pharmacist.pharmacyName,
          pharmacist.departmentName,
          pharmacist.phone,
        ].join(' ').toLowerCase();

        return searchable.contains(search);
      },
    ).toList();
  }

  int get _activeCount {
    return _pharmacists
        .where(
          (pharmacist) => pharmacist.isActive,
        )
        .length;
  }

  int get _inactiveCount {
    return _pharmacists
        .where(
          (pharmacist) => !pharmacist.isActive,
        )
        .length;
  }

  int get _pendingCount {
    return _pharmacists.where(
      (pharmacist) {
        return pharmacist.licenseStatus == 'pending_review';
      },
    ).length;
  }

  int get _verifiedCount {
    return _pharmacists.where(
      (pharmacist) {
        return pharmacist.licenseStatus == 'verified';
      },
    ).length;
  }

  Future<void> _linkPharmacist() async {
    final result = await showDialog<_LinkPharmacistResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const _LinkPharmacistDialog();
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _supabase.rpc(
        'corvia_admin_link_pharmacist',
        params: {
          'p_email': result.email,
          'p_employee_number': _nullableText(result.employeeNumber),
          'p_license_number': _nullableText(result.licenseNumber),
          'p_pharmacy_name': _nullableText(result.pharmacyName),
          'p_department_name': _nullableText(result.departmentName),
          'p_phone': _nullableText(result.phone),
        },
      );

      await _loadPharmacists();

      _showMessage(
        'Pharmacist account linked successfully.',
      );
    } catch (error) {
      _showMessage(
        'Could not link pharmacist. ${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _editPharmacist(
    _HospitalPharmacist pharmacist,
  ) async {
    final result = await showDialog<_EditPharmacistResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _EditPharmacistDialog(
          pharmacist: pharmacist,
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _supabase.rpc(
        'corvia_admin_update_pharmacist',
        params: {
          'p_pharmacist_id': pharmacist.id,
          'p_employee_number': result.employeeNumber,
          'p_license_number': result.licenseNumber,
          'p_pharmacy_name': result.pharmacyName,
          'p_department_name': result.departmentName,
          'p_phone': result.phone,
        },
      );

      await _loadPharmacists();

      _showMessage(
        'Pharmacist details updated.',
      );
    } catch (error) {
      _showMessage(
        'Could not update pharmacist. ${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _changeActiveState(
    _HospitalPharmacist pharmacist,
  ) async {
    final newState = !pharmacist.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            newState ? 'Activate Pharmacist' : 'Deactivate Pharmacist',
          ),
          content: Text(
            newState
                ? 'Restore pharmacy staff access for '
                    '${pharmacist.displayName}?'
                : 'Remove pharmacy staff access for '
                    '${pharmacist.displayName}?\n\n'
                    'Their patient profile will not be deactivated.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(
                newState ? 'Activate' : 'Deactivate',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _supabase.rpc(
        'corvia_admin_set_pharmacist_active',
        params: {
          'p_pharmacist_id': pharmacist.id,
          'p_is_active': newState,
        },
      );

      await _loadPharmacists();

      _showMessage(
        newState
            ? 'Pharmacist access activated.'
            : 'Pharmacist access deactivated.',
      );
    } catch (error) {
      _showMessage(
        'Could not change pharmacist access. '
        '${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String? _nullableText(String value) {
    final text = value.trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  Color _licenseColor(String status) {
    switch (status) {
      case 'verified':
        return Colors.green.shade700;

      case 'pending_review':
        return Colors.orange.shade800;

      case 'rejected':
        return CorviaColors.danger;

      case 'not_provided':
      default:
        return Colors.grey.shade700;
    }
  }

  String _licenseLabel(String status) {
    switch (status) {
      case 'verified':
        return 'Verified';

      case 'pending_review':
        return 'Pending Review';

      case 'rejected':
        return 'Rejected';

      case 'not_provided':
      default:
        return 'Not Provided';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Pharmacists',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _saving ? null : _loadPharmacists,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
          IconButton(
            tooltip: 'Link Pharmacist',
            onPressed: _saving ? null : _linkPharmacist,
            icon: const Icon(
              Icons.person_add_alt_1,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _linkPharmacist,
        icon: const Icon(
          Icons.person_add_alt_1,
        ),
        label: const Text(
          'Link Pharmacist',
        ),
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

    final pharmacists = _visiblePharmacists;

    return RefreshIndicator(
      onRefresh: _loadPharmacists,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          18,
          18,
          18,
          95,
        ),
        children: [
          Text(
            'Pharmacy Staff',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Manage pharmacists linked to this hospital. '
            'Professional registration remains pending until '
            'independently verified.',
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _buildSummary(),
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: 'Search name, email, employee or licence number',
              prefixIcon: const Icon(
                Icons.search,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
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
            'Pharmacists (${pharmacists.length})',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (pharmacists.isEmpty)
            _buildEmptyState()
          else
            ...pharmacists.map(
              _buildPharmacistCard,
            ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final items = [
      _SummaryItem(
        label: 'Active',
        value: _activeCount,
        icon: Icons.check_circle_outline,
        color: Colors.green.shade700,
      ),
      _SummaryItem(
        label: 'Inactive',
        value: _inactiveCount,
        icon: Icons.block_outlined,
        color: CorviaColors.danger,
      ),
      _SummaryItem(
        label: 'Pending Review',
        value: _pendingCount,
        icon: Icons.pending_actions_outlined,
        color: Colors.orange.shade800,
      ),
      _SummaryItem(
        label: 'Verified',
        value: _verifiedCount,
        icon: Icons.verified_outlined,
        color: Colors.blue.shade700,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final columns = constraints.maxWidth >= 850
            ? 4
            : constraints.maxWidth >= 500
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
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
            final item = items[index];

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

  Widget _buildPharmacistCard(
    _HospitalPharmacist pharmacist,
  ) {
    final licenseColor = _licenseColor(
      pharmacist.licenseStatus,
    );

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
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: pharmacist.isActive
                      ? Colors.green.withValues(alpha: 0.12)
                      : CorviaColors.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.local_pharmacy_outlined,
                  color: pharmacist.isActive
                      ? Colors.green.shade700
                      : CorviaColors.danger,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pharmacist.displayName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pharmacist.email,
                      style: TextStyle(
                        color: context.cTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pharmacist.employeeNumber.isEmpty
                          ? 'No employee number'
                          : pharmacist.employeeNumber,
                      style: TextStyle(
                        color: context.cTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(
                label: pharmacist.isActive ? 'Active' : 'Inactive',
                color: pharmacist.isActive
                    ? Colors.green.shade700
                    : CorviaColors.danger,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
            color: context.cDivider,
          ),
          const SizedBox(height: 8),
          _InformationRow(
            icon: Icons.store_outlined,
            label: 'Pharmacy',
            value: pharmacist.pharmacyName.isEmpty
                ? 'Not recorded'
                : pharmacist.pharmacyName,
          ),
          _InformationRow(
            icon: Icons.apartment_outlined,
            label: 'Department',
            value: pharmacist.departmentName.isEmpty
                ? 'Not recorded'
                : pharmacist.departmentName,
          ),
          _InformationRow(
            icon: Icons.badge_outlined,
            label: 'SAPC number',
            value: pharmacist.licenseNumber.isEmpty
                ? 'Not provided'
                : pharmacist.licenseNumber,
          ),
          _InformationRow(
            icon: Icons.verified_user_outlined,
            label: 'Verification',
            value: _licenseLabel(
              pharmacist.licenseStatus,
            ),
            valueColor: licenseColor,
          ),
          _InformationRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: pharmacist.phone.isEmpty ? 'Not recorded' : pharmacist.phone,
          ),
          if (!pharmacist.profileActive) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CorviaColors.warning.withValues(
                  alpha: 0.10,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'The main profile is inactive. Activating the '
                'pharmacist staff record alone will not restore login.',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              final compact = constraints.maxWidth < 520;

              final editButton = OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        _editPharmacist(pharmacist);
                      },
                icon: const Icon(
                  Icons.edit_outlined,
                ),
                label: const Text(
                  'Edit Details',
                ),
              );

              final stateButton = pharmacist.isActive
                  ? OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              _changeActiveState(pharmacist);
                            },
                      icon: const Icon(
                        Icons.block_outlined,
                      ),
                      label: const Text(
                        'Deactivate',
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              _changeActiveState(pharmacist);
                            },
                      icon: const Icon(
                        Icons.check_circle_outline,
                      ),
                      label: const Text(
                        'Activate',
                      ),
                    );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    editButton,
                    const SizedBox(height: 10),
                    stateButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: editButton,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: stateButton,
                  ),
                ],
              );
            },
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
            'No pharmacists found',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Create an Auth login first, then use Link Pharmacist '
            'to connect the account to this hospital.',
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
              borderRadius: BorderRadius.circular(21),
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
                  'Pharmacists could not load',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 11),
                SelectableText(
                  _error ?? 'Unknown pharmacist error.',
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
                    onPressed: _loadPharmacists,
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

class _HospitalPharmacist {
  const _HospitalPharmacist({
    required this.id,
    required this.profileId,
    required this.email,
    required this.firstName,
    required this.surname,
    required this.employeeNumber,
    required this.licenseNumber,
    required this.licenseStatus,
    required this.pharmacyName,
    required this.departmentName,
    required this.phone,
    required this.isActive,
    required this.profileActive,
  });

  factory _HospitalPharmacist.fromMap(
    Map<String, dynamic> map,
  ) {
    return _HospitalPharmacist(
      id: _text(map['pharmacist_id']),
      profileId: _text(map['profile_id']),
      email: _text(map['email']),
      firstName: _text(map['first_name']),
      surname: _text(map['surname']),
      employeeNumber: _text(map['employee_number']),
      licenseNumber: _text(map['license_number']),
      licenseStatus: _text(
        map['license_verification_status'],
        fallback: 'not_provided',
      ).toLowerCase(),
      pharmacyName: _text(map['pharmacy_name']),
      departmentName: _text(map['department_name']),
      phone: _text(map['phone']),
      isActive: map['pharmacist_active'] == true,
      profileActive: map['profile_active'] != false,
    );
  }

  final String id;
  final String profileId;
  final String email;
  final String firstName;
  final String surname;
  final String employeeNumber;
  final String licenseNumber;
  final String licenseStatus;
  final String pharmacyName;
  final String departmentName;
  final String phone;
  final bool isActive;
  final bool profileActive;

  String get displayName {
    final name = [
      firstName,
      surname,
    ]
        .where(
          (part) => part.isNotEmpty,
        )
        .join(' ');

    return name.isEmpty ? email : name;
  }

  static String _text(
    dynamic value, {
    String fallback = '',
  }) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }
}

class _LinkPharmacistResult {
  const _LinkPharmacistResult({
    required this.email,
    required this.employeeNumber,
    required this.licenseNumber,
    required this.pharmacyName,
    required this.departmentName,
    required this.phone,
  });

  final String email;
  final String employeeNumber;
  final String licenseNumber;
  final String pharmacyName;
  final String departmentName;
  final String phone;
}

class _EditPharmacistResult {
  const _EditPharmacistResult({
    required this.employeeNumber,
    required this.licenseNumber,
    required this.pharmacyName,
    required this.departmentName,
    required this.phone,
  });

  final String employeeNumber;
  final String licenseNumber;
  final String pharmacyName;
  final String departmentName;
  final String phone;
}

class _LinkPharmacistDialog extends StatefulWidget {
  const _LinkPharmacistDialog();

  @override
  State<_LinkPharmacistDialog> createState() => _LinkPharmacistDialogState();
}

class _LinkPharmacistDialogState extends State<_LinkPharmacistDialog> {
  late final TextEditingController _emailController;
  late final TextEditingController _employeeController;
  late final TextEditingController _licenseController;
  late final TextEditingController _pharmacyController;
  late final TextEditingController _departmentController;
  late final TextEditingController _phoneController;

  String? _emailError;

  @override
  void initState() {
    super.initState();

    _emailController = TextEditingController();
    _employeeController = TextEditingController();
    _licenseController = TextEditingController();

    _pharmacyController = TextEditingController(
      text: 'Corvia Hospital Pharmacy',
    );

    _departmentController = TextEditingController(
      text: 'Pharmacy',
    );

    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _employeeController.dispose();
    _licenseController.dispose();
    _pharmacyController.dispose();
    _departmentController.dispose();
    _phoneController.dispose();

    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();

    setState(() {
      _emailError = email.isEmpty || !email.contains('@')
          ? 'Enter a valid existing Auth email.'
          : null;
    });

    if (_emailError != null) {
      return;
    }

    Navigator.of(context).pop(
      _LinkPharmacistResult(
        email: email,
        employeeNumber: _employeeController.text.trim(),
        licenseNumber: _licenseController.text.trim(),
        pharmacyName: _pharmacyController.text.trim(),
        departmentName: _departmentController.text.trim(),
        phone: _phoneController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Link Pharmacist',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CorviaColors.warning.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'The login must already exist under Supabase '
                  'Authentication. Corvia will not create or expose '
                  'a password from this page.',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Existing Auth Email',
                  hintText: 'pharmacist@hospital.co.za',
                  errorText: _emailError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _employeeController,
                decoration: const InputDecoration(
                  labelText: 'Employee Number (Optional)',
                  hintText: 'Generated automatically when empty',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _licenseController,
                decoration: const InputDecoration(
                  labelText: 'SAPC Number (Optional)',
                  helperText: 'Captured numbers remain Pending Review.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pharmacyController,
                decoration: const InputDecoration(
                  labelText: 'Pharmacy Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _departmentController,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            'Cancel',
          ),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(
            Icons.link,
          ),
          label: const Text(
            'Link Pharmacist',
          ),
        ),
      ],
    );
  }
}

class _EditPharmacistDialog extends StatefulWidget {
  const _EditPharmacistDialog({
    required this.pharmacist,
  });

  final _HospitalPharmacist pharmacist;

  @override
  State<_EditPharmacistDialog> createState() => _EditPharmacistDialogState();
}

class _EditPharmacistDialogState extends State<_EditPharmacistDialog> {
  late final TextEditingController _employeeController;
  late final TextEditingController _licenseController;
  late final TextEditingController _pharmacyController;
  late final TextEditingController _departmentController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();

    _employeeController = TextEditingController(
      text: widget.pharmacist.employeeNumber,
    );

    _licenseController = TextEditingController(
      text: widget.pharmacist.licenseNumber,
    );

    _pharmacyController = TextEditingController(
      text: widget.pharmacist.pharmacyName,
    );

    _departmentController = TextEditingController(
      text: widget.pharmacist.departmentName,
    );

    _phoneController = TextEditingController(
      text: widget.pharmacist.phone,
    );
  }

  @override
  void dispose() {
    _employeeController.dispose();
    _licenseController.dispose();
    _pharmacyController.dispose();
    _departmentController.dispose();
    _phoneController.dispose();

    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _EditPharmacistResult(
        employeeNumber: _employeeController.text.trim(),
        licenseNumber: _licenseController.text.trim(),
        pharmacyName: _pharmacyController.text.trim(),
        departmentName: _departmentController.text.trim(),
        phone: _phoneController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Edit ${widget.pharmacist.displayName}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _employeeController,
                decoration: const InputDecoration(
                  labelText: 'Employee Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _licenseController,
                decoration: const InputDecoration(
                  labelText: 'SAPC Number',
                  helperText: 'Changing this number resets verification '
                      'to Pending Review.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pharmacyController,
                decoration: const InputDecoration(
                  labelText: 'Pharmacy Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _departmentController,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            'Cancel',
          ),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(
            Icons.save_outlined,
          ),
          label: const Text(
            'Save Changes',
          ),
        ),
      ],
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
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
        maxWidth: 150,
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

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: context.cTextMuted,
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 105,
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
                color: valueColor ?? context.cTextPrimary,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
