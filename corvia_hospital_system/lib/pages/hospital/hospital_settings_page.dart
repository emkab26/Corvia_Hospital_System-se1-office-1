import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

class HospitalSettingsPage extends StatefulWidget {
  const HospitalSettingsPage({super.key});

  @override
  State<HospitalSettingsPage> createState() => _HospitalSettingsPageState();
}

class _HospitalSettingsPageState extends State<HospitalSettingsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SettingsService _settings = SettingsService.instance;

  bool _loading = true;
  String? _loadError;

  String? _hospitalId;
  String _hospitalName = 'Hospital Settings';

  Map<String, dynamic> _hospital = {};
  Map<String, dynamic> _adminProfile = {};

  late double _textScaleDraft;

  @override
  void initState() {
    super.initState();
    _textScaleDraft = _settings.textScale;
    _settings.addListener(_onSettingsChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;

    setState(() {
      _textScaleDraft = _settings.textScale;
    });
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception('You are not signed in.');
      }

      final adminLink = await _supabase
          .from('hospital_admins')
          .select('hospital_id')
          .eq('profile_id', user.id)
          .maybeSingle();

      if (adminLink == null) {
        throw Exception(
          'This account is not linked to a hospital admin record.',
        );
      }

      final hospitalId = adminLink['hospital_id']?.toString();

      if (hospitalId == null || hospitalId.isEmpty) {
        throw Exception('No hospital is linked to this admin account.');
      }

      final results = await Future.wait([
        _supabase.from('hospitals').select().eq('id', hospitalId).maybeSingle(),
        _loadAdminProfile(user.id),
      ]);

      final hospitalRow = results[0];
      final profileRow = results[1];

      if (hospitalRow == null) {
        throw Exception('Hospital record could not be found.');
      }

      _hospitalId = hospitalId;
      _hospital = Map<String, dynamic>.from(hospitalRow);
      _adminProfile = profileRow ?? {};

      _hospitalName = _hospitalValue(
        ['name', 'hospital_name'],
        fallback: 'Hospital Settings',
      );
    } catch (e) {
      _loadError = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _loadAdminProfile(String userId) async {
    try {
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (profile != null) {
        return Map<String, dynamic>.from(profile);
      }
    } catch (_) {}

    try {
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        return Map<String, dynamic>.from(profile);
      }
    } catch (_) {}

    return null;
  }

  String _profileValue(List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = _adminProfile[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    return fallback;
  }

  String _hospitalValue(List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = _hospital[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    return fallback;
  }

  bool _setFirstExistingField(
    Map<String, dynamic> payload,
    List<String> possibleFields,
    String value,
  ) {
    for (final field in possibleFields) {
      if (_hospital.containsKey(field)) {
        payload[field] = value.trim().isEmpty ? null : value.trim();
        return true;
      }
    }

    return false;
  }

  String get _adminName {
    final firstName = _profileValue(['first_name']);
    final surname = _profileValue(['surname']);
    final fullName = '$firstName $surname'.trim();

    return fullName.isEmpty ? 'Hospital Administrator' : fullName;
  }

  String get _adminEmail {
    final authEmail = _supabase.auth.currentUser?.email;

    if (authEmail != null && authEmail.trim().isNotEmpty) {
      return authEmail;
    }

    return _profileValue(['email'], fallback: 'No email captured');
  }

  String get _adminPhone {
    return _profileValue(
      ['phone', 'phone_number'],
      fallback: 'No phone number captured',
    );
  }

  String get _adminRole {
    return _profileValue(
      ['role', 'user_type'],
      fallback: 'hospital_admin',
    ).replaceAll('_', ' ');
  }

  String get _hospitalAddress {
    final values = [
      _hospitalValue(['address', 'street_address', 'physical_address']),
      _hospitalValue(['city', 'town', 'suburb']),
      _hospitalValue(['province', 'state', 'region']),
      _hospitalValue(['country']),
    ].where((value) => value.isNotEmpty).toList();

    return values.isEmpty ? 'No address captured' : values.join(', ');
  }

  String get _hospitalPhone {
    return _hospitalValue(
      ['phone', 'phone_number', 'contact_number', 'hospital_phone'],
      fallback: 'No hospital phone captured',
    );
  }

  String get _hospitalEmail {
    return _hospitalValue(
      ['email', 'contact_email', 'hospital_email'],
      fallback: 'No hospital email captured',
    );
  }

  String get _hospitalEmergencyPhone {
    return _hospitalValue(
      ['emergency_phone', 'emergency_contact_number', 'emergency_number'],
      fallback: 'No emergency phone captured',
    );
  }

  bool get _adminActive => _adminProfile['is_active'] != false;

  bool get _profileComplete => _adminProfile['profile_complete'] == true;

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? CorviaColors.danger : CorviaColors.accentDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showHospitalNameEditor() async {
    final nameController = TextEditingController(text: _hospitalName);
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
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hospital Name',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This changes the hospital name shown in the dashboard.',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Hospital name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final name = nameController.text.trim();

                                if (name.isEmpty) {
                                  _showSnack(
                                    'Hospital name is required.',
                                    isError: true,
                                  );
                                  return;
                                }

                                setModalState(() {
                                  saving = true;
                                });

                                try {
                                  final payload = <String, dynamic>{};

                                  final changed = _setFirstExistingField(
                                    payload,
                                    ['name', 'hospital_name'],
                                    name,
                                  );

                                  if (!changed) {
                                    throw Exception(
                                      'No hospital name column was found.',
                                    );
                                  }

                                  if (_hospital.containsKey('updated_at')) {
                                    payload['updated_at'] = DateTime.now()
                                        .toUtc()
                                        .toIso8601String();
                                  }

                                  await _supabase
                                      .from('hospitals')
                                      .update(payload)
                                      .eq('id', _hospitalId!);

                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }

                                  await _loadSettings();

                                  _showSnack(
                                    'Hospital name updated successfully.',
                                  );
                                } catch (e) {
                                  if (sheetContext.mounted) {
                                    setModalState(() {
                                      saving = false;
                                    });
                                  }

                                  _showSnack(
                                    'Could not update hospital name: $e',
                                    isError: true,
                                  );
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          saving ? 'Saving...' : 'Save hospital name',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  Future<void> _showAdminProfileEditor() async {
    final firstNameController = TextEditingController(
      text: _profileValue(['first_name']),
    );

    final surnameController = TextEditingController(
      text: _profileValue(['surname']),
    );

    final phoneController = TextEditingController(
      text: _profileValue(['phone', 'phone_number']),
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
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Administrator Profile',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Signed in as $_adminEmail',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: firstNameController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: surnameController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Surname',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: phoneController,
                        enabled: !saving,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 22),
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
                                    final profileId =
                                        _adminProfile['id']?.toString();

                                    final userId =
                                        _supabase.auth.currentUser?.id;

                                    if ((profileId == null ||
                                            profileId.isEmpty) &&
                                        (userId == null || userId.isEmpty)) {
                                      throw Exception(
                                        'Administrator profile record could not be found.',
                                      );
                                    }

                                    final payload = <String, dynamic>{
                                      'first_name':
                                          firstNameController.text.trim(),
                                      'surname': surnameController.text.trim(),
                                    };

                                    if (_adminProfile.containsKey('phone')) {
                                      payload['phone'] =
                                          phoneController.text.trim().isEmpty
                                              ? null
                                              : phoneController.text.trim();
                                    }

                                    if (_adminProfile
                                        .containsKey('phone_number')) {
                                      payload['phone_number'] =
                                          phoneController.text.trim().isEmpty
                                              ? null
                                              : phoneController.text.trim();
                                    }

                                    if (_adminProfile
                                        .containsKey('updated_at')) {
                                      payload['updated_at'] = DateTime.now()
                                          .toUtc()
                                          .toIso8601String();
                                    }

                                    var query = _supabase
                                        .from('profiles')
                                        .update(payload);

                                    if (profileId != null &&
                                        profileId.isNotEmpty) {
                                      await query.eq('id', profileId);
                                    } else {
                                      await query.eq('user_id', userId!);
                                    }

                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    await _loadSettings();

                                    _showSnack(
                                      'Administrator profile updated.',
                                    );
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setModalState(() {
                                        saving = false;
                                      });
                                    }

                                    _showSnack(
                                      'Could not update administrator profile: $e',
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
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            saving ? 'Saving...' : 'Save administrator profile',
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

    firstNameController.dispose();
    surnameController.dispose();
    phoneController.dispose();
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      _showSnack('Could not sign out: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: SafeArea(
        child: RefreshIndicator(
          color: context.cAccentReadable,
          onRefresh: _loadSettings,
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: context.cAccentReadable,
                  ),
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 22),
                      if (_loadError != null) _buildErrorBox(),
                      _buildAppearancePanel(),
                      const SizedBox(height: 22),
                      _buildStatusCards(),
                      const SizedBox(height: 22),
                      _buildHospitalPanel(),
                      const SizedBox(height: 22),
                      _buildAdminPanel(),
                      const SizedBox(height: 22),
                      _buildSecurityPanel(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings • $_hospitalName',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Manage the hospital appearance, account details and administrator access.',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 14,
              ),
            ),
          ],
        );

        final refreshButton = OutlinedButton.icon(
          onPressed: _loadSettings,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.cAccentReadable,
            side: BorderSide(color: context.cDivider),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 14),
              refreshButton,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            refreshButton,
          ],
        );
      },
    );
  }

  Widget _buildErrorBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CorviaColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CorviaColors.danger.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: CorviaColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not load all settings. $_loadError',
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

  Widget _buildAppearancePanel() {
    return _buildPanel(
      title: 'Appearance & Accessibility',
      icon: Icons.palette_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Theme',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick a colour palette in light or dark. Changes apply to the entire Corvia app immediately.',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ...CorviaThemeVariant.values.map(
            (variant) => _ThemePickerRow(
              variant: variant,
              selected: _settings.themeVariant == variant,
              onTap: () {
                _settings.themeVariant = variant;
              },
            ),
          ),
          const SizedBox(height: 18),
          Divider(color: context.cDivider),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.text_increase_rounded,
                color: context.cAccentReadable,
              ),
              const SizedBox(width: 10),
              Text(
                'Text Size',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${_textScaleDraft.toStringAsFixed(1)}×',
                style: TextStyle(
                  color: context.cAccentReadable,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Increase text size for easier reading across the app.',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
            ),
          ),
          Slider(
            value: _textScaleDraft,
            min: 0.9,
            max: 1.5,
            divisions: 6,
            label: '${_textScaleDraft.toStringAsFixed(1)}×',
            onChanged: (value) {
              setState(() {
                _textScaleDraft = double.parse(value.toStringAsFixed(1));
              });
            },
            onChangeEnd: (value) {
              _settings.textScale = double.parse(value.toStringAsFixed(1));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards() {
    final cards = [
      _SettingsStatusCard(
        title: 'Hospital Record',
        value: _hospital.isEmpty ? 'Missing' : 'Connected',
        subtitle: 'Hospital details linked',
        icon: Icons.local_hospital_rounded,
        color: _hospital.isEmpty ? CorviaColors.danger : CorviaColors.success,
      ),
      _SettingsStatusCard(
        title: 'Admin Account',
        value: _adminActive ? 'Active' : 'Inactive',
        subtitle: _adminRole,
        icon: Icons.admin_panel_settings_rounded,
        color: _adminActive ? context.cAccentReadable : CorviaColors.danger,
      ),
      _SettingsStatusCard(
        title: 'Profile Setup',
        value: _profileComplete ? 'Complete' : 'In Progress',
        subtitle: 'Administrator profile status',
        icon: Icons.assignment_turned_in_rounded,
        color: _profileComplete ? CorviaColors.success : CorviaColors.warning,
      ),
      _SettingsStatusCard(
        title: 'Hospital Contact',
        value: _hospitalPhone != 'No hospital phone captured' ||
                _hospitalEmail != 'No hospital email captured'
            ? 'Ready'
            : 'Missing',
        subtitle: 'Phone or email contact',
        icon: Icons.contact_phone_rounded,
        color: _hospitalPhone != 'No hospital phone captured' ||
                _hospitalEmail != 'No hospital email captured'
            ? CorviaColors.success
            : CorviaColors.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 2,
            mainAxisExtent: 165,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.cDivider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: card.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(card.icon, color: card.color),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        card.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHospitalPanel() {
    return _buildPanel(
      title: 'Hospital Settings',
      icon: Icons.local_hospital_rounded,
      action: OutlinedButton.icon(
        onPressed: _showHospitalNameEditor,
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('Edit Name'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.cAccentReadable,
          side: BorderSide(color: context.cDivider),
        ),
      ),
      child: Column(
        children: [
          _buildSettingRow(
            icon: Icons.business_rounded,
            title: 'Hospital name',
            subtitle: _hospitalName,
            color: context.cAccentReadable,
          ),
          _buildSettingRow(
            icon: Icons.location_on_rounded,
            title: 'Hospital address',
            subtitle: _hospitalAddress,
            color: CorviaColors.success,
          ),
          _buildSettingRow(
            icon: Icons.phone_rounded,
            title: 'Hospital phone',
            subtitle: _hospitalPhone,
            color: context.cAccentReadable,
          ),
          _buildSettingRow(
            icon: Icons.email_rounded,
            title: 'Hospital email',
            subtitle: _hospitalEmail,
            color: CorviaColors.success,
          ),
          _buildSettingRow(
            icon: Icons.emergency_rounded,
            title: 'Emergency phone',
            subtitle: _hospitalEmergencyPhone,
            color: CorviaColors.danger,
          ),
        ],
      ),
    );
  }

  Widget _buildAdminPanel() {
    return _buildPanel(
      title: 'Administrator Account',
      icon: Icons.admin_panel_settings_rounded,
      action: OutlinedButton.icon(
        onPressed: _showAdminProfileEditor,
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('Edit Profile'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.cAccentReadable,
          side: BorderSide(color: context.cDivider),
        ),
      ),
      child: Column(
        children: [
          _buildSettingRow(
            icon: Icons.person_rounded,
            title: 'Administrator name',
            subtitle: _adminName,
            color: context.cAccentReadable,
          ),
          _buildSettingRow(
            icon: Icons.badge_rounded,
            title: 'Role',
            subtitle: _adminRole,
            color: context.cAccentReadable,
          ),
          _buildSettingRow(
            icon: Icons.email_rounded,
            title: 'Sign-in email',
            subtitle: _adminEmail,
            color: CorviaColors.success,
          ),
          _buildSettingRow(
            icon: Icons.phone_rounded,
            title: 'Administrator phone',
            subtitle: _adminPhone,
            color: CorviaColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPanel() {
    return _buildPanel(
      title: 'Account Security',
      icon: Icons.security_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingRow(
            icon: Icons.verified_user_rounded,
            title: 'Current session',
            subtitle: _adminActive
                ? 'Administrator account is active.'
                : 'Administrator account is marked inactive.',
            color: _adminActive ? CorviaColors.success : CorviaColors.danger,
          ),
          _buildSettingRow(
            icon: Icons.fingerprint_rounded,
            title: 'Biometric access',
            subtitle:
                'Managed from the Corvia sign-in flow and device settings.',
            color: context.cAccentReadable,
          ),
          _buildSettingRow(
            icon: Icons.lock_reset_rounded,
            title: 'Password and sign-in email',
            subtitle:
                'These should be changed through the authenticated account flow, not the profile table.',
            color: CorviaColors.warning,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out of Hospital Admin'),
              style: OutlinedButton.styleFrom(
                foregroundColor: CorviaColors.danger,
                side: const BorderSide(color: CorviaColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? action,
  }) {
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
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 500;

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          color: context.cAccentReadable,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (action != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: action,
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Icon(
                    icon,
                    color: context.cAccentReadable,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (action != null) action,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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

class _ThemePickerRow extends StatelessWidget {
  const _ThemePickerRow({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final CorviaThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  static const Map<CorviaThemeVariant, (Color, Color)> _variantSwatch = {
    CorviaThemeVariant.modernLight: (
      Color(0xFFF8FAFC),
      Color(0xFF2563EB),
    ),
    CorviaThemeVariant.modernDark: (
      Color(0xFF0B1220),
      Color(0xFF60A5FA),
    ),
    CorviaThemeVariant.premiumLight: (
      Color(0xFFF8FAFC),
      Color(0xFF06B6D4),
    ),
    CorviaThemeVariant.premiumDark: (
      Color(0xFF0F172A),
      Color(0xFF22D3EE),
    ),
    CorviaThemeVariant.tealLight: (
      Color(0xFFF0FDFA),
      Color(0xFF0F766E),
    ),
    CorviaThemeVariant.tealDark: (
      Color(0xFF042F2A),
      Color(0xFF2DD4BF),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (background, accent) = _variantSwatch[variant]!;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: selected
                ? context.cAccentReadable.withValues(alpha: 0.10)
                : context.cBgPrimary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? context.cAccentReadable : context.cDivider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.cDivider),
                ),
                child: Center(
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  variant.label,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? context.cAccentReadable : context.cTextMuted,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsStatusCard {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SettingsStatusCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
