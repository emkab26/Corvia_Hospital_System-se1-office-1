import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env.dart';

import '../../theme/app_theme.dart';
import 'hospital_page_shared.dart';

enum _StaffRole {
  doctor('Doctor', Icons.medical_services_rounded),
  specialist('Specialist', Icons.monitor_heart_rounded),
  nurse('Nurse', Icons.vaccines_rounded),
  pharmacist('Pharmacist', Icons.local_pharmacy_rounded),
  reception('Receptionist', Icons.support_agent_rounded),
  labAdmin('Lab Admin', Icons.science_rounded);

  const _StaffRole(this.label, this.icon);

  final String label;
  final IconData icon;

  String get databaseValue => name;
}

class HospitalStaffAccountsPage extends StatefulWidget {
  const HospitalStaffAccountsPage({super.key});

  @override
  State<HospitalStaffAccountsPage> createState() =>
      _HospitalStaffAccountsPageState();
}

class _HospitalStaffAccountsPageState extends State<HospitalStaffAccountsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _specializationController =
      TextEditingController();
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _employeeNumberController =
      TextEditingController();
  final TextEditingController _pharmacyNameController = TextEditingController();

  bool _loading = true;
  bool _searching = false;
  bool _hasSearched = false;
  bool _saving = false;
  String? _removingProfileId;
  String? _removingLabAdminProfileId;
  String? _error;
  String? _searchError;
  String _hospitalName = 'Hospital';
  String? _selectedDepartmentId;
  _StaffRole _selectedRole = _StaffRole.doctor;
  Map<String, dynamic>? _selectedAccount;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _linkedStaff = [];
  List<Map<String, dynamic>> _labAdmins = [];
  List<Map<String, dynamic>> _departments = [];

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _specializationController.dispose();
    _licenseController.dispose();
    _employeeNumberController.dispose();
    _pharmacyNameController.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final scope = await HospitalAdminScope.load(
        _supabase,
        fallbackName: 'Hospital',
      );
      final rows = await _supabase
          .from('departments')
          .select('id, name, is_active')
          .eq('hospital_id', scope.hospitalId)
          .order('name', ascending: true);
      final linkedStaffResponse = await _supabase.rpc(
        'corvia_admin_list_staff_accounts',
      );
      final labAdminsResponse = await _supabase.rpc(
        'corvia_admin_list_hospital_lab_admins',
      );

      if (!mounted) return;

      setState(() {
        _hospitalName = scope.hospitalName;
        _departments = HospitalDataTools.rows(rows)
            .where((row) => row['is_active'] != false)
            .toList();
        _linkedStaff = HospitalDataTools.rows(linkedStaffResponse);
        _labAdmins = HospitalDataTools.rows(labAdminsResponse)
            .where((admin) => admin['is_active'] != false)
            .toList();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _cleanError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _searchAccounts() async {
    final query = _searchController.text.trim();

    if (query.length < 3) {
      _showMessage('Enter at least 3 characters of a name or email address.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _hasSearched = true;
      _searchError = null;
      _selectedAccount = null;
      _accounts = [];
    });

    try {
      final response = await _supabase.rpc(
        'corvia_admin_search_accounts_json',
        params: {
          'p_search': query,
          'p_limit': 25,
        },
      );

      if (!mounted) return;

      setState(() {
        _accounts = _accountRows(response);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _searchError = _cleanError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  List<Map<String, dynamic>> _accountRows(dynamic response) {
    if (response is List) {
      return response
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }

    if (response is Map) {
      return [Map<String, dynamic>.from(response)];
    }

    throw FormatException(
      'Supabase returned an unexpected account-search response: '
      '${response.runtimeType}.',
    );
  }

  void _selectAccount(Map<String, dynamic> account) {
    setState(() {
      _selectedAccount = account;
      _clearProfessionalFields();
    });
  }

  void _clearProfessionalFields() {
    _specializationController.clear();
    _licenseController.clear();
    _employeeNumberController.clear();
    _pharmacyNameController.clear();
    _selectedDepartmentId = null;
  }

  Future<void> _linkAccount() async {
    final account = _selectedAccount;
    final profileId = account?['profile_id']?.toString().trim() ?? '';

    if (profileId.isEmpty) {
      _showMessage('Select an existing Corvia account first.');
      return;
    }

    if ((_selectedRole == _StaffRole.doctor ||
            _selectedRole == _StaffRole.specialist) &&
        _specializationController.text.trim().isEmpty) {
      _showMessage('Enter the doctor or specialist field.');
      return;
    }

    if (_selectedRole == _StaffRole.labAdmin) {
      final name = _accountName(account!);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Appoint Lab Admin?'),
          content: Text(
            '$name will receive administration-only access to the internal laboratory. Any Technician or Verifier access for this account will be deactivated.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Appoint Lab Admin')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _saving = true);

    try {
      if (_selectedRole == _StaffRole.labAdmin) {
        await _supabase.rpc(
          'corvia_admin_appoint_hospital_lab_admin',
          params: {'p_profile_id': profileId},
        );
      } else {
        await _supabase.rpc(
          'corvia_admin_link_staff_account',
          params: {
            'p_profile_id': profileId,
            'p_staff_role': _selectedRole.databaseValue,
            'p_department_id': _selectedDepartmentId,
            'p_specialization': _nullable(_specializationController.text),
            'p_license_number': _nullable(_licenseController.text),
            'p_employee_number': _nullable(_employeeNumberController.text),
            'p_pharmacy_name': _nullable(_pharmacyNameController.text),
          },
        );
      }

      if (!mounted) return;

      final name = _accountName(account!);
      setState(() {
        _selectedAccount = null;
        _accounts = [];
        _hasSearched = false;
        _searchController.clear();
        _clearProfessionalFields();
      });
      await _loadLinkedStaff();
      await _loadLabAdmins();
      _showMessage('$name is now linked as ${_selectedRole.label}.');
    } catch (error) {
      if (mounted) {
        _showMessage('Could not link this account. ${_cleanError(error)}');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _loadLinkedStaff() async {
    final response = await _supabase.rpc(
      'corvia_admin_list_staff_accounts',
    );

    if (!mounted) return;

    setState(() {
      _linkedStaff = HospitalDataTools.rows(response);
    });
  }

  Future<void> _loadLabAdmins() async {
    final response = await _supabase.rpc(
      'corvia_admin_list_hospital_lab_admins',
    );
    if (!mounted) return;
    setState(() {
      _labAdmins = HospitalDataTools.rows(response)
          .where((admin) => admin['is_active'] != false)
          .toList();
    });
  }

  Future<void> _confirmRemoveLabAdmin(Map<String, dynamic> account) async {
    final profileId = account['profile_id']?.toString().trim() ?? '';
    if (profileId.isEmpty || _removingLabAdminProfileId != null) return;
    final name = _accountName(account);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Lab Admin?'),
        content: Text(
          '$name will lose laboratory administration access. This does not grant Technician or Verifier access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: CorviaColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.person_remove_rounded),
            label: const Text('Remove Lab Admin'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingLabAdminProfileId = profileId);
    try {
      await _supabase.rpc(
        'corvia_admin_remove_hospital_lab_admin',
        params: {'p_profile_id': profileId},
      );
      await _loadLabAdmins();
      if (mounted) _showMessage('$name is no longer a Lab Admin.');
    } catch (error) {
      if (mounted) {
        _showMessage(
            'Could not remove Lab Admin access. ${_cleanError(error)}');
      }
    } finally {
      if (mounted) setState(() => _removingLabAdminProfileId = null);
    }
  }

  Future<void> _confirmRemoveStaff(Map<String, dynamic> account) async {
    final profileId = account['profile_id']?.toString().trim() ?? '';
    if (profileId.isEmpty || _removingProfileId != null) return;

    final name = _accountName(account);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove from hospital?'),
          content: Text(
            '$name will lose staff access to $_hospitalName. Their Corvia login, patient account, and historical records will be preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: CorviaColors.danger,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.person_remove_rounded),
              label: const Text('Remove access'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _removingProfileId = profileId);

    try {
      await _supabase.rpc(
        'corvia_admin_remove_staff_account',
        params: {'p_profile_id': profileId},
      );
      await _loadLinkedStaff();

      if (mounted) {
        _showMessage('$name was removed from $_hospitalName.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Could not remove staff access. ${_cleanError(error)}');
      }
    } finally {
      if (mounted) {
        setState(() => _removingProfileId = null);
      }
    }
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _accountName(Map<String, dynamic> account) {
    final firstName = account['first_name']?.toString().trim() ?? '';
    final surname = account['surname']?.toString().trim() ?? '';
    final fullName = '$firstName $surname'.trim();
    return fullName.isEmpty ? 'Corvia user' : fullName;
  }

  String _linkedRoles(Map<String, dynamic> account) {
    final roles = account['linked_roles'];
    if (roles is List && roles.isNotEmpty) {
      return roles.map((role) => _roleLabel(role.toString())).join(', ');
    }

    final role = account['current_role']?.toString().trim() ?? '';
    return role.isEmpty ? 'Basic account' : _roleLabel(role);
  }

  String _linkedFieldSummary(Map<String, dynamic> account) {
    final parts = <String>[];
    for (final key in const [
      'specialization',
      'department_name',
      'employee_number',
    ]) {
      final value = account[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && !parts.contains(value)) parts.add(value);
    }
    return parts.join(' • ');
  }

  String _roleLabel(String role) {
    return role
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _cleanError(Object error) {
    if (error.toString().contains('corvia_admin_list_staff_accounts') &&
        error.toString().contains('schema cache')) {
      return 'Staff Accounts is unavailable because the required admin '
          'function is missing from this backend. No accounts were changed.';
    }
    return error
        .toString()
        .replaceFirst('PostgrestException(message: ', '')
        .replaceFirst('Exception: ', '')
        .split(', code:')
        .first
        .trim();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 44),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadPage,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HospitalPageHeader(
                  title: 'Staff Accounts',
                  subtitle:
                      'Link an existing Corvia account to $_hospitalName. This does not create a new login.',
                  onRefresh: _loadPage,
                ),
                const SizedBox(height: 22),
                _buildGuidanceCard(),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _showCreateAccountDialog,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Create login for new staff'),
                  ),
                ),
                const SizedBox(height: 12),
                HospitalPanel(
                  title: '1. Find an existing account',
                  subtitle:
                      'Search by the email address or name used when the person registered with Corvia.',
                  icon: Icons.person_search_rounded,
                  child: Column(
                    children: [
                      _buildSearchBar(),
                      if (_searching) ...[
                        const SizedBox(height: 22),
                        const CircularProgressIndicator(),
                      ] else if (_searchError != null) ...[
                        const SizedBox(height: 16),
                        _buildSearchError(),
                      ] else if (_accounts.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        ..._accounts.map(_buildAccountResult),
                      ] else if (_hasSearched) ...[
                        const SizedBox(height: 16),
                        const HospitalEmptyState(
                          icon: Icons.person_off_outlined,
                          title: 'No matching accounts',
                          message:
                              'Check the spelling or ask the staff member to register a basic Corvia account first.',
                        ),
                      ] else if (_searchController.text.trim().length >= 3) ...[
                        const SizedBox(height: 16),
                        const HospitalEmptyState(
                          icon: Icons.manage_search_rounded,
                          title: 'Ready to search',
                          message:
                              'Select Search accounts or press Enter to find matching Corvia accounts.',
                        ),
                      ],
                      const SizedBox(height: 24),
                      Divider(color: context.cDivider),
                      const SizedBox(height: 18),
                      _buildLinkedStaffExpansion(),
                      const SizedBox(height: 14),
                      _buildLabAdminsExpansion(),
                    ],
                  ),
                ),
                if (_selectedAccount != null) ...[
                  const SizedBox(height: 18),
                  HospitalPanel(
                    title: '2. Assign a hospital role',
                    subtitle:
                        'The account keeps its existing patient record and gains staff access for this hospital.',
                    icon: Icons.manage_accounts_rounded,
                    child: _buildRoleForm(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuidanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cAccentReadable.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.cAccentReadable.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: context.cAccentReadable),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'The staff member must register normally first. Use this page only after you have verified their identity and professional details. Paramedic accounts remain under Fleet & Paramedic > Personnel because their qualification and credential expiry require separate verification.',
              style: TextStyle(
                color: context.cTextPrimary,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Creates a normal Corvia login for a new employee without touching the
  /// administrator's own session. Staff roles are still granted only by the
  /// link step below, after the person has signed in once.
  Future<void> _showCreateAccountDialog() async {
    final firstName = TextEditingController();
    final surname = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var saving = false;
    String? error;

    final createdEmail = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Create login for new staff'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'This creates a Corvia login only. Give the person '
                      'their email and temporary password; after they sign '
                      'in once, search for them below and assign their role.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: firstName,
                      decoration: const InputDecoration(labelText: 'First name'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: surname,
                      decoration: const InputDecoration(labelText: 'Surname'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Work email'),
                      validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch((v ?? '').trim())
                          ? null
                          : 'Enter a valid email address.',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      decoration: const InputDecoration(
                        labelText: 'Temporary password',
                        helperText: 'At least 8 characters. Ask them to '
                            'change it after first sign-in.',
                      ),
                      validator: (v) => (v ?? '').length < 8
                          ? 'Use at least 8 characters.'
                          : null,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: TextStyle(color: CorviaColors.danger)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        // Call the sign-up endpoint directly. A second
                        // Supabase client would broadcast SIGNED_IN on web and
                        // replace the administrator's own session.
                        final response = await http
                            .post(
                              Uri.parse('${Env.backend.url}/auth/v1/signup')
                                  .replace(queryParameters: {
                                'redirect_to': Env.oauthRedirectUrl,
                              }),
                              headers: {
                                'apikey': Env.backend.publicKey,
                                'Content-Type': 'application/json',
                              },
                              body: jsonEncode({
                                'email': email.text.trim().toLowerCase(),
                                'password': password.text,
                                'data': {
                                  // Lets the first sign-in create the
                                  // profile; it grants no staff access.
                                  'corvia_registration_type':
                                      'patient_self_registration',
                                  'registration_schema_version': 1,
                                  'first_name': firstName.text.trim(),
                                  'surname': surname.text.trim(),
                                  'created_by_hospital_admin': true,
                                },
                              }),
                            )
                            .timeout(const Duration(seconds: 20));
                        if (response.statusCode >= 400) {
                          final body = jsonDecode(response.body);
                          throw Exception(body is Map
                              ? (body['msg'] ??
                                  body['error_description'] ??
                                  body['message'] ??
                                  response.body)
                              : response.body);
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext)
                              .pop(email.text.trim().toLowerCase());
                        }
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = _cleanError(e);
                        });
                      }
                    },
              child: Text(saving ? 'Creating...' : 'Create login'),
            ),
          ],
        ),
      ),
    );

    for (final c in [firstName, surname, email, password]) {
      c.dispose();
    }

    if (createdEmail != null) {
      _showMessage(
        'Login created for $createdEmail. If email confirmation is on, they '
        'must confirm first. After their first sign-in, search for them here '
        'to assign a role.',
      );
    }
  }

  Widget _buildSearchBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final field = TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchAccounts(),
          onChanged: (_) {
            setState(() {
              _hasSearched = false;
              _searchError = null;
              _accounts = [];
              _selectedAccount = null;
            });
          },
          decoration: const InputDecoration(
            labelText: 'Name or email address',
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'e.g. doctor@corvia.co.za',
          ),
        );
        final button = FilledButton.icon(
          onPressed: _searching ? null : _searchAccounts,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Search accounts'),
        );

        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [field, const SizedBox(height: 12), button],
          );
        }

        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 12),
            SizedBox(height: 56, child: button),
          ],
        );
      },
    );
  }

  Widget _buildAccountResult(Map<String, dynamic> account) {
    final selected = _selectedAccount?['profile_id']?.toString() ==
        account['profile_id']?.toString();
    final email = account['email']?.toString().trim() ?? 'No email available';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? context.cAccentReadable.withValues(alpha: 0.10)
            : context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _selectAccount(account),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? context.cAccentReadable : context.cDivider,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      context.cAccentReadable.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.person_rounded,
                    color: context.cAccentReadable,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _accountName(account),
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$email • ${_linkedRoles(account)}',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  color: selected ? CorviaColors.success : context.cTextMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CorviaColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CorviaColors.danger.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: CorviaColors.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account search failed',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _searchError!,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _searchAccounts,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedStaffExpansion() {
    final staffCount = _linkedStaff.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        backgroundColor: context.cBgSecondary,
        collapsedBackgroundColor: context.cBgSecondary,
        shape: Border.all(color: context.cDivider),
        collapsedShape: Border.all(color: context.cDivider),
        iconColor: CorviaColors.accent,
        collapsedIconColor: context.cTextSecondary,
        leading: Icon(Icons.groups_rounded, color: CorviaColors.accent),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Currently linked to this hospital',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CorviaColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$staffCount',
                style: TextStyle(
                  color: CorviaColors.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Expand to view or remove linked staff accounts.',
          style: TextStyle(color: context.cTextSecondary, fontSize: 13),
        ),
        children: [
          if (_linkedStaff.isEmpty)
            const HospitalEmptyState(
              icon: Icons.groups_outlined,
              title: 'No linked staff accounts',
              message: 'Staff linked through this page will appear here.',
            )
          else
            ..._linkedStaff.map(_buildLinkedStaffCard),
        ],
      ),
    );
  }

  Widget _buildLabAdminsExpansion() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        backgroundColor: context.cBgSecondary,
        collapsedBackgroundColor: context.cBgSecondary,
        shape: Border.all(color: context.cDivider),
        collapsedShape: Border.all(color: context.cDivider),
        leading: Icon(Icons.science_rounded, color: context.cAccentReadable),
        title: Text(
          'Hospital laboratory leadership (${_labAdmins.length})',
          style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          'Lab Admins assign separate Technician and Verifier roles. Lab Admins cannot test or verify results.',
          style: TextStyle(color: context.cTextSecondary, fontSize: 13),
        ),
        children: [
          if (_labAdmins.isEmpty)
            const HospitalEmptyState(
              icon: Icons.science_outlined,
              title: 'No Lab Admin appointed',
              message:
                  'Select an existing account above and assign the Lab Admin role.',
            )
          else
            ..._labAdmins.map(_buildLabAdminCard),
        ],
      ),
    );
  }

  Widget _buildLabAdminCard(Map<String, dynamic> account) {
    final profileId = account['profile_id']?.toString() ?? '';
    final removing = _removingLabAdminProfileId == profileId;
    final email = account['email']?.toString().trim() ?? 'No email available';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: context.cAccentReadable.withValues(alpha: 0.12),
            child: Icon(Icons.admin_panel_settings_outlined,
                color: context.cAccentReadable),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_accountName(account),
                    style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('$email • Administration only',
                    style:
                        TextStyle(color: context.cTextSecondary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _removingLabAdminProfileId == null
                ? () => _confirmRemoveLabAdmin(account)
                : null,
            icon: removing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.person_remove_alt_1_rounded),
            label: Text(removing ? 'Removing...' : 'Remove'),
            style: OutlinedButton.styleFrom(
              foregroundColor: CorviaColors.danger,
              side: BorderSide(
                  color: CorviaColors.danger.withValues(alpha: 0.55)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedStaffCard(Map<String, dynamic> account) {
    final profileId = account['profile_id']?.toString() ?? '';
    final removing = _removingProfileId == profileId;
    final email = account['email']?.toString().trim() ?? 'No email available';
    final fieldSummary = _linkedFieldSummary(account);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: CorviaColors.success.withValues(alpha: 0.12),
            child: Icon(
              Icons.badge_rounded,
              color: CorviaColors.success,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _accountName(account),
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$email • ${_linkedRoles(account)}',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 13,
                  ),
                ),
                if (fieldSummary.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    fieldSummary,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _removingProfileId == null
                ? () => _confirmRemoveStaff(account)
                : null,
            icon: removing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_remove_alt_1_rounded),
            label: Text(removing ? 'Removing...' : 'Remove'),
            style: OutlinedButton.styleFrom(
              foregroundColor: CorviaColors.danger,
              side: BorderSide(
                color: CorviaColors.danger.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleForm() {
    final account = _selectedAccount!;
    final needsClinicalDetails = _selectedRole == _StaffRole.doctor ||
        _selectedRole == _StaffRole.specialist;
    final needsLicense =
        needsClinicalDetails || _selectedRole == _StaffRole.pharmacist;
    final needsEmployeeNumber = _selectedRole == _StaffRole.nurse ||
        _selectedRole == _StaffRole.pharmacist ||
        _selectedRole == _StaffRole.reception;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cBgPrimary,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: context.cDivider),
          ),
          child: Text(
            '${_accountName(account)} • ${account['email'] ?? 'No email available'}',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Staff role',
          style: TextStyle(
            color: context.cTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: _StaffRole.values.map((role) {
            return ChoiceChip(
              selected: _selectedRole == role,
              avatar: Icon(role.icon, size: 18),
              label: Text(role.label),
              onSelected: (_) {
                setState(() {
                  _selectedRole = role;
                  _clearProfessionalFields();
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = <Widget>[
              if (needsClinicalDetails)
                TextField(
                  controller: _specializationController,
                  decoration: InputDecoration(
                    labelText: _selectedRole == _StaffRole.specialist
                        ? 'Specialist field *'
                        : 'Specialization *',
                    hintText: _selectedRole == _StaffRole.specialist
                        ? 'e.g. Cardiology'
                        : 'e.g. General Practice',
                  ),
                ),
              if (needsLicense)
                TextField(
                  controller: _licenseController,
                  decoration: const InputDecoration(
                    labelText: 'Professional licence number',
                  ),
                ),
              if (needsEmployeeNumber)
                TextField(
                  controller: _employeeNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Employee number',
                  ),
                ),
              if (_selectedRole == _StaffRole.pharmacist)
                TextField(
                  controller: _pharmacyNameController,
                  decoration: const InputDecoration(
                    labelText: 'Pharmacy name',
                  ),
                ),
              if (_selectedRole != _StaffRole.labAdmin)
                DropdownButtonFormField<String>(
                  initialValue: _selectedDepartmentId,
                  decoration: const InputDecoration(
                    labelText: 'Department (optional)',
                  ),
                  items: _departments.map((department) {
                    return DropdownMenuItem<String>(
                      value: department['id']?.toString(),
                      child: Text(
                        department['name']?.toString() ?? 'Department',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedDepartmentId = value);
                  },
                ),
            ];

            if (constraints.maxWidth < 700) {
              return Column(
                children: [
                  for (final field in fields) ...[
                    field,
                    const SizedBox(height: 13),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: fields
                  .map(
                    (field) => SizedBox(
                      width: (constraints.maxWidth - 14) / 2,
                      child: field,
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _linkAccount,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link_rounded),
            label: Text(
              _saving ? 'Linking account...' : 'Link as ${_selectedRole.label}',
            ),
          ),
        ),
      ],
    );
  }
}
