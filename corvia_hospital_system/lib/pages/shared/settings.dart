import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/biometric_service.dart';
import '../../services/settings_service.dart';
import '../../services/settings_workspace_access_service.dart';
import '../../services/supabase_service.dart';
import '../../services/voice_service.dart';
import '../../config/env.dart';
import '../../theme/app_theme.dart';
import '../dispatch/response_workspace_page.dart';
import '../dispatch/team_completion_page.dart';
import '../blood_bank/blood_bank_page.dart';
import '../paramedic/paramedic_workspace_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.showAppBar = true,
    this.showStaffWorkspaces = false,
    this.showSignOut = false,
    this.workspaceAccessService,
  });

  /// Hidden when embedded in a shell that already provides a header, so a
  /// dashboard tab does not stack two app bars.
  final bool showAppBar;

  /// Enables staff shortcuts on this surface. Each shortcut also requires
  /// verified database access for the signed-in account.
  final bool showStaffWorkspaces;
  final SettingsWorkspaceAccessService? workspaceAccessService;

  /// Shown for staff dashboards whose only other sign-out is in a top bar
  /// or menu that is easy to miss.
  final bool showSignOut;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final _s = SettingsService.instance;
  late SettingsWorkspaceAccessService _workspaceAccessService;
  StreamSubscription<String?>? _workspaceAuthSubscription;
  SettingsWorkspaceAccess _workspaceAccess = const SettingsWorkspaceAccess();
  int _workspaceAccessGeneration = 0;

  late double _textScaleDraft;
  late double _dyslexiaOverlayDraft;

  List<BiometricType> _availableBiometrics = const [];

  /// Null until the running build reports itself, and stays null if it cannot.
  /// The line is there to tell support which build a user is on, so showing
  /// nothing is the only honest fallback - a guessed version is worse than none.
  String? _appVersion;

  // Overlay endpoint colours – must match SettingsService.dyslexiaOverlayColor
  static const _overlayYellow = Color(0xFFFFF9C4);
  static const _overlayAqua = Color(0xFFB2EBF2);

  @override
  void initState() {
    super.initState();
    _textScaleDraft = _s.textScale;
    _dyslexiaOverlayDraft = _s.dyslexiaOverlayValue;
    _s.addListener(_onServiceChanged);
    _loadBiometricCapability();
    _loadAppVersion();
    WidgetsBinding.instance.addObserver(this);
    _watchWorkspaceAccess();
  }

  @override
  void dispose() {
    _workspaceAccessGeneration++;
    _workspaceAuthSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _s.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _watchWorkspaceAccess() {
    _workspaceAccessService =
        widget.workspaceAccessService ?? SettingsWorkspaceAccessService();
    _workspaceAuthSubscription = _workspaceAccessService.users.listen((_) {
      if (mounted) _loadWorkspaceAccess();
    });
    _loadWorkspaceAccess();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceAccessService != widget.workspaceAccessService) {
      _workspaceAuthSubscription?.cancel();
      _watchWorkspaceAccess();
    } else if (oldWidget.showStaffWorkspaces != widget.showStaffWorkspaces) {
      _loadWorkspaceAccess();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadWorkspaceAccess();
  }

  Future<void> _loadWorkspaceAccess() async {
    final generation = ++_workspaceAccessGeneration;
    final actor = _workspaceAccessService.userId;
    setState(() => _workspaceAccess = const SettingsWorkspaceAccess());
    try {
      final access = await _workspaceAccessService.load(
        includeStaff: widget.showStaffWorkspaces,
        includeTeam: Env.ws4TeamEmsHandoffEnabled,
      );
      if (!mounted ||
          generation != _workspaceAccessGeneration ||
          actor != _workspaceAccessService.userId) {
        return;
      }
      setState(() => _workspaceAccess = access);
    } catch (_) {
      // Unverified access stays hidden; ordinary settings remain available.
    }
  }

  Future<void> _openWorkspace(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _loadWorkspaceAccess();
  }

  void _onServiceChanged() {
    setState(() {
      _textScaleDraft = _s.textScale;
      _dyslexiaOverlayDraft = _s.dyslexiaOverlayValue;
    });
  }

  Future<void> _loadBiometricCapability() async {
    final types = await BiometricService.availableTypes();
    if (!mounted) return;
    setState(() => _availableBiometrics = types);
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(
          () => _appVersion = 'Version ${info.version} (${info.buildNumber})');
    } catch (e) {
      debugPrint('Failed to read package info: $e');
    }
  }

  bool get _faceAvailable =>
      _availableBiometrics.contains(BiometricType.face) ||
      _availableBiometrics.contains(BiometricType.strong);

  bool get _fingerprintAvailable =>
      _availableBiometrics.contains(BiometricType.fingerprint) ||
      _availableBiometrics.contains(BiometricType.strong);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('Settings')) : null,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: context.cBgGradient),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_workspaceAccess.emergencyResponse)
                ListTile(
                  leading: const Icon(Icons.emergency),
                  title: const Text('Emergency response workspace'),
                  subtitle: const Text(
                      'For authorised dispatch, crew and receiving staff'),
                  onTap: () => _openWorkspace(const ResponseWorkspacePage()),
                ),
              if (Env.ws4TeamEmsHandoffEnabled) ...[
                if (_workspaceAccess.backupResponses)
                  ListTile(
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('My backup responses'),
                    onTap: () => _openWorkspace(const Ws4BackupPage()),
                  ),
                if (_workspaceAccess.receivingHandovers)
                  ListTile(
                    leading: const Icon(Icons.how_to_reg_outlined),
                    title: const Text('Receiving handovers'),
                    onTap: () => _openWorkspace(const Ws4ReceivingInboxPage()),
                  ),
              ],
              // Appearance & Accessibility section
              _sectionTitle(context, 'Appearance & Accessibility'),
              _card(context, children: [
                // Theme picker
                _row(context, Icons.color_lens, 'Theme',
                    subtitle: 'Pick a colour palette in light or dark.'),
                const SizedBox(height: 8),
                _themePicker(context),
                const SizedBox(height: 16),

                // Text size
                _row(context, Icons.text_increase, 'Text Size'),
                Slider(
                  value: _textScaleDraft,
                  min: 0.9,
                  max: 1.5,
                  divisions: 6,
                  label: '${_textScaleDraft.toStringAsFixed(1)}×',
                  onChanged: (v) => setState(() =>
                      _textScaleDraft = double.parse(v.toStringAsFixed(1))),
                  onChangeEnd: (v) =>
                      _s.textScale = double.parse(v.toStringAsFixed(1)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('${_textScaleDraft.toStringAsFixed(1)}×',
                      style: TextStyle(color: context.cTextSecondary)),
                ),

                _divider(context),

                // Reading Tools collapsible section
                // Wrap in Theme to suppress dividers and sit flush inside the card.
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: Icon(
                      Icons.menu_book_outlined,
                      color: context.cAccentReadable,
                      size: 22,
                    ),
                    title: Text(
                      'Reading Tools',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Screen tint, font, spacing and more',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    iconColor: context.cAccentReadable,
                    collapsedIconColor: context.cTextSecondary,
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    childrenPadding: EdgeInsets.zero,
                    children: [
                      _divider(context),

                      // 1. Screen tint overlay
                      _switch(context,
                          title: 'Screen tint overlay',
                          subtitle:
                              'Adds a soft colour wash to reduce contrast '
                              'glare and visual stress.',
                          value: _s.dyslexiaOverlayEnabled,
                          onChanged: (v) =>
                              setState(() => _s.dyslexiaOverlayEnabled = v)),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        child: _s.dyslexiaOverlayEnabled
                            ? _overlayHueSlider(context)
                            : const SizedBox.shrink(),
                      ),

                      _divider(context),

                      // 2. Wider letter & word spacing
                      _switch(context,
                          title: 'Wider letter & word spacing',
                          subtitle: 'Spreads characters further apart to help '
                              'prevent letters from appearing to swap or merge.',
                          value: _s.dyslexiaSpacingEnabled,
                          onChanged: (v) =>
                              setState(() => _s.dyslexiaSpacingEnabled = v)),

                      _divider(context),

                      // 3. Verdana font
                      _switch(context,
                          title: 'Verdana reading font',
                          subtitle: 'Switches to Verdana — designed for screen '
                              'readability with wide, distinct letters.',
                          value: _s.dyslexiaVerdanaEnabled,
                          onChanged: (v) =>
                              setState(() => _s.dyslexiaVerdanaEnabled = v)),

                      _divider(context),

                      // 4. Bold text
                      _switch(context,
                          title: 'Bold text',
                          subtitle: 'Makes all body text heavier so characters '
                              'are easier to distinguish at a glance.',
                          value: _s.boldTextEnabled,
                          onChanged: (v) =>
                              setState(() => _s.boldTextEnabled = v)),

                      // Live preview showing the effect of toggles.
                      _readingPreview(context),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: Center(
                    child: Text(
                      'Preview Text',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 16 * _textScaleDraft,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              // Notifications & Reminders section
              _sectionTitle(context, 'Notifications & Reminders'),
              _card(context, children: [
                _switch(context,
                    title: 'Appointment reminders',
                    subtitle: 'Notify me before upcoming appointments.',
                    value: _s.appointmentReminders,
                    onChanged: (v) =>
                        setState(() => _s.appointmentReminders = v)),
                _divider(context),
                _switch(context,
                    title: 'Medication reminders',
                    subtitle: 'Daily reminders for prescriptions.',
                    value: _s.medicationReminders,
                    onChanged: (v) =>
                        setState(() => _s.medicationReminders = v)),
                _divider(context),
                _switch(context,
                    title: 'Critical health alerts',
                    subtitle:
                        'High priority alerts for emergencies and abnormal results.',
                    value: _s.criticalAlerts,
                    onChanged: (v) => setState(() => _s.criticalAlerts = v)),
              ]),

              const SizedBox(height: 20),

              // Voice Assistance section
              _sectionTitle(context, 'Voice Assistance'),
              _card(context, children: [
                _switch(context,
                    title: 'Enable voice input',
                    subtitle:
                        'Use speech-to-text in chat, notes, and search fields.',
                    value: _s.voiceInputEnabled,
                    onChanged: _handleVoiceInputToggle),
                _divider(context),
                _switch(context,
                    title: 'Enable read-back',
                    subtitle:
                        'Tap the speaker icon to have content read aloud.',
                    value: _s.readBackEnabled,
                    onChanged: _handleReadBackToggle),
              ]),

              const SizedBox(height: 20),

              if (widget.showStaffWorkspaces &&
                  _workspaceAccess.hasStaffWorkspaces) ...[
                _sectionTitle(context, 'Staff workspaces'),
                _card(context, children: [
                  if (_workspaceAccess.paramedic)
                    ListTile(
                      leading: const Icon(Icons.emergency),
                      title: const Text('Dispatch & Paramedic workspace'),
                      subtitle: const Text(
                          'Dispatch operations or assigned patient care, according to your role.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _openWorkspace(const ParamedicWorkspacePage()),
                    ),
                  if (_workspaceAccess.bloodBank)
                    ListTile(
                      leading: const Icon(Icons.bloodtype_outlined),
                      title: const Text('Blood Bank'),
                      subtitle: const Text(
                          'Requires an assigned hospital blood-bank membership.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openWorkspace(const BloodBankPage()),
                    ),
                ]),
                const SizedBox(height: 20),
              ],
              _sectionTitle(context, 'Privacy, Security & Permissions'),
              _card(context, children: [
                _switch(context,
                    title: 'Face ID login',
                    subtitle: !_faceAvailable
                        ? 'Not available on this device.'
                        : _s.faceIdLogin
                            ? 'Required for identity verification - cannot be disabled.'
                            : 'Use Face ID to unlock the app - like your banking app.',
                    value: _s.faceIdLogin,
                    onChanged: (_faceAvailable && !_s.faceIdLogin)
                        ? _handleFaceIdToggle
                        : null),
                _divider(context),
                _switch(context,
                    title: 'Fingerprint login',
                    subtitle: _fingerprintAvailable
                        ? 'Use your fingerprint to unlock the app.'
                        : 'Not available on this device.',
                    value: _s.fingerprintLogin,
                    onChanged: _fingerprintAvailable
                        ? _handleFingerprintToggle
                        : null),
                _divider(context),
                _switch(context,
                    title: 'Show personal info on home screen',
                    subtitle:
                        'Hide or show name and profile details on dashboard.',
                    value: _s.showPersonalInfoOnHome,
                    onChanged: (v) =>
                        setState(() => _s.showPersonalInfoOnHome = v)),
                _divider(context),
                _switch(context,
                    title: 'Share anonymised usage data',
                    subtitle:
                        'Help improve the app by sharing anonymous stats.',
                    value: _s.shareUsageData,
                    onChanged: (v) => setState(() => _s.shareUsageData = v)),
                _divider(context),
                _switch(context,
                    title: 'Allow location access',
                    subtitle:
                        'Used for nearby hospitals, emergency services and '
                        'context-aware features.',
                    value: _s.locationEnabled,
                    onChanged: _handleLocationToggle),
                _divider(context),
                _switch(context,
                    title: 'Allow microphone access',
                    subtitle: 'Required for voice input and telehealth calls.',
                    value: _s.microphoneEnabled,
                    onChanged: _handleMicToggle),
              ]),

              const SizedBox(height: 24),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: CorviaColors.success, size: 16),
                    const SizedBox(width: 6),
                    Text('Changes save automatically',
                        style: TextStyle(
                            color: context.cTextSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('Reset to default'),
                  onPressed: _showResetDialog,
                ),
              ),
              if (widget.showSignOut) ...[
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: CorviaColors.danger,
                      foregroundColor: Colors.white,
                    ),
                    icon: _signingOut
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                    onPressed: _signingOut ? null : _signOut,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_appVersion != null)
                Center(
                  child: Text(
                    _appVersion!,
                    style:
                        TextStyle(color: context.cTextSecondary, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      _s.sessionUnlocked = false;
      await SupabaseService.client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _showResetDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.cBgSecondary,
        title: Text('Reset to default?',
            style: TextStyle(color: context.cTextPrimary)),
        content: Text(
          'This restores appearance, notifications, privacy and reading '
          'preferences to their defaults. Your biometric and device security '
          'settings are not affected.',
          style: TextStyle(color: context.cTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    _s.resetToDefaults();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings reset to default.')),
    );
  }

  // Reading support widgets

  Widget _overlayHueSlider(BuildContext context) {
    final thumbColor =
        Color.lerp(_overlayYellow, _overlayAqua, _dyslexiaOverlayDraft)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Warm yellow',
                  style:
                      TextStyle(color: context.cTextSecondary, fontSize: 12)),
              Text('Cool aqua',
                  style:
                      TextStyle(color: context.cTextSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Center(
                  child: Container(
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: const LinearGradient(
                          colors: [_overlayYellow, _overlayAqua]),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 2,
                            offset: const Offset(0, 1))
                      ],
                    ),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: thumbColor,
                  overlayColor: thumbColor.withValues(alpha: 0.22),
                  thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 11,
                      elevation: 2,
                      pressedElevation: 4),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 20),
                ),
                child: Slider(
                  value: _dyslexiaOverlayDraft,
                  onChanged: (v) => setState(() => _dyslexiaOverlayDraft = v),
                  onChangeEnd: (v) => _s.dyslexiaOverlayValue = v,
                  semanticFormatterCallback: (v) {
                    if (v < 0.25) return 'Warm yellow';
                    if (v < 0.5) return 'Light yellow';
                    if (v < 0.75) return 'Light aqua';
                    return 'Cool aqua';
                  },
                ),
              ),
            ],
          ),
          Text('Slide to find the tint that feels most comfortable.',
              style: TextStyle(color: context.cTextSecondary, fontSize: 12)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // Live text preview reflecting current reading flags.
  Widget _readingPreview(BuildContext context) {
    // Build the preview style to match what the theme will apply app-wide.
    TextStyle style = TextStyle(
      color: context.cTextPrimary,
      fontSize: 14,
    );
    if (_s.dyslexiaSpacingEnabled) {
      style =
          style.copyWith(letterSpacing: 0.9, wordSpacing: 4.0, height: 1.65);
    }
    if (_s.dyslexiaVerdanaEnabled) {
      style = style.copyWith(
        fontFamily: CorviaTheme.readingFontFamily,
        fontFamilyFallback: CorviaTheme.readingFontFallback,
      );
    }
    if (_s.boldTextEnabled) {
      style = style.copyWith(fontWeight: FontWeight.w600);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.cDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preview',
                style: TextStyle(
                    color: context.cAccentReadable,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Text(
              'This should be easy to read.\n'
              'Medication taken at 08:00 — next dose 20:00.\n'
              'Appointment confirmed for Tuesday at 14:30.',
              style: style,
            ),
          ],
        ),
      ),
    );
  }

  // Theme picker

  static const Map<CorviaThemeVariant, (Color, Color)> _variantSwatch = {
    CorviaThemeVariant.modernLight: (Color(0xFFF8FAFC), Color(0xFF2563EB)),
    CorviaThemeVariant.modernDark: (Color(0xFF0B1220), Color(0xFF60A5FA)),
    CorviaThemeVariant.premiumLight: (Color(0xFFF8FAFC), Color(0xFF06B6D4)),
    CorviaThemeVariant.premiumDark: (Color(0xFF0F172A), Color(0xFF22D3EE)),
    CorviaThemeVariant.tealLight: (Color(0xFFF0FDFA), Color(0xFF0F766E)),
    CorviaThemeVariant.tealDark: (Color(0xFF042F2A), Color(0xFF2DD4BF)),
  };

  Widget _themePicker(BuildContext context) {
    return Column(
      children: CorviaThemeVariant.values.map((variant) {
        final selected = _s.themeVariant == variant;
        final (background, accent) = _variantSwatch[variant]!;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _s.themeVariant = variant),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.cDivider),
                  ),
                  child: Center(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(variant.label,
                      style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal)),
                ),
                if (selected)
                  Icon(Icons.check_circle,
                      color: context.cAccentReadable, size: 22)
                else
                  Icon(Icons.circle_outlined,
                      color: context.cTextMuted, size: 22),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // Shared UI helpers

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: context.cAccentReadable,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      );

  Widget _row(BuildContext context, IconData icon, String label,
      {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: context.cAccentReadable, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.bold)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(
                          color: context.cTextSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switch(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) =>
      SwitchListTile(
        title: Text(title, style: TextStyle(color: context.cTextPrimary)),
        subtitle:
            Text(subtitle, style: TextStyle(color: context.cTextSecondary)),
        value: value,
        onChanged: onChanged,
      );

  Widget _divider(BuildContext context) =>
      Divider(color: context.cDivider, height: 0);

  Widget _card(BuildContext context, {required List<Widget> children}) =>
      Container(
        // Shadow and shape only. The background colour lives on the Material
        // below so the ListTile-based rows (ExpansionTile, SwitchListTile) have
        // a Material ancestor to paint their fill and ink onto - a DecoratedBox
        // with a colour in between hides those effects and trips an assertion.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: context.cCardShadow,
                blurRadius: 5,
                offset: const Offset(0, 3))
          ],
        ),
        child: Material(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children),
          ),
        ),
      );

  // Biometric handlers

  Future<void> _handleFaceIdToggle(bool enable) => _toggleBiometric(enable,
      label: 'Face ID', setFlag: (v) => _s.faceIdLogin = v);

  Future<void> _handleFingerprintToggle(bool enable) => _toggleBiometric(enable,
      label: 'Fingerprint', setFlag: (v) => _s.fingerprintLogin = v);

  Future<void> _toggleBiometric(bool enable,
      {required String label, required void Function(bool) setFlag}) async {
    if (enable) {
      final available = await BiometricService.isAvailable();
      if (!available) {
        if (!mounted) return;
        _showOpenSettingsDialog(
            '$label Not Available',
            'No $label is enrolled on this device. Please set it up in your '
                'device security settings first.');
        return;
      }
      final AuthResult result = await BiometricService.authenticate(
          reason: 'Authenticate to enable $label login for Corvia.');
      if (!mounted) return;
      if (result == AuthResult.success) {
        setState(() => setFlag(true));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label login enabled.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Authentication failed. $label login not enabled.')));
      }
      return;
    }
    setState(() => setFlag(false));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label login disabled.')));
  }

  // Voice handlers

  Future<void> _handleVoiceInputToggle(bool enable) async {
    if (enable) {
      final granted = await VoiceService.instance.ensureMicPermission();
      if (!mounted) return;
      if (!granted) {
        _showOpenSettingsDialog(
            'Microphone Permission Required',
            'Voice input needs microphone access. Please grant it in your '
                'device settings, then try again.');
        return;
      }
      setState(() => _s.voiceInputEnabled = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Voice input enabled. Tap the mic icon on supported fields.')));
      return;
    }
    await VoiceService.instance.stopListening();
    if (!mounted) return;
    setState(() => _s.voiceInputEnabled = false);
  }

  Future<void> _handleReadBackToggle(bool enable) async {
    if (enable) {
      setState(() => _s.readBackEnabled = true);
      await VoiceService.instance.speak('Read-back is now enabled.');
      return;
    }
    await VoiceService.instance.stopSpeaking();
    if (!mounted) return;
    setState(() => _s.readBackEnabled = false);
  }

  // Permission handlers

  Future<void> _handleLocationToggle(bool enable) async {
    if (enable) {
      final status = await Permission.location.request();
      if (status.isGranted || status.isLimited) {
        setState(() => _s.locationEnabled = true);
      } else if (status.isPermanentlyDenied) {
        _showOpenSettingsDialog(
            'Location Permission Blocked',
            'Location access has been permanently denied. Please enable it '
                'in your device settings.');
      }
      return;
    }
    setState(() => _s.locationEnabled = false);
    _showRevokeDialog('location');
  }

  Future<void> _handleMicToggle(bool enable) async {
    if (enable) {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        setState(() => _s.microphoneEnabled = true);
      } else if (status.isPermanentlyDenied) {
        _showOpenSettingsDialog(
            'Microphone Permission Blocked',
            'Microphone access has been permanently denied. Please enable it '
                'in your device settings.');
      }
      return;
    }
    setState(() => _s.microphoneEnabled = false);
    _showRevokeDialog('microphone');
  }

  // Dialogs

  void _showOpenSettingsDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Open Settings')),
        ],
      ),
    );
  }

  void _showRevokeDialog(String permission) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
            '${permission[0].toUpperCase()}${permission.substring(1)} disabled'),
        content: Text('The app will no longer use $permission. '
            'To fully revoke the OS-level permission, tap "Open Settings" '
            'and disable it from there.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Open Settings')),
        ],
      ),
    );
  }
}
