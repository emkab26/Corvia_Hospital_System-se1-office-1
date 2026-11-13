import 'backend_environment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  // ============================================================
  // SUPABASE
  // ============================================================

  static BackendEnvironment? _debugBackend;

  /// Plain `flutter run` has no compile-time defines. In debug builds only,
  /// read the repository's public client settings from its bundled .env asset.
  /// Explicit --dart-define values always take precedence.
  static Future<void> initializeForStartup() async {
    const hasBackendDefines = bool.hasEnvironment('CORVIA_ENV') ||
        bool.hasEnvironment('SUPABASE_URL') ||
        bool.hasEnvironment('SUPABASE_ANON_KEY') ||
        bool.hasEnvironment('CORVIA_EXPECTED_BACKEND_ORIGIN');
    if (hasBackendDefines || !kDebugMode) return;
    await dotenv.load(fileName: '.env');
    const publicKeys = {
      'SUPABASE_URL',
      'SUPABASE_ANON_KEY',
      'MAPTILER_KEY',
      'OAUTH_REDIRECT_URL',
      'STUN_SERVER',
    };
    if (dotenv.env.keys.any((key) => !publicKeys.contains(key))) {
      throw StateError('The development .env contains a non-public setting.');
    }
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final uri = Uri.tryParse(url);
    _debugBackend = BackendEnvironment.parse(
      profile: 'testing',
      url: url,
      publicKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
      expectedOrigin: uri != null && uri.hasAuthority ? uri.origin : '',
    );
  }

  static BackendEnvironment get backend => _debugBackend ?? BackendEnvironment.parse(
    profile: const String.fromEnvironment('CORVIA_ENV', defaultValue: 'local'),
    url: const String.fromEnvironment('SUPABASE_URL',
        defaultValue: 'http://127.0.0.1:54321'),
    publicKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    expectedOrigin:
        const String.fromEnvironment('CORVIA_EXPECTED_BACKEND_ORIGIN'),
  );
  static String get supabaseUrl => backend.url;
  static String get supabaseAnonKey => backend.publicKey;

  // ============================================================
  // OAUTH / AUTH CALLBACK
  // ============================================================

  static String get oauthRedirectUrl {
    final value = const String.fromEnvironment('OAUTH_REDIRECT_URL').trim().isNotEmpty
        ? const String.fromEnvironment('OAUTH_REDIRECT_URL').trim()
        : (_debugBackend == null ? '' : dotenv.env['OAUTH_REDIRECT_URL'] ?? '').trim();

    if (value.isEmpty) {
      return 'mycorvia://login-callback';
    }

    return _cleanRedirectUrl(value);
  }

  // ============================================================
  // MAPTILER
  // ============================================================

  /// MapTiler tile key.
  /// Null when unset, signalling callers to fall back to
  /// the keyless OpenStreetMap tile server.
  static String? get mapTilerKey {
    final value = const String.fromEnvironment('MAPTILER_KEY').trim().isNotEmpty
        ? const String.fromEnvironment('MAPTILER_KEY').trim()
        : (_debugBackend == null ? '' : dotenv.env['MAPTILER_KEY'] ?? '').trim();

    if (value.isEmpty) {
      return null;
    }

    return value;
  }

  // ============================================================
  // WEBRTC / STUN / TURN
  // ============================================================

  static String get stunServer {
    final value = const String.fromEnvironment('STUN_SERVER').trim().isNotEmpty
        ? const String.fromEnvironment('STUN_SERVER').trim()
        : (_debugBackend == null ? '' : dotenv.env['STUN_SERVER'] ?? '').trim();

    if (value.isEmpty) {
      return 'stun:stun.l.google.com:19302';
    }

    return value;
  }

  static String? get turnServer {
    final value = const String.fromEnvironment('TURN_SERVER').trim();

    if (value.isEmpty) {
      return null;
    }

    return value;
  }

  static String? get turnUsername {
    final value = const String.fromEnvironment('TURN_USERNAME').trim();

    if (value.isEmpty) {
      return null;
    }

    return value;
  }

  static String? get turnCredential {
    final value = const String.fromEnvironment('TURN_CREDENTIAL').trim();

    if (value.isEmpty) {
      return null;
    }

    return value;
  }

  static List<Map<String, dynamic>> get iceServers {
    final servers = <Map<String, dynamic>>[
      {
        'urls': stunServer,
      },
    ];

    final turn = turnServer;

    if (turn != null && turn.isNotEmpty) {
      servers.add({
        'urls': turn,
        if (turnUsername != null) 'username': turnUsername,
        if (turnCredential != null) 'credential': turnCredential,
      });
    }

    return servers;
  }

  // ============================================================
  // EMERGENCY
  // ============================================================

  /// Phone-first MVP by default. Enable only for a validated Corvia dispatch
  /// backend; this flag does not connect Corvia to ER24's systems.
  static const emergencyDispatchEnabled = bool.fromEnvironment(
    'CORVIA_EMERGENCY_DISPATCH_ENABLED',
    defaultValue: false,
  );

  /// Enable after the reviewed WS4/team EMS bridge SQL and route are installed.
  static const ws4TeamEmsHandoffEnabled = bool.fromEnvironment(
    'CORVIA_WS4_TEAM_EMS_HANDOFF_ENABLED',
    defaultValue: false,
  );

  /// Emergency cancel PIN.
  /// Legacy confirmation only; never a server authorization credential.
  /// Server cancellation policy replaces this in the backend slice.
  static String get emergencyCancelPin {
    final value = const String.fromEnvironment('EMERGENCY_CANCEL_PIN').trim();

    if (value.isEmpty) {
      return '1234';
    }

    return value;
  }

  // ============================================================
  // INTERNAL HELPERS
  // ============================================================

  static String _cleanRedirectUrl(String rawUrl) {
    var url = rawUrl.trim();

    while (url.endsWith('/')) {
      url = url.substring(
        0,
        url.length - 1,
      );
    }

    return url;
  }
}
