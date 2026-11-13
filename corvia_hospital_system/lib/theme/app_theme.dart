import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralised colours, text styles, and themes for Corvia.
/// Use these instead of inlining `Color(0xFF...)` values.

// Palette + variant model

enum CorviaPalette { modern, premium, teal }

enum CorviaThemeVariant {
  modernLight(CorviaPalette.modern, Brightness.light, 'Modern Light'),
  modernDark(CorviaPalette.modern, Brightness.dark, 'Modern Dark'),
  premiumLight(CorviaPalette.premium, Brightness.light, 'Premium Light'),
  premiumDark(CorviaPalette.premium, Brightness.dark, 'Premium Dark'),
  tealLight(CorviaPalette.teal, Brightness.light, 'Teal Light'),
  tealDark(CorviaPalette.teal, Brightness.dark, 'Teal Dark');

  const CorviaThemeVariant(this.palette, this.brightness, this.label);

  final CorviaPalette palette;
  final Brightness brightness;
  final String label;

  bool get isDark => brightness == Brightness.dark;

  static const CorviaThemeVariant fallback = CorviaThemeVariant.modernLight;
}

extension CorviaThemeLoader on CorviaThemeVariant {
  String get loaderAnimation {
    switch (palette) {
      case CorviaPalette.modern:
        return 'assets/animations/mLight_LabExplainLoader.json';
      case CorviaPalette.premium:
        return 'assets/animations/pLight_LabExplainLoader.json';
      case CorviaPalette.teal:
        return 'assets/animations/tLight_LabExplainLoader.json';
    }
  }
}

// Colour palette

class CorviaColors {
  static CorviaPalette _palette = CorviaPalette.modern;
  static Brightness _brightness = Brightness.light;
  static bool get _isLight => _brightness == Brightness.light;

  static void setPalette(CorviaPalette p) => _palette = p;
  static void setBrightness(Brightness b) => _brightness = b;

  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  static const Color _modernAccentL = Color(0xFF2563EB);
  static const Color _modernAccentD = Color(0xFF60A5FA);
  static const Color _modernAccentDeep = Color(0xFF1D4ED8);
  static const Color _modernAccentTextL = Color(0xFF1D4ED8);
  static const Color _modernAccentTextD = Color(0xFF93C5FD);
  static const Color _modernSuccess = Color(0xFF10B981);
  static const Color _modernBgL = Color(0xFFF8FAFC);
  static const Color _modernBgD = Color(0xFF0B1220);
  static const Color _modernSurfaceD = Color(0xFF16202E);

  static const Color _premiumAccentL = Color(0xFF06B6D4);
  static const Color _premiumAccentD = Color(0xFF22D3EE);
  static const Color _premiumAccentDeep = Color(0xFF0891B2);
  static const Color _premiumAccentTextL = Color(0xFF0E7490);
  static const Color _premiumAccentTextD = Color(0xFF67E8F9);
  static const Color _premiumSuccess = Color(0xFF22C55E);
  static const Color _premiumBgL = Color(0xFFF8FAFC);
  static const Color _premiumBgD = Color(0xFF0F172A);
  static const Color _premiumSurfaceD = Color(0xFF1E293B);

  static const Color _tealAccentL = Color(0xFF0F766E);
  static const Color _tealAccentD = Color(0xFF2DD4BF);
  static const Color _tealAccentDeep = Color(0xFF0B5C56);
  static const Color _tealAccentTextL = Color(0xFF0F766E);
  static const Color _tealAccentTextD = Color(0xFF5EEAD4);
  static const Color _tealSuccess = Color(0xFF22C55E);
  static const Color _tealBgL = Color(0xFFF0FDFA);
  static const Color _tealBgD = Color(0xFF042F2A);
  static const Color _tealSurfaceD = Color(0xFF0C3B35);

  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightTextPrimary = Color(0xFF0F172A);
  static const Color _lightTextSecondary = Color(0xFF475569);
  static const Color _lightTextMuted = Color(0xFF94A3B8);
  static const Color _lightDivider = Color(0xFFE2E8F0);
  static const Color _lightCardShadow = Color(0x1A000000);
  static const Color _darkText = Colors.white;
  static const Color _darkTextSub = Colors.white70;
  static const Color _darkTextMuted = Colors.white54;
  static const Color _darkDivider = Colors.white12;
  static const Color _darkCardShadow = Color(0x80000000);

  static Color get accent {
    switch (_palette) {
      case CorviaPalette.modern:
        return _isLight ? _modernAccentL : _modernAccentD;
      case CorviaPalette.premium:
        return _isLight ? _premiumAccentL : _premiumAccentD;
      case CorviaPalette.teal:
        return _isLight ? _tealAccentL : _tealAccentD;
    }
  }

  static Color get accentDark {
    switch (_palette) {
      case CorviaPalette.modern:
        return _modernAccentDeep;
      case CorviaPalette.premium:
        return _premiumAccentDeep;
      case CorviaPalette.teal:
        return _tealAccentDeep;
    }
  }

  static Color get accentLight {
    switch (_palette) {
      case CorviaPalette.modern:
        return _isLight ? _modernAccentTextL : _modernAccentTextD;
      case CorviaPalette.premium:
        return _isLight ? _premiumAccentTextL : _premiumAccentTextD;
      case CorviaPalette.teal:
        return _isLight ? _tealAccentTextL : _tealAccentTextD;
    }
  }

  static Color get success {
    switch (_palette) {
      case CorviaPalette.modern:
        return _modernSuccess;
      case CorviaPalette.premium:
        return _premiumSuccess;
      case CorviaPalette.teal:
        return _tealSuccess;
    }
  }

  static Color get primaryDark {
    if (_isLight) {
      switch (_palette) {
        case CorviaPalette.modern:
          return _modernBgL;
        case CorviaPalette.premium:
          return _premiumBgL;
        case CorviaPalette.teal:
          return _tealBgL;
      }
    }
    switch (_palette) {
      case CorviaPalette.modern:
        return _modernBgD;
      case CorviaPalette.premium:
        return _premiumBgD;
      case CorviaPalette.teal:
        return _tealBgD;
    }
  }

  static Color get secondaryDark {
    if (_isLight) return _lightSurface;
    switch (_palette) {
      case CorviaPalette.modern:
        return _modernSurfaceD;
      case CorviaPalette.premium:
        return _premiumSurfaceD;
      case CorviaPalette.teal:
        return _tealSurfaceD;
    }
  }

  static Color get textPrimary => _isLight ? _lightTextPrimary : _darkText;
  static Color get textSecondary =>
      _isLight ? _lightTextSecondary : _darkTextSub;
  static Color get textMuted => _isLight ? _lightTextMuted : _darkTextMuted;
  static Color get divider => _isLight ? _lightDivider : _darkDivider;
  static Color get cardShadow => _isLight ? _lightCardShadow : _darkCardShadow;

  static LinearGradient get bgGradient => LinearGradient(
        colors: [primaryDark, secondaryDark],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
}

// Text styles

class CorviaTextStyles {
  static TextStyle get heading => TextStyle(
      color: CorviaColors.accentLight,
      fontSize: 22,
      fontWeight: FontWeight.bold);
  static TextStyle get title => TextStyle(
      color: CorviaColors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.bold);
  static TextStyle get body =>
      TextStyle(color: CorviaColors.textPrimary, fontSize: 16);
  static TextStyle get subtle =>
      TextStyle(color: CorviaColors.textSecondary, fontSize: 14);
}

// Theme-aware BuildContext extension

extension CorviaContext on BuildContext {
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;

  Color get cBgPrimary {
    Theme.of(this);
    return CorviaColors.primaryDark;
  }

  Color get cBgSecondary {
    Theme.of(this);
    return CorviaColors.secondaryDark;
  }

  Color get cTextPrimary {
    Theme.of(this);
    return CorviaColors.textPrimary;
  }

  Color get cTextSecondary {
    Theme.of(this);
    return CorviaColors.textSecondary;
  }

  Color get cTextMuted {
    Theme.of(this);
    return CorviaColors.textMuted;
  }

  Color get cAccentReadable {
    Theme.of(this);
    return CorviaColors.accentLight;
  }

  Color get cCardShadow {
    Theme.of(this);
    return CorviaColors.cardShadow;
  }

  Color get cDivider {
    Theme.of(this);
    return CorviaColors.divider;
  }

  LinearGradient get cBgGradient {
    Theme.of(this);
    return CorviaColors.bgGradient;
  }
}

// Theme builder

class CorviaTheme {
  CorviaTheme._();

  /// Builds [ThemeData] for the active palette + brightness.
  ///
  /// Reading-support flags (all default false):
  ///   [dyslexiaFontEnabled]   — wider letter/word spacing + generous line height
  ///   [dyslexiaVerdanaEnabled]— Verdana font family app-wide
  ///   [highContrastEnabled]   — maximum text/background contrast
  ///   [boldTextEnabled]       — heavier weight on all body & label styles
  static ThemeData resolve({
    bool dyslexiaFontEnabled = false,
    bool dyslexiaVerdanaEnabled = false,
    bool highContrastEnabled = false,
    bool boldTextEnabled = false,
  }) {
    final isLight = CorviaColors._isLight;

    // High-contrast overrides surface & text colours for WCAG AAA compliance.
    final bg = highContrastEnabled
        ? (isLight ? Colors.white : Colors.black)
        : CorviaColors.primaryDark;
    final surface = highContrastEnabled
        ? (isLight ? Colors.white : const Color(0xFF0D0D0D))
        : CorviaColors.secondaryDark;
    final onSurface = highContrastEnabled
        ? (isLight ? Colors.black : Colors.white)
        : CorviaColors.textPrimary;

    final ColorScheme scheme = isLight
        ? ColorScheme.light(
            primary: CorviaColors.accent,
            secondary: CorviaColors.accentLight,
            surface: surface,
            surfaceContainerHighest: surface,
            surfaceContainerHigh: surface,
            surfaceContainer: surface,
            surfaceContainerLow: bg,
            surfaceContainerLowest: bg,
            onSurface: onSurface,
            onSurfaceVariant: highContrastEnabled
                ? Colors.black87
                : CorviaColors.textSecondary,
            error: CorviaColors.danger,
            onPrimary: Colors.white,
            outline: CorviaColors.textMuted,
            outlineVariant: CorviaColors.divider,
          )
        : ColorScheme.dark(
            primary: CorviaColors.accent,
            secondary: CorviaColors.accentLight,
            surface: surface,
            surfaceContainerHighest: surface,
            surfaceContainerHigh: surface,
            surfaceContainer: surface,
            surfaceContainerLow: bg,
            surfaceContainerLowest: bg,
            onSurface: onSurface,
            onSurfaceVariant: highContrastEnabled
                ? Colors.white70
                : CorviaColors.textSecondary,
            error: CorviaColors.danger,
            onPrimary: Colors.white,
            outline: CorviaColors.textMuted,
            outlineVariant: CorviaColors.divider,
          );

    final ThemeData base = ThemeData(
      brightness: isLight ? Brightness.light : Brightness.dark,
      primaryColor: CorviaColors.accent,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        centerTitle: true,
        elevation: isLight ? 1 : 0,
        iconTheme: IconThemeData(color: onSurface),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
        ),
        titleTextStyle: TextStyle(
            color: onSurface, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: isLight ? 2 : 4,
        shadowColor: CorviaColors.cardShadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CorviaColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CorviaColors.accent,
          foregroundColor: Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: CorviaColors.accentLight),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : CorviaColors.secondaryDark,
        labelStyle: TextStyle(color: CorviaColors.textSecondary),
        hintStyle: TextStyle(color: CorviaColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CorviaColors.textMuted, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CorviaColors.accent, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? CorviaColors.accent
                : (isLight ? Colors.grey.shade400 : Colors.white54)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? CorviaColors.accent.withValues(alpha: isLight ? 0.4 : 0.5)
                : (isLight ? Colors.grey.shade300 : Colors.white12)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: CorviaColors.accent,
        thumbColor: CorviaColors.accent,
        inactiveTrackColor: isLight ? CorviaColors.textMuted : Colors.white24,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isLight ? CorviaColors.textPrimary : CorviaColors.secondaryDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: CorviaColors.accent),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: CorviaColors.accentLight,
        unselectedItemColor: CorviaColors.textMuted,
        elevation: isLight ? 8 : 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: CorviaColors.accentLight,
        unselectedLabelColor: CorviaColors.textMuted,
        indicatorColor: CorviaColors.accentLight,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        titleTextStyle: TextStyle(
            color: onSurface, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: CorviaColors.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: CorviaColors.divider),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        textStyle: TextStyle(color: onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: surface,
        collapsedBackgroundColor: surface,
        iconColor: CorviaColors.textSecondary,
        collapsedIconColor: CorviaColors.textSecondary,
        textColor: onSurface,
        collapsedTextColor: onSurface,
      ),
      listTileTheme: ListTileThemeData(
          textColor: onSurface, iconColor: CorviaColors.textSecondary),
      chipTheme: ChipThemeData(
        backgroundColor:
            isLight ? CorviaColors.primaryDark : CorviaColors.secondaryDark,
        labelStyle: TextStyle(color: CorviaColors.textPrimary),
        selectedColor: CorviaColors.accent,
        secondarySelectedColor: CorviaColors.accent,
        side: BorderSide(color: CorviaColors.textMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    // Apply reading support text styles if any flag is on
    final bool anyReadingFlag =
        dyslexiaFontEnabled || dyslexiaVerdanaEnabled || boldTextEnabled;

    if (!anyReadingFlag) return base;

    return base.copyWith(
      textTheme: _applyReadingTextTheme(
        base.textTheme,
        spacing: dyslexiaFontEnabled,
        verdana: dyslexiaVerdanaEnabled,
        bold: boldTextEnabled,
      ),
      primaryTextTheme: _applyReadingTextTheme(
        base.primaryTextTheme,
        spacing: dyslexiaFontEnabled,
        verdana: dyslexiaVerdanaEnabled,
        bold: boldTextEnabled,
      ),
    );
  }

  // Reading support helpers

  static TextTheme _applyReadingTextTheme(
    TextTheme t, {
    required bool spacing,
    required bool verdana,
    required bool bold,
  }) {
    TextStyle apply(TextStyle? s) =>
        _readingStyle(s, spacing: spacing, verdana: verdana, bold: bold);

    return t.copyWith(
      displayLarge: apply(t.displayLarge),
      displayMedium: apply(t.displayMedium),
      displaySmall: apply(t.displaySmall),
      headlineLarge: apply(t.headlineLarge),
      headlineMedium: apply(t.headlineMedium),
      headlineSmall: apply(t.headlineSmall),
      titleLarge: apply(t.titleLarge),
      titleMedium: apply(t.titleMedium),
      titleSmall: apply(t.titleSmall),
      bodyLarge: apply(t.bodyLarge),
      bodyMedium: apply(t.bodyMedium),
      bodySmall: apply(t.bodySmall),
      labelLarge: apply(t.labelLarge),
      labelMedium: apply(t.labelMedium),
      labelSmall: apply(t.labelSmall),
    );
  }

  /// Verdana where the platform has it, otherwise the bundled Bitstream Vera.
  static const String readingFontFamily = 'Verdana';
  static const List<String> readingFontFallback = ['BitstreamVera'];

  static TextStyle _readingStyle(
    TextStyle? base, {
    required bool spacing,
    required bool verdana,
    required bool bold,
  }) {
    TextStyle s = base ?? const TextStyle();

    if (spacing) {
      s = s.copyWith(
        letterSpacing: 0.9,
        wordSpacing: 4.0,
        height: 1.65,
      );
    }

    if (verdana) {
      s = s.copyWith(
        fontFamily: readingFontFamily,
        fontFamilyFallback: readingFontFallback,
      );
    }

    if (bold) {
      final current = s.fontWeight ?? FontWeight.normal;
      if (current.value < FontWeight.w600.value) {
        s = s.copyWith(fontWeight: FontWeight.w600);
      }
    }

    return s;
  }
}
