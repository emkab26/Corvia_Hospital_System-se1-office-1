import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/corvia_payment_monitor.dart';

class HospitalBillingPage extends StatefulWidget {
  const HospitalBillingPage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<HospitalBillingPage> createState() => _HospitalBillingPageState();
}

class _HospitalBillingPageState extends State<HospitalBillingPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  Color get primary => context.cAccentReadable;
  Color get accent => CorviaColors.accent;
  Color get success => CorviaColors.success;
  Color get warning => CorviaColors.warning;
  Color get error => CorviaColors.danger;
  Color get background => context.cBgPrimary;
  Color get textDark => context.cTextPrimary;
  Color get mutedText => context.cTextMuted;

  bool _loading = true;
  String? _error;

  String? _hospitalId;
  String _hospitalName = 'Hospital Billing';
  String _selectedFilter = 'All';
  int _paymentRefreshVersion = 0;

  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _medicalAidProviders = [];
  List<Map<String, dynamic>> _payfastTotals = [];

  final Map<String, Map<String, dynamic>> _profilesByKey = {};

  @override
  void initState() {
    super.initState();
    _loadBillingPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBillingPage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await _loadHospitalContext();
      await _loadPatients();
      await _loadProfiles();
      await _loadSubscriptions();
      await _loadPayFastTotals();
      await _loadAppointments();
      await _loadMedicalAidProviders();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _paymentRefreshVersion++;
        });
      }
    }
  }

  Future<void> _loadHospitalContext() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You are not signed in.');
    }

    final adminLink = await _supabase
        .from('hospital_admins')
        .select('hospital_id, hospitals(name)')
        .eq('profile_id', user.id)
        .maybeSingle();

    if (adminLink == null) {
      throw Exception('This account is not linked to a hospital admin record.');
    }

    final hospitalId = adminLink['hospital_id']?.toString();

    if (hospitalId == null || hospitalId.trim().isEmpty) {
      throw Exception('No hospital is linked to this admin account.');
    }

    String hospitalName = 'Hospital Billing';
    final hospital = adminLink['hospitals'];

    if (hospital is Map && hospital['name'] != null) {
      hospitalName = hospital['name'].toString();
    }

    _hospitalId = hospitalId;
    _hospitalName = hospitalName;
  }

  Future<void> _loadPatients() async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) {
      throw Exception('Hospital ID could not be found.');
    }

    final rows = await _supabase
        .from('patients')
        .select()
        .eq('hospital_id', hospitalId)
        .limit(500);

    _patients = _mapRows(rows);
  }

  Future<void> _loadProfiles() async {
    _profilesByKey.clear();

    final keys = <String>{};

    for (final patient in _patients) {
      final profileId = patient['profile_id']?.toString();
      final userId = patient['user_id']?.toString();

      if (profileId != null && profileId.isNotEmpty) {
        keys.add(profileId);
      }

      if (userId != null && userId.isNotEmpty) {
        keys.add(userId);
      }
    }

    if (keys.isEmpty) return;

    final keyList = keys.toList();

    await _loadProfilesByColumn('id', keyList);
    await _loadProfilesByColumn('user_id', keyList);
  }

  Future<void> _loadProfilesByColumn(String column, List<String> keys) async {
    try {
      final rows = await _supabase
          .from('profiles')
          .select(
            'id, user_id, first_name, surname, email, phone, phone_number, id_number',
          )
          .inFilter(column, keys);

      for (final row in rows.whereType<Map>()) {
        final profile = Map<String, dynamic>.from(row);

        final id = profile['id']?.toString();
        final userId = profile['user_id']?.toString();

        if (id != null && id.isNotEmpty) {
          _profilesByKey[id] = profile;
        }

        if (userId != null && userId.isNotEmpty) {
          _profilesByKey[userId] = profile;
        }
      }
    } catch (_) {
      // Billing still works if profile access is restricted.
    }
  }

  Future<void> _loadSubscriptions() async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) return;

    List<Map<String, dynamic>> rows = [];

    try {
      final data = await _supabase
          .from('subscriptions')
          .select()
          .eq('hospital_id', hospitalId)
          .limit(500);

      rows = _mapRows(data);
    } catch (_) {
      try {
        final data = await _supabase.from('subscriptions').select().limit(500);
        rows = _mapRows(data);
      } catch (_) {
        rows = [];
      }
    }

    final hospitalPatientIds = _patients
        .map((patient) => patient['id']?.toString())
        .whereType<String>()
        .toSet();

    final hospitalProfileKeys = <String>{};

    for (final patient in _patients) {
      final profileId = patient['profile_id']?.toString();
      final userId = patient['user_id']?.toString();

      if (profileId != null && profileId.isNotEmpty) {
        hospitalProfileKeys.add(profileId);
      }

      if (userId != null && userId.isNotEmpty) {
        hospitalProfileKeys.add(userId);
      }
    }

    _subscriptions = rows.where((subscription) {
      final directHospitalId = subscription['hospital_id']?.toString();

      if (directHospitalId == hospitalId) return true;

      final patientId = subscription['patient_id']?.toString();
      final profileId = subscription['profile_id']?.toString();
      final userId = subscription['user_id']?.toString();

      return hospitalPatientIds.contains(patientId) ||
          hospitalProfileKeys.contains(profileId) ||
          hospitalProfileKeys.contains(userId);
    }).toList();
  }

  Future<void> _loadPayFastTotals() async {
    final hospitalId = _hospitalId;
    if (hospitalId == null) return;

    try {
      final rows = await _supabase.rpc(
        'corvia_hospital_payment_totals',
        params: {'p_hospital_id': hospitalId},
      );
      _payfastTotals = _mapRows(rows);
    } on PostgrestException catch (error) {
      if (error.code != '42883' && error.code != 'PGRST202') rethrow;
      _payfastTotals = [];
    }
  }

  Future<void> _loadAppointments() async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) return;

    try {
      final rows = await _supabase
          .from('appointments')
          .select()
          .eq('hospital_id', hospitalId)
          .limit(500);

      _appointments = _mapRows(rows);
    } catch (_) {
      _appointments = [];
    }
  }

  Future<void> _loadMedicalAidProviders() async {
    try {
      final rows = await _supabase
          .from('medical_aid_providers')
          .select()
          .order('name', ascending: true)
          .limit(500);

      _medicalAidProviders = _mapRows(rows);
    } catch (_) {
      _medicalAidProviders = [];
    }
  }

  List<Map<String, dynamic>> _mapRows(dynamic rows) {
    if (rows is! List) return [];

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Map<String, dynamic>? _profileForPatient(Map<String, dynamic>? patient) {
    if (patient == null) return null;

    final profileId = patient['profile_id']?.toString();
    final userId = patient['user_id']?.toString();

    if (profileId != null && _profilesByKey.containsKey(profileId)) {
      return _profilesByKey[profileId];
    }

    if (userId != null && _profilesByKey.containsKey(userId)) {
      return _profilesByKey[userId];
    }

    return null;
  }

  Map<String, dynamic>? _patientForSubscription(
    Map<String, dynamic> subscription,
  ) {
    final patientId = subscription['patient_id']?.toString();
    final profileId = subscription['profile_id']?.toString();
    final userId = subscription['user_id']?.toString();

    for (final patient in _patients) {
      if (patientId != null && patient['id']?.toString() == patientId) {
        return patient;
      }

      if (profileId != null && patient['profile_id']?.toString() == profileId) {
        return patient;
      }

      if (userId != null && patient['user_id']?.toString() == userId) {
        return patient;
      }
    }

    return null;
  }

  String _patientName(Map<String, dynamic>? patient) {
    if (patient == null) return 'Unknown patient';

    final directName =
        patient['full_name'] ?? patient['patient_name'] ?? patient['name'];

    if (directName != null && directName.toString().trim().isNotEmpty) {
      return directName.toString();
    }

    final profile = _profileForPatient(patient);

    final firstName = patient['first_name'] ?? profile?['first_name'] ?? '';
    final surname =
        patient['surname'] ?? patient['last_name'] ?? profile?['surname'] ?? '';

    final fullName = '$firstName $surname'.trim();

    if (fullName.isNotEmpty) {
      return fullName;
    }

    return 'Corvia Patient';
  }

  String _patientPhone(Map<String, dynamic>? patient) {
    if (patient == null) return 'No phone number';

    final profile = _profileForPatient(patient);

    final phone = patient['phone'] ??
        patient['phone_number'] ??
        profile?['phone'] ??
        profile?['phone_number'];

    if (phone != null && phone.toString().trim().isNotEmpty) {
      return phone.toString();
    }

    return 'No phone number';
  }

  String _normaliseStatus(dynamic value) {
    final raw = value?.toString() ?? 'pending';

    final status =
        raw.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

    if (status.contains('active')) return 'active';
    if (status.contains('overdue')) return 'overdue';
    if (status.contains('cancel')) return 'cancelled';
    if (status.contains('expire')) return 'expired';
    if (status.contains('inactive')) return 'inactive';
    if (status.contains('paid')) return 'paid';
    if (status.contains('pending')) return 'pending';

    return 'pending';
  }

  String _subscriptionStatus(Map<String, dynamic> subscription) {
    return _normaliseStatus(
      subscription['status'] ??
          subscription['subscription_status'] ??
          subscription['payment_status'],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'paid':
        return 'Paid';
      case 'pending':
        return 'Pending';
      case 'overdue':
        return 'Overdue';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
      case 'inactive':
        return 'Inactive';
      default:
        return 'Pending';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
      case 'paid':
        return success;
      case 'pending':
        return warning;
      case 'overdue':
      case 'cancelled':
      case 'expired':
        return error;
      case 'inactive':
        return mutedText;
      default:
        return accent;
    }
  }

  String _planName(Map<String, dynamic> subscription) {
    final value = subscription['plan_name'] ??
        subscription['plan'] ??
        subscription['subscription_plan'] ??
        subscription['tier'] ??
        subscription['type'];

    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }

    return 'Medical billing plan';
  }

  double _amount(Map<String, dynamic> subscription) {
    final value = subscription['amount'] ??
        subscription['price'] ??
        subscription['monthly_amount'] ??
        subscription['subscription_amount'] ??
        subscription['plan_price'] ??
        subscription['total_amount'];

    if (value == null) return 0;

    if (value is num) return value.toDouble();

    final clean = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');

    return double.tryParse(clean) ?? 0;
  }

  String _formatCurrency(num amount) {
    return 'R${amount.toStringAsFixed(2)}';
  }

  String _billingCycle(Map<String, dynamic> subscription) {
    final value = subscription['billing_cycle'] ??
        subscription['cycle'] ??
        subscription['payment_cycle'] ??
        'monthly';

    return value.toString();
  }

  String _medicalAidProviderName(dynamic providerId) {
    if (providerId == null) return 'No medical aid linked';

    for (final provider in _medicalAidProviders) {
      if (provider['id']?.toString() == providerId.toString()) {
        return provider['name']?.toString() ??
            provider['provider_name']?.toString() ??
            'Medical aid linked';
      }
    }

    return 'Medical aid linked';
  }

  String _medicalAidForPatient(Map<String, dynamic>? patient) {
    if (patient == null) return 'No medical aid linked';

    final directName = patient['medical_aid_provider_name'] ??
        patient['medical_aid_name'] ??
        patient['medical_aid'];

    if (directName != null && directName.toString().trim().isNotEmpty) {
      return directName.toString();
    }

    final providerId =
        patient['medical_aid_provider_id'] ?? patient['medical_aid_id'];

    return _medicalAidProviderName(providerId);
  }

  String _memberNumber(Map<String, dynamic>? patient) {
    if (patient == null) return 'No member number';

    final value = patient['medical_aid_member_number'] ??
        patient['member_number'] ??
        patient['medical_aid_number'] ??
        patient['policy_number'];

    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }

    return 'No member number';
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'No date captured';

    final date = DateTime.tryParse(value.toString());

    if (date == null) return value.toString();

    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');

    return '$day/$month/${local.year}';
  }

  String _nextBillingDate(Map<String, dynamic> subscription) {
    final value = subscription['next_billing_date'] ??
        subscription['next_payment_date'] ??
        subscription['renewal_date'] ??
        subscription['expires_at'] ??
        subscription['end_date'];

    return _formatDate(value);
  }

  int _appointmentCountForPatient(dynamic patientId) {
    if (patientId == null) return 0;

    return _appointments.where((appointment) {
      return appointment['patient_id']?.toString() == patientId.toString();
    }).length;
  }

  double get _monthlyRevenue {
    double total = 0;

    for (final subscription in _subscriptions) {
      final status = _subscriptionStatus(subscription);

      if (status == 'active' || status == 'paid') {
        total += _amount(subscription);
      }
    }

    return total;
  }

  int get _activeBillingCount {
    return _subscriptions.where((subscription) {
      final status = _subscriptionStatus(subscription);
      return status == 'active' || status == 'paid';
    }).length;
  }

  int get _attentionCount {
    return _subscriptions.where((subscription) {
      final status = _subscriptionStatus(subscription);
      return status == 'pending' || status == 'overdue' || status == 'expired';
    }).length;
  }

  int get _medicalAidReadyCount {
    return _patients.where((patient) {
      return _medicalAidForPatient(patient) != 'No medical aid linked';
    }).length;
  }

  List<Map<String, dynamic>> get _visibleSubscriptions {
    final search = _searchController.text.trim().toLowerCase();

    return _subscriptions.where((subscription) {
      final patient = _patientForSubscription(subscription);
      final patientName = _patientName(patient).toLowerCase();
      final patientPhone = _patientPhone(patient).toLowerCase();
      final plan = _planName(subscription).toLowerCase();
      final status = _subscriptionStatus(subscription);
      final medicalAid = _medicalAidForPatient(patient).toLowerCase();
      final memberNumber = _memberNumber(patient).toLowerCase();

      final matchesSearch = search.isEmpty ||
          patientName.contains(search) ||
          patientPhone.contains(search) ||
          plan.contains(search) ||
          medicalAid.contains(search) ||
          memberNumber.contains(search);

      bool matchesFilter = true;

      if (_selectedFilter == 'Active') {
        matchesFilter = status == 'active' || status == 'paid';
      } else if (_selectedFilter == 'Pending') {
        matchesFilter = status == 'pending';
      } else if (_selectedFilter == 'Overdue') {
        matchesFilter = status == 'overdue' || status == 'expired';
      } else if (_selectedFilter == 'Cancelled') {
        matchesFilter = status == 'cancelled' || status == 'inactive';
      } else if (_selectedFilter == 'Medical Aid Ready') {
        matchesFilter =
            _medicalAidForPatient(patient) != 'No medical aid linked';
      }

      return matchesSearch && matchesFilter;
    }).toList();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? error : primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showBillingEditor(Map<String, dynamic> subscription) async {
    final subscriptionId = subscription['id']?.toString();

    if (subscriptionId == null || subscriptionId.isEmpty) {
      _showSnack('This billing record has no valid ID.', isError: true);
      return;
    }

    String selectedStatus = _subscriptionStatus(subscription);

    final amountController = TextEditingController(
      text: _amount(subscription).toStringAsFixed(2),
    );

    final notesController = TextEditingController(
      text: subscription['notes']?.toString() ??
          subscription['billing_notes']?.toString() ??
          '',
    );

    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage Billing Record',
                        style: TextStyle(
                          color: textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_patientName(_patientForSubscription(subscription))} • ${_planName(subscription)}',
                        style: TextStyle(color: mutedText, fontSize: 13),
                      ),
                      const SizedBox(height: 22),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Billing status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(value: 'paid', child: Text('Paid')),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pending'),
                          ),
                          DropdownMenuItem(
                            value: 'overdue',
                            child: Text('Overdue'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelled'),
                          ),
                          DropdownMenuItem(
                            value: 'expired',
                            child: Text('Expired'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;

                                setModalState(() {
                                  selectedStatus = value;
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: amountController,
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: 'R ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        enabled: !saving,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Billing notes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  setModalState(() {
                                    saving = true;
                                  });

                                  try {
                                    final update = <String, dynamic>{};

                                    if (subscription.containsKey('status')) {
                                      update['status'] = selectedStatus;
                                    }

                                    if (subscription.containsKey(
                                      'subscription_status',
                                    )) {
                                      update['subscription_status'] =
                                          selectedStatus;
                                    }

                                    if (subscription.containsKey(
                                      'payment_status',
                                    )) {
                                      update['payment_status'] = selectedStatus;
                                    }

                                    final amount = double.tryParse(
                                      amountController.text.trim().replaceAll(
                                            ',',
                                            '.',
                                          ),
                                    );

                                    if (amount != null) {
                                      if (subscription.containsKey('amount')) {
                                        update['amount'] = amount;
                                      }

                                      if (subscription.containsKey('price')) {
                                        update['price'] = amount;
                                      }

                                      if (subscription.containsKey(
                                        'monthly_amount',
                                      )) {
                                        update['monthly_amount'] = amount;
                                      }

                                      if (subscription.containsKey(
                                        'subscription_amount',
                                      )) {
                                        update['subscription_amount'] = amount;
                                      }
                                    }

                                    if (subscription.containsKey('notes')) {
                                      update['notes'] =
                                          notesController.text.trim().isEmpty
                                              ? null
                                              : notesController.text.trim();
                                    }

                                    if (subscription.containsKey(
                                      'billing_notes',
                                    )) {
                                      update['billing_notes'] =
                                          notesController.text.trim().isEmpty
                                              ? null
                                              : notesController.text.trim();
                                    }

                                    if (subscription.containsKey(
                                      'updated_at',
                                    )) {
                                      update['updated_at'] = DateTime.now()
                                          .toUtc()
                                          .toIso8601String();
                                    }

                                    if (update.isEmpty) {
                                      throw Exception(
                                        'No supported billing columns found to update.',
                                      );
                                    }

                                    await _supabase
                                        .from('subscriptions')
                                        .update(update)
                                        .eq('id', subscriptionId);

                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    await _loadBillingPage();

                                    _showSnack(
                                      'Billing record updated successfully.',
                                    );
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setModalState(() {
                                        saving = false;
                                      });
                                    }

                                    _showSnack(
                                      'Could not update billing record: $e',
                                      isError: true,
                                    );
                                  }
                                },
                          icon: saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.save_rounded),
                          label: Text(
                            saving ? 'Saving...' : 'Save billing changes',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
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

    amountController.dispose();
    notesController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subscriptions = _visibleSubscriptions;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _loadBillingPage,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: accent))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 22),
                      if (_error != null) _buildErrorBox(),
                      if (_hospitalId != null) ...[
                        CorviaPaymentMonitor(
                          hospitalId: _hospitalId,
                          staff: true,
                          refreshVersion: _paymentRefreshVersion,
                        ),
                        const SizedBox(height: 22),
                        if (_payfastTotals.isNotEmpty) ...[
                          _buildPayFastTotals(),
                          const SizedBox(height: 22),
                        ],
                      ],
                      _buildStats(),
                      const SizedBox(height: 22),
                      _buildBillingDirectory(subscriptions),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to hospital dashboard',
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded),
          color: primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Billing • $_hospitalName',
                style: TextStyle(
                  color: textDark,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Track subscriptions, medical aid information, billing status and monthly revenue.',
                style: TextStyle(color: mutedText, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _loadBillingPage,
          icon: Icon(Icons.refresh_rounded),
          label: Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ],
    );
  }

  Widget _buildPayFastTotals() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirmed PayFast totals',
            style: TextStyle(
              color: textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Live and sandbox are reported separately. Pending payments are not included in confirmed revenue.',
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: _payfastTotals.map((row) {
              final cents = row['confirmed_amount_cents'];
              final amount = cents is num
                  ? cents.toDouble() / 100
                  : (num.tryParse(cents?.toString() ?? '') ?? 0) / 100;
              return Semantics(
                label:
                    '${row['environment']} PayFast: ${row['confirmed_payments']} confirmed, ${_formatCurrency(amount)}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['environment']?.toString().toUpperCase() ?? 'UNKNOWN',
                      style: TextStyle(
                        color: primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _formatCurrency(amount),
                      style: TextStyle(
                        color: textDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${row['confirmed_payments'] ?? 0} confirmed • '
                      '${row['pending_payments'] ?? 0} pending • '
                      '${row['review_required'] ?? 0} review',
                      style: TextStyle(color: mutedText, fontSize: 12),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: error.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not load all billing information. $_error',
              style: TextStyle(color: textDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final stats = [
      _BillingStat(
        title: 'Monthly Revenue',
        value: _formatCurrency(_monthlyRevenue),
        subtitle: 'Active or paid billing',
        icon: Icons.payments_rounded,
        color: success,
      ),
      _BillingStat(
        title: 'Active Billing',
        value: _activeBillingCount.toString(),
        subtitle: 'Active/paid subscriptions',
        icon: Icons.verified_rounded,
        color: accent,
      ),
      _BillingStat(
        title: 'Needs Attention',
        value: _attentionCount.toString(),
        subtitle: 'Pending, overdue or expired',
        icon: Icons.warning_amber_rounded,
        color: warning,
      ),
      _BillingStat(
        title: 'Medical Aid Ready',
        value: _medicalAidReadyCount.toString(),
        subtitle: 'Patients with medical aid linked',
        icon: Icons.health_and_safety_rounded,
        color: primary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        return GridView.builder(
          itemCount: stats.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 2,
            mainAxisExtent: 205,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            final stat = stats[index];

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.cDivider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: stat.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(stat.icon, color: stat.color),
                  ),
                  const Spacer(),
                  Text(
                    stat.value,
                    style: TextStyle(
                      color: textDark,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    stat.title,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    stat.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedText, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBillingDirectory(List<Map<String, dynamic>> subscriptions) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: accent),
              SizedBox(width: 10),
              Text(
                'Hospital Billing Directory',
                style: TextStyle(
                  color: primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${subscriptions.length} billing record(s) currently shown',
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'Search patient, phone, plan, medical aid or member number',
              prefixIcon: Icon(Icons.search_rounded, color: accent),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: Icon(Icons.clear_rounded),
                    ),
              filled: true,
              fillColor: context.cBgPrimary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'All',
              'Active',
              'Pending',
              'Overdue',
              'Cancelled',
              'Medical Aid Ready',
            ].map((filter) {
              return ChoiceChip(
                label: Text(filter),
                selected: _selectedFilter == filter,
                selectedColor: accent.withValues(alpha: 0.13),
                onSelected: (_) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          if (subscriptions.isEmpty)
            _buildEmptyState()
          else
            ...subscriptions.map(_buildBillingCard),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, color: accent, size: 42),
          SizedBox(height: 12),
          Text(
            'No billing records found',
            style: TextStyle(
              color: primary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Patient subscriptions and billing records will appear here once linked.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingCard(Map<String, dynamic> subscription) {
    final patient = _patientForSubscription(subscription);
    final patientName = _patientName(patient);
    final patientPhone = _patientPhone(patient);
    final status = _subscriptionStatus(subscription);
    final statusColor = _statusColor(status);
    final amount = _amount(subscription);
    final medicalAid = _medicalAidForPatient(patient);
    final memberNumber = _memberNumber(patient);
    final appointmentCount = _appointmentCountForPatient(patient?['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                patientName,
                style: TextStyle(
                  color: textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                patientPhone,
                style: TextStyle(color: mutedText, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BillingPill(
                    icon: Icons.workspace_premium_rounded,
                    label: _planName(subscription),
                    color: accent,
                  ),
                  _BillingPill(
                    icon: Icons.payments_rounded,
                    label: _formatCurrency(amount),
                    color: success,
                  ),
                  _BillingPill(
                    icon: Icons.repeat_rounded,
                    label: _billingCycle(subscription),
                    color: primary,
                  ),
                  _BillingPill(
                    icon: Icons.event_rounded,
                    label: 'Next: ${_nextBillingDate(subscription)}',
                    color: warning,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Medical aid: $medicalAid',
                style: TextStyle(
                  color: textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Member number: $memberNumber • Appointments: $appointmentCount',
                style: TextStyle(color: mutedText, fontSize: 12),
              ),
            ],
          );

          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _BillingPill(
                icon: Icons.circle,
                label: _statusLabel(status),
                color: statusColor,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showBillingEditor(subscription),
                icon: Icon(Icons.edit_rounded, size: 18),
                label: Text('Manage'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 14),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.receipt_long_rounded, color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(child: details),
              const SizedBox(width: 14),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _BillingStat {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _BillingStat({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _BillingPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _BillingPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
