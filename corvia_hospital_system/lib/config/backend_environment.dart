import 'dart:convert';

enum CorviaEnvironment { local, testing, live }

/// Build configuration is explicit. It never falls back to the bundled .env.
class BackendEnvironment {
  BackendEnvironment._(this.environment, this.url, this.publicKey);
  final CorviaEnvironment environment;
  final String url;
  final String publicKey;

  factory BackendEnvironment.parse({
    String profile = 'local',
    String url = 'http://127.0.0.1:54321',
    required String publicKey,
    String expectedOrigin = '',
  }) {
    final matches = CorviaEnvironment.values.where((e) => e.name == profile);
    if (matches.isEmpty) {
      throw StateError('Select local, testing or live with CORVIA_ENV.');
    }
    final environment = matches.single;
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !const ['', '/'].contains(uri.path) ||
        !const ['http', 'https'].contains(uri.scheme)) {
      throw StateError(
          'SUPABASE_URL must be a backend origin without credentials or paths.');
    }
    final origin = uri.origin;
    if (environment == CorviaEnvironment.local) {
      if (!const {'127.0.0.1', 'localhost', '[::1]', '::1', '10.0.2.2'}
          .contains(uri.host)) {
        throw StateError(
            'Local builds require a loopback or Android emulator backend.');
      }
    } else {
      if (uri.scheme != 'https' || expectedOrigin.trim() != origin) {
        throw StateError(
            'Testing/live requires HTTPS and matching CORVIA_EXPECTED_BACKEND_ORIGIN.');
      }
    }
    final key = publicKey.trim();
    if (key.isEmpty || key.startsWith('sb_secret_')) {
      throw StateError(
          'Supply only the backend public client key via SUPABASE_ANON_KEY.');
    }
    final parts = key.split('.');
    if (parts.length == 3) {
      Map<String, dynamic>? claims;
      try {
        claims = jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
      } catch (_) {
        throw StateError('The public client key has an invalid token format.');
      }
      if (claims['role'] != 'anon') {
        throw StateError(
            'A privileged or user token must not be bundled as the public client key.');
      }
    }
    return BackendEnvironment._(environment, origin, key);
  }
}
