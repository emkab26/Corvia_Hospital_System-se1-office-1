import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Singleton that loads, stores, and broadcasts all user settings.
///
/// Usage:
///   await SettingsService.instance.init();   // call once in main()
///   SettingsService.instance.themeMode = ThemeMode.light;  // auto-persists
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final instance = SettingsService._();

  // pref keys
  static const _kTheme = 'settings_theme';
  static const _kThemeVariant = 'settings_theme_variant';
  static const _kTextScale = 'settings_text_scale';
  static const _kApptReminders = 'settings_appt_reminders';
  static const _kMedReminders = 'settings_med_reminders';
  static const _kCriticalAlerts = 'settings_critical_alerts';
  static const _kVoiceInput = 'settings_voice_input';
  static const _kReadBack = 'settings_read_back';
  static const _kBiometricLegacy = 'settings_biometric';
  static const _kFaceId = 'settings_face_id_login';
  static const _kFingerprint = 'settings_fingerprint_login';
  static const _kDeviceVerified = 'settings_device_verified';
  static const _kShowPersonalInfo = 'settings_show_personal_info';
  static const _kShareUsage = 'settings_share_usage';
  static const _kLocation = 'settings_location';
  static const _kMicrophone = 'settings_microphone';

  // reading support pref keys
  static const _kDyslexiaOverlayEnabled = 'settings_dyslexia_overlay_enabled';
  static const _kDyslexiaOverlayValue = 'settings_dyslexia_overlay_value';
  static const _kDyslexiaSpacing = 'settings_dyslexia_font';
  static const _kDyslexiaVerdana = 'settings_dyslexia_verdana';
  static const _kBoldText = 'settings_bold_text';

  // internal state
  late SharedPreferences _prefs;

  CorviaThemeVariant _themeVariant = CorviaThemeVariant.fallback;
  double _textScale = 1.0;
  bool _appointmentReminders = true;
  bool _medicationReminders = true;
  bool _criticalAlerts = true;
  bool _voiceInputEnabled = true;
  bool _readBackEnabled = true;
  bool _faceIdLogin = false;
  bool _fingerprintLogin = false;
  bool _deviceVerified = false;
  bool _showPersonalInfoOnHome = true;
  bool _shareUsageData = false;
  bool _locationEnabled = true;
  bool _microphoneEnabled = true;

  // reading support state
  bool _dyslexiaOverlayEnabled = false;
  double _dyslexiaOverlayValue = 0.0;
  bool _dyslexiaSpacingEnabled = false;
  bool _dyslexiaVerdanaEnabled = false;
  bool _boldTextEnabled = false;

  // Getters

  CorviaThemeVariant get themeVariant => _themeVariant;
  ThemeMode get themeMode =>
      _themeVariant.isDark ? ThemeMode.dark : ThemeMode.light;

  double get textScale => _textScale;
  bool get appointmentReminders => _appointmentReminders;
  bool get medicationReminders => _medicationReminders;
  bool get criticalAlerts => _criticalAlerts;
  bool get voiceInputEnabled => _voiceInputEnabled;
  bool get readBackEnabled => _readBackEnabled;
  bool get faceIdLogin => _faceIdLogin;
  bool get fingerprintLogin => _fingerprintLogin;
  bool get anyBiometricEnabled => _faceIdLogin || _fingerprintLogin;
  bool sessionUnlocked = false;
  bool get deviceVerified => _deviceVerified;
  bool get showPersonalInfoOnHome => _showPersonalInfoOnHome;
  bool get shareUsageData => _shareUsageData;
  bool get locationEnabled => _locationEnabled;
  bool get microphoneEnabled => _microphoneEnabled;

  // reading support getters
  bool get dyslexiaOverlayEnabled => _dyslexiaOverlayEnabled;
  double get dyslexiaOverlayValue => _dyslexiaOverlayValue;
  bool get dyslexiaSpacingEnabled => _dyslexiaSpacingEnabled;

  /// Kept for backwards compatibility with settings_page references.
  bool get dyslexiaFontEnabled => _dyslexiaSpacingEnabled;

  bool get dyslexiaVerdanaEnabled => _dyslexiaVerdanaEnabled;
  bool get boldTextEnabled => _boldTextEnabled;

  /// Resolved tint colour for the reading overlay. Interpolates cream-yellow
  /// → pale-aqua at 15 % opacity. Use as a full-screen stack layer.
  Color get dyslexiaOverlayColor {
    const yellow = Color(0xFFFFF9C4);
    const aqua = Color(0xFFB2EBF2);
    return Color.lerp(yellow, aqua, _dyslexiaOverlayValue)!
        .withValues(alpha: 0.15);
  }

  //init

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _themeVariant = _loadThemeVariant();
    _textScale = _prefs.getDouble(_kTextScale) ?? 1.0;
    _appointmentReminders = _prefs.getBool(_kApptReminders) ?? true;
    _medicationReminders = _prefs.getBool(_kMedReminders) ?? true;
    _criticalAlerts = _prefs.getBool(_kCriticalAlerts) ?? true;
    _voiceInputEnabled = _prefs.getBool(_kVoiceInput) ?? true;
    _readBackEnabled = _prefs.getBool(_kReadBack) ?? true;
    _faceIdLogin = _prefs.getBool(_kFaceId) ?? false;
    _fingerprintLogin = _prefs.getBool(_kFingerprint) ?? false;
    _deviceVerified = _prefs.getBool(_kDeviceVerified) ?? false;

    final legacy = _prefs.getBool(_kBiometricLegacy);
    if (legacy == true &&
        !_prefs.containsKey(_kFaceId) &&
        !_prefs.containsKey(_kFingerprint)) {
      _faceIdLogin = true;
      _fingerprintLogin = true;
      await _prefs.setBool(_kFaceId, true);
      await _prefs.setBool(_kFingerprint, true);
    }
    if (legacy != null) await _prefs.remove(_kBiometricLegacy);

    _showPersonalInfoOnHome = _prefs.getBool(_kShowPersonalInfo) ?? true;
    _shareUsageData = _prefs.getBool(_kShareUsage) ?? false;
    _locationEnabled = _prefs.getBool(_kLocation) ?? true;
    _microphoneEnabled = _prefs.getBool(_kMicrophone) ?? true;

    // reading support
    _dyslexiaOverlayEnabled = _prefs.getBool(_kDyslexiaOverlayEnabled) ?? false;
    _dyslexiaOverlayValue =
        (_prefs.getDouble(_kDyslexiaOverlayValue) ?? 0.0).clamp(0.0, 1.0);
    _dyslexiaSpacingEnabled = _prefs.getBool(_kDyslexiaSpacing) ?? false;
    _dyslexiaVerdanaEnabled = _prefs.getBool(_kDyslexiaVerdana) ?? false;
    _boldTextEnabled = _prefs.getBool(_kBoldText) ?? false;

    notifyListeners();
  }

  CorviaThemeVariant _loadThemeVariant() {
    final saved = _prefs.getString(_kThemeVariant);
    if (saved != null) {
      for (final v in CorviaThemeVariant.values) {
        if (v.name == saved) return v;
      }
    }
    final legacyIdx = _prefs.getInt(_kTheme);
    if (legacyIdx != null) {
      final wasDark = legacyIdx == ThemeMode.dark.index;
      _prefs.remove(_kTheme);
      final migrated = wasDark
          ? CorviaThemeVariant.modernDark
          : CorviaThemeVariant.modernLight;
      _prefs.setString(_kThemeVariant, migrated.name);
      return migrated;
    }
    return CorviaThemeVariant.fallback;
  }

  // setters

  set themeVariant(CorviaThemeVariant v) {
    if (_themeVariant == v) return;
    _themeVariant = v;
    _prefs.setString(_kThemeVariant, v.name);
    notifyListeners();
  }

  set textScale(double v) {
    if (_textScale == v) return;
    _textScale = v;
    _prefs.setDouble(_kTextScale, v);
    notifyListeners();
  }

  set appointmentReminders(bool v) {
    if (_appointmentReminders == v) return;
    _appointmentReminders = v;
    _prefs.setBool(_kApptReminders, v);
    notifyListeners();
  }

  set medicationReminders(bool v) {
    if (_medicationReminders == v) return;
    _medicationReminders = v;
    _prefs.setBool(_kMedReminders, v);
    notifyListeners();
  }

  set criticalAlerts(bool v) {
    if (_criticalAlerts == v) return;
    _criticalAlerts = v;
    _prefs.setBool(_kCriticalAlerts, v);
    notifyListeners();
  }

  set voiceInputEnabled(bool v) {
    if (_voiceInputEnabled == v) return;
    _voiceInputEnabled = v;
    _prefs.setBool(_kVoiceInput, v);
    notifyListeners();
  }

  set readBackEnabled(bool v) {
    if (_readBackEnabled == v) return;
    _readBackEnabled = v;
    _prefs.setBool(_kReadBack, v);
    notifyListeners();
  }

  set faceIdLogin(bool v) {
    if (_faceIdLogin == v) return;
    _faceIdLogin = v;
    _prefs.setBool(_kFaceId, v);
    notifyListeners();
  }

  set fingerprintLogin(bool v) {
    if (_fingerprintLogin == v) return;
    _fingerprintLogin = v;
    _prefs.setBool(_kFingerprint, v);
    notifyListeners();
  }

  void disableAllBiometrics() {
    faceIdLogin = false;
    fingerprintLogin = false;
  }

  set deviceVerified(bool v) {
    if (_deviceVerified == v) return;
    _deviceVerified = v;
    _prefs.setBool(_kDeviceVerified, v);
    notifyListeners();
  }

  set showPersonalInfoOnHome(bool v) {
    if (_showPersonalInfoOnHome == v) return;
    _showPersonalInfoOnHome = v;
    _prefs.setBool(_kShowPersonalInfo, v);
    notifyListeners();
  }

  set shareUsageData(bool v) {
    if (_shareUsageData == v) return;
    _shareUsageData = v;
    _prefs.setBool(_kShareUsage, v);
    notifyListeners();
  }

  set locationEnabled(bool v) {
    if (_locationEnabled == v) return;
    _locationEnabled = v;
    _prefs.setBool(_kLocation, v);
    notifyListeners();
  }

  set microphoneEnabled(bool v) {
    if (_microphoneEnabled == v) return;
    _microphoneEnabled = v;
    _prefs.setBool(_kMicrophone, v);
    notifyListeners();
  }

  // reading support setters

  set dyslexiaOverlayEnabled(bool v) {
    if (_dyslexiaOverlayEnabled == v) return;
    _dyslexiaOverlayEnabled = v;
    _prefs.setBool(_kDyslexiaOverlayEnabled, v);
    notifyListeners();
  }

  set dyslexiaOverlayValue(double v) {
    final c = v.clamp(0.0, 1.0);
    if (_dyslexiaOverlayValue == c) return;
    _dyslexiaOverlayValue = c;
    _prefs.setDouble(_kDyslexiaOverlayValue, c);
    notifyListeners();
  }

  set dyslexiaSpacingEnabled(bool v) {
    if (_dyslexiaSpacingEnabled == v) return;
    _dyslexiaSpacingEnabled = v;
    _prefs.setBool(_kDyslexiaSpacing, v);
    notifyListeners();
  }

  /// Alias kept so settings_page can write to either name.
  set dyslexiaFontEnabled(bool v) => dyslexiaSpacingEnabled = v;

  set dyslexiaVerdanaEnabled(bool v) {
    if (_dyslexiaVerdanaEnabled == v) return;
    _dyslexiaVerdanaEnabled = v;
    _prefs.setBool(_kDyslexiaVerdana, v);
    notifyListeners();
  }

  set boldTextEnabled(bool v) {
    if (_boldTextEnabled == v) return;
    _boldTextEnabled = v;
    _prefs.setBool(_kBoldText, v);
    notifyListeners();
  }

  /// Restores user-facing preferences to their first-run defaults.
  ///
  /// Security and device state (biometric login, device verification, session
  /// unlock) is deliberately left untouched so a reset can never lock the user
  /// out or silently weaken authentication. Each setter persists and notifies.
  void resetToDefaults() {
    themeVariant = CorviaThemeVariant.fallback;
    textScale = 1.0;
    appointmentReminders = true;
    medicationReminders = true;
    criticalAlerts = true;
    voiceInputEnabled = true;
    readBackEnabled = true;
    showPersonalInfoOnHome = true;
    shareUsageData = false;
    locationEnabled = true;
    microphoneEnabled = true;
    dyslexiaOverlayEnabled = false;
    dyslexiaOverlayValue = 0.0;
    dyslexiaSpacingEnabled = false;
    dyslexiaVerdanaEnabled = false;
    boldTextEnabled = false;
  }
}
