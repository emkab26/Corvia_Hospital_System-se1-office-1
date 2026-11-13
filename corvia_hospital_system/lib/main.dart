import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_gate.dart';
import 'auth/dispatch_entry_redirect.dart';
import 'auth/fleet_entry_redirect.dart';
import 'config/env.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/wearable_link_service.dart';
import 'theme/app_theme.dart';
import 'widgets/corvia_startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);

    if (kDebugMode) {
      debugPrint(
        'FlutterError: ${details.exceptionAsString()}',
      );

      debugPrintStack(
        stackTrace: details.stack,
      );
    }
  };

  runApp(CorviaStartup(
    initializeWithStage: (stage) async {
      stage(CorviaStartupStage.configuration);
      await Env.initializeForStartup();
      final backend = Env.backend;
      stage(CorviaStartupStage.backend);
      await Supabase.initialize(
        url: backend.url,
        // ignore: deprecated_member_use
        anonKey: backend.publicKey,
        debug: false,
      );
      stage(CorviaStartupStage.settings);
      await SettingsService.instance.init();
      stage(CorviaStartupStage.wearables);
      try {
        await WearableLinkService.instance.init()
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        if (kDebugMode) debugPrint('Corvia startup: wearables unavailable');
      }
      stage(CorviaStartupStage.notifications);
      try {
        await NotificationService.instance.init()
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        if (kDebugMode) debugPrint('Corvia startup: notifications unavailable');
      }
    },
    ready: const MyApp(),
  ));
}

// =============================================================================
// MAIN CORVIA APP
// =============================================================================

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
  });

  @override
  State<MyApp> createState() {
    return _MyAppState();
  }
}

class _MyAppState extends State<MyApp> {
  final SettingsService _settings = SettingsService.instance;

  /*
   * IMPORTANT
   * -------------------------------------------------------------------------
   *
   * SettingsService also stores runtime/session values such as:
   *
   * sessionUnlocked
   * deviceVerified
   *
   * Those values may change while Android is pausing/resuming.
   *
   * Rebuilding the complete MaterialApp every time ANY SettingsService value
   * changes can rebuild Flutter's root Navigator while the application is
   * entering/leaving the background.
   *
   * That can cause:
   *
   * A GlobalKey was used multiple times...
   * GlobalObjectKey<NavigatorState> _WidgetsAppState
   *
   * We therefore only rebuild MaterialApp when a VISUAL setting actually
   * changes.
   */

  late int _visualSettingsFingerprint;

  @override
  void initState() {
    super.initState();

    _visualSettingsFingerprint = _calculateVisualSettingsFingerprint();

    _settings.addListener(
      _onSettingsChanged,
    );
  }

  @override
  void dispose() {
    _settings.removeListener(
      _onSettingsChanged,
    );

    super.dispose();
  }

  int _calculateVisualSettingsFingerprint() {
    final variant = _settings.themeVariant;

    return Object.hash(
      variant.hashCode,
      variant.brightness,
      _settings.dyslexiaSpacingEnabled,
      _settings.dyslexiaVerdanaEnabled,
      _settings.boldTextEnabled,
      _settings.textScale,
      _settings.dyslexiaOverlayEnabled,
      _settings.dyslexiaOverlayColor,
    );
  }

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }

    final newFingerprint = _calculateVisualSettingsFingerprint();

    /*
     * If only sessionUnlocked/deviceVerified/etc changed,
     * DO NOT rebuild MaterialApp.
     */
    if (newFingerprint == _visualSettingsFingerprint) {
      return;
    }

    _visualSettingsFingerprint = newFingerprint;

    setState(() {});

    // Many widgets read the static CorviaColors palette rather than
    // Theme.of(context), so they do not depend on the theme and would keep
    // stale colours until something else rebuilt them, which showed as a
    // flash of mixed old/new colours. Rebuild the whole tree in this frame.
    void markForRebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markForRebuild);
    }

    (context as Element).visitChildren(markForRebuild);
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final variant = _settings.themeVariant;

    CorviaColors.setPalette(
      variant.palette,
    );

    CorviaColors.setBrightness(
      variant.brightness,
    );

    final theme = CorviaTheme.resolve(
      dyslexiaFontEnabled: _settings.dyslexiaSpacingEnabled,
      dyslexiaVerdanaEnabled: _settings.dyslexiaVerdanaEnabled,
      boldTextEnabled: _settings.boldTextEnabled,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyCorvia',
      theme: theme,
      darkTheme: theme,
      themeMode: variant.isDark ? ThemeMode.dark : ThemeMode.light,
      // Palette colours are also read from CorviaColors during rebuild.
      // Animating ThemeData against that immediately-updated palette causes
      // a mismatched intermediate frame when switching light/dark.
      themeAnimationDuration: Duration.zero,

      /*
       * IMPORTANT
       * -------------------------------------------------------------------
       *
       * Keep the builder widget structure STABLE.
       *
       * Previously the tree changed between:
       *
       * MediaQuery
       *
       * and
       *
       * Stack -> MediaQuery + overlay
       *
       * depending on SettingsService state.
       *
       * The root MaterialApp child is Flutter's Navigator.
       *
       * We now always use the same structure so that the Navigator does not
       * get unnecessarily moved/re-parented.
       */
      builder: (
        context,
        child,
      ) {
        final appChild = child ?? const SizedBox.shrink();

        final scaledContent = MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(
            textScaler: TextScaler.linear(
              _settings.textScale,
            ),
          ),
          child: appChild,
        );

        final overlayColor = _settings.dyslexiaOverlayEnabled
            ? _settings.dyslexiaOverlayColor
            : Colors.transparent;

        return Stack(
          fit: StackFit.expand,
          children: [
            scaledContent,
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: ColoredBox(
                  color: overlayColor,
                ),
              ),
            ),
          ],
        );
      },

      /*
       * ONE root authentication gate.
       *
       * Never create another MaterialApp/AuthGate from login,
       * dashboard, OAuth callback or registration.
       */
      home: const AuthGate(),
      routes: {
        '/dispatch': (
          context,
        ) =>
            const DispatchEntryRedirect(),
        '/fleet-management': (
          context,
        ) =>
            const FleetEntryRedirect(),
      },
      onUnknownRoute: (
        settings,
      ) {
        return MaterialPageRoute<void>(
          builder: (
            context,
          ) {
            return Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Page Not Found',
                ),
              ),
              body: Center(
                child: Text(
                  'The route ${settings.name} is not registered in main.dart yet.',
                ),
              ),
            );
          },
        );
      },
    );
  }
}
