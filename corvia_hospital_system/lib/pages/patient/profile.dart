import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_gate.dart';
import '../../auth/role_choice_page.dart';
import '../../models/profile_update_model.dart';
import '../../services/account_mode_service.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_number_format.dart';
import 'billing.dart';
import 'contact_details_editor.dart';
import 'medical_aid_info.dart';

final ValueNotifier<bool> profilePageHasChangesNotifier =
    ValueNotifier<bool>(false);

final ValueNotifier<bool> profilePageIsSavingNotifier =
    ValueNotifier<bool>(false);

/// Bumped when the patient leaves the Profile tab, so an open contact-details
/// edit is closed instead of waiting there for next time.
final ValueNotifier<int> profileLeaveSignal = ValueNotifier<int>(0);

/// Call before switching away from the Profile tab. Dashboard tabs live in an
/// IndexedStack, so switching is not a route pop and ProfilePage's PopScope
/// never sees it.
///
/// Returns false when the patient chooses to stay. Otherwise any edit in
/// progress is discarded and this returns true.
Future<bool> confirmLeaveProfile(BuildContext context) async {
  if (profilePageIsSavingNotifier.value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Please wait for your contact details to finish saving.'),
      ));
    return false;
  }
  if (profilePageHasChangesNotifier.value &&
      !await showDiscardProfileChangesDialog(context)) {
    return false;
  }

  if (!context.mounted || profilePageIsSavingNotifier.value) return false;

  profilePageHasChangesNotifier.value = false;
  profileLeaveSignal.value++;

  return true;
}

/// Asks whether to throw away unsaved contact-detail changes. True means
/// discard.
Future<bool> showDiscardProfileChangesDialog(BuildContext context) async {
  final choice = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: context.cBgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Unsaved Changes',
          style: TextStyle(
            color: context.cTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'You have unsaved changes. Do you want to discard them?',
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Stay',
              style: TextStyle(
                color: context.cAccentReadable,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Discard',
              style: TextStyle(
                color: CorviaColors.danger,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    },
  );

  return choice == true;
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _profileData;

  bool _loading = true;
  bool _signingOut = false;
  bool _loadFailed = false;
  bool _canSwitchDoctorView = false;

  bool _hasUnsavedChanges = false;
  bool _savingContactDetails = false;

  // Saved contact details, shown and edited by ContactDetailsEditor.
  String _initialAddress = '';
  String _initialPhone = '';

  @override
  void initState() {
    super.initState();

    _loadProfile();
  }

  @override
  void dispose() {
    profilePageHasChangesNotifier.value = false;
    profilePageIsSavingNotifier.value = false;

    super.dispose();
  }

  void _setUnsavedChanges(bool changed) {
    if (changed == _hasUnsavedChanges) {
      return;
    }

    setState(() {
      _hasUnsavedChanges = changed;
    });

    profilePageHasChangesNotifier.value = changed;
  }

  void _setContactSaving(bool saving) {
    setState(() => _savingContactDetails = saving);
    profilePageIsSavingNotifier.value = saving;
  }

  Future<void> _loadProfile() async {
    if (_savingContactDetails) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }

      return;
    }

    try {
      final profileFuture = _supabase
          .from('profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      // Active mode access is authoritative. Doctor rows are retained for
      // audit history after access is removed, so row existence alone must not
      // keep the doctor switch visible.
      final canSwitchDoctorFuture = AccountModeService.current()
          .then(
            (access) => access.isActive && access.canSwitchDoctorPatient,
          )
          .catchError((_) => false);

      var profile = await profileFuture;
      final canSwitchDoctorView = await canSwitchDoctorFuture;

      if (profile == null) {
        await _supabase.from('profiles').insert({
          'user_id': user.id,
          'first_name': user.email?.split('@')[0] ?? 'Unknown',
          'surname': 'User',
          'email': user.email,
          'id_number': 'N/A',
        });

        profile = await _supabase
            .from('profiles')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
      }

      // Some older patient records have the name on `patients` while their
      // linked `profiles` row has empty name fields. Prefer that real record
      // to the generic "Corvia Patient" label without writing to the backend.
      if (profile != null &&
          (profile['first_name']?.toString().trim().isEmpty ?? true)) {
        try {
          final patient = await _supabase
              .from('patients')
              .select('first_name, surname')
              .eq('profile_id', user.id)
              .maybeSingle();
          if (patient != null) {
            final patientFirstName =
                patient['first_name']?.toString().trim() ?? '';
            final patientSurname = patient['surname']?.toString().trim() ?? '';
            profile = {
              ...profile,
              if (patientFirstName.isNotEmpty) 'first_name': patientFirstName,
              if ((profile['surname']?.toString().trim().isEmpty ?? true) &&
                  patientSurname.isNotEmpty)
                'surname': patientSurname,
            };
          }
        } catch (_) {
          // Continue showing the available profile data if patient lookup
          // is not permitted for this session.
        }
      }

      if (!mounted) {
        return;
      }

      final address = profile?['address']?.toString() ?? '';
      final phone = profile?['phone_number']?.toString() ?? '';

      setState(() {
        _profileData = profile;

        _initialAddress = address;
        _initialPhone = formatPhoneNumber(phone);

        _canSwitchDoctorView = canSwitchDoctorView;

        _hasUnsavedChanges = false;

        _loading = false;
      });

      profilePageHasChangesNotifier.value = false;
    } catch (error) {
      debugPrint(
        'Error loading profile: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _navigateToAuthGate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      try {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => const AuthGate(),
          ),
          (route) => false,
        );
      } catch (error) {
        debugPrint(
          'Navigation to AuthGate failed: $error',
        );
      }
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: context.cBgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Sign out',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out of Corvia?',
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: Text(
                'Sign out',
                style: TextStyle(
                  color: CorviaColors.danger,
                  fontWeight: FontWeight.w800,
                ),
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
      _signingOut = true;
    });

    try {
      await SupabaseService.signOut();

      if (mounted) {
        _navigateToAuthGate();
      }
    } catch (error) {
      debugPrint(
        'Sign-out error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _signingOut = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not sign out. Please try again.',
            ),
          ),
        );
    }
  }

  Future<bool> _saveContactDetails(String address, String phone) async {
    if (_supabase.auth.currentUser == null) {
      return false;
    }

    try {
      final result = await const ProfileService().updateProfile(
        ProfileUpdateModel(
          address: address,
          phoneNumber: phone,
        ),
      );

      if (!mounted) {
        return false;
      }

      if (!result.isSuccess) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'Could not update profile.',
              ),
            ),
          );

        return false;
      }

      setState(() {
        _initialAddress = address;
        _initialPhone = phone;
        _hasUnsavedChanges = false;
      });

      profilePageHasChangesNotifier.value = false;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Profile updated successfully.',
            ),
          ),
        );

      return true;
    } catch (error) {
      debugPrint('Could not update profile: $error');

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Could not update profile.',
              ),
            ),
          );
      }

      return false;
    }
  }

  Future<bool> _showUnsavedDialog() => confirmLeaveProfile(context);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges && !_savingContactDetails,
      onPopInvokedWithResult: (
        didPop,
        result,
      ) async {
        if (didPop) {
          return;
        }

        final shouldPop = await _showUnsavedDialog();

        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.cBgPrimary,
        appBar: widget.showAppBar
            ? AppBar(
                title: const Text(
                  'Profile',
                ),
              )
            : null,
        body: SafeArea(
          top: widget.showAppBar,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _buildLoading();
    }

    if (_loadFailed) {
      return _buildError();
    }

    if (_profileData == null) {
      return _buildNoProfile();
    }

    return _buildContent();
  }

  Widget _buildLoading() {
    return Center(
      child: Container(
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
            CircularProgressIndicator(
              color: context.cAccentReadable,
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              'Loading your profile...',
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoProfile() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 480,
          ),
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
                Icons.person_off_outlined,
                size: 48,
                color: context.cTextSecondary,
              ),
              const SizedBox(
                height: 14,
              ),
              Text(
                'No profile found.',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 6,
              ),
              Text(
                'Corvia could not find a profile linked to your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(
            height: 90,
          ),
          Center(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 500,
              ),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: CorviaColors.warning.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 52,
                    color: CorviaColors.warning,
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Text(
                    "Couldn't load your profile",
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Check your connection and try again.',
                    style: TextStyle(
                      color: context.cTextSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  FilledButton.icon(
                    onPressed: _loadProfile,
                    icon: const Icon(
                      Icons.refresh_rounded,
                    ),
                    label: const Text(
                      'Try Again',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final data = _profileData!;

    final firstName = data['first_name']?.toString().trim() ?? '';
    final surname = data['surname']?.toString().trim() ?? '';

    final name = '$firstName $surname'.trim();

    final email = data['email']?.toString().trim() ?? '';
    final idNumber = data['id_number']?.toString().trim() ?? '';

    final rawDob = data['date_of_birth']?.toString().trim() ?? '';

    final displayIdNumber = idNumber.isEmpty || idNumber.toUpperCase() == 'N/A'
        ? 'Not provided'
        : idNumber;

    final displayDob = rawDob.isEmpty ? 'Not provided' : rawDob;

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final horizontalPadding = constraints.maxWidth >= 900 ? 28.0 : 16.0;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1050,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProfileHeader(
                      name: name,
                      email: email,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _buildPersonalDetails(
                      idNumber: displayIdNumber,
                      dob: displayDob,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _buildAccountLinks(),
                    if (_canSwitchDoctorView) ...[
                      const SizedBox(
                        height: 16,
                      ),
                      _buildDoctorSwitch(),
                    ],
                    const SizedBox(
                      height: 16,
                    ),
                    _buildSignOutCard(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader({
    required String name,
    required String email,
  }) {
    final displayName = name.isEmpty ? 'Name not on file' : name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 30,
        horizontal: 22,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
        ),
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 12,
            offset: const Offset(
              0,
              4,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.cAccentReadable.withValues(
                alpha: 0.12,
              ),
              border: Border.all(
                color: context.cAccentReadable.withValues(
                  alpha: 0.30,
                ),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.person_rounded,
              size: 52,
              color: context.cAccentReadable,
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(
              height: 5,
            ),
            Text(
              email,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(
            height: 14,
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: CorviaColors.success.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(
                999,
              ),
              border: Border.all(
                color: CorviaColors.success.withValues(
                  alpha: 0.24,
                ),
              ),
            ),

            // IMPORTANT:
            // Do not make this Row const because
            // CorviaColors.success is resolved at runtime.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: CorviaColors.success,
                  size: 16,
                ),
                const SizedBox(
                  width: 6,
                ),
                Text(
                  'Corvia Patient Account',
                  style: TextStyle(
                    color: CorviaColors.success,
                    fontSize: 11,
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

  Widget _buildPersonalDetails({
    required String idNumber,
    required String dob,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
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
          _sectionTitle(
            icon: Icons.person_outline_rounded,
            title: 'Personal Details',
            subtitle: 'Your registered patient information',
          ),
          const SizedBox(
            height: 18,
          ),
          _infoRow(
            icon: Icons.badge_outlined,
            label: 'ID Number',
            value: idNumber,
          ),
          _divider(),
          _infoRow(
            icon: Icons.cake_outlined,
            label: 'Date of Birth',
            value: dob,
          ),
          const SizedBox(
            height: 22,
          ),
          Divider(
            color: context.cDivider,
          ),
          const SizedBox(
            height: 16,
          ),
          _sectionTitle(
            icon: Icons.edit_outlined,
            title: 'Contact Details',
            subtitle: 'Update your address and cellphone number',
          ),
          const SizedBox(
            height: 18,
          ),
          ContactDetailsEditor(
            address: _initialAddress,
            phone: _initialPhone,
            onSave: _saveContactDetails,
            onDirtyChanged: _setUnsavedChanges,
            onSavingChanged: _setContactSaving,
            discardSignal: profileLeaveSignal,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountLinks() {
    return Container(
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
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
        children: [
          _navTile(
            icon: Icons.health_and_safety_outlined,
            iconColor: CorviaColors.success,
            title: 'Medical Aid Info',
            subtitle: 'Provider, plan and member details',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const MedicalAidInfoPage(),
                ),
              );
            },
          ),
          Divider(
            color: context.cDivider,
            height: 1,
            indent: 76,
          ),
          _navTile(
            icon: Icons.receipt_long_outlined,
            iconColor: CorviaColors.warning,
            title: 'Billing',
            subtitle: 'Plans, invoices and payment history',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const BillingPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorSwitch() {
    return Container(
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          20,
        ),
        border: Border.all(
          color: context.cAccentReadable.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: context.cAccentReadable,
            side: BorderSide(
              color: context.cAccentReadable,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 15,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                14,
              ),
            ),
          ),
          onPressed: _savingContactDetails
              ? null
              : () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const RoleChoicePage(),
                    ),
                    (route) => false,
                  );
                },
          icon: const Icon(
            Icons.swap_horiz_rounded,
          ),
          label: const Text(
            'Switch to Doctor View',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutCard() {
    return Container(
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: CorviaColors.danger.withValues(
          alpha: 0.055,
        ),
        borderRadius: BorderRadius.circular(
          20,
        ),
        border: Border.all(
          color: CorviaColors.danger.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: CorviaColors.danger.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: CorviaColors.danger,
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
                      'Sign out of Corvia',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      'You will need to sign in again to access your account.',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: CorviaColors.danger,
                side: BorderSide(
                  color: CorviaColors.danger,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                ),
              ),
              onPressed: _signingOut || _savingContactDetails ? null : _signOut,
              icon: _signingOut
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CorviaColors.danger,
                      ),
                    )
                  : const Icon(
                      Icons.logout_rounded,
                    ),
              label: Text(
                _signingOut ? 'Signing out...' : 'Sign Out',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.cAccentReadable.withValues(
              alpha: 0.10,
            ),
            borderRadius: BorderRadius.circular(
              12,
            ),
          ),
          child: Icon(
            icon,
            color: context.cAccentReadable,
            size: 21,
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
                title,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 2,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 19,
            color: context.cAccentReadable,
          ),
          const SizedBox(
            width: 10,
          ),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(
      color: context.cDivider,
      height: 18,
    );
  }

  Widget _navTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          20,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 23,
                ),
              ),
              const SizedBox(
                width: 14,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.cAccentReadable,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
