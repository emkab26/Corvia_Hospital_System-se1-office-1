import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/config/backend_environment.dart';

void main() {
  test('default environment is local with no remote fallback', () {
    final env = BackendEnvironment.parse(publicKey: 'synthetic-test');
    expect(env.environment, CorviaEnvironment.local);
    expect(env.url, 'http://127.0.0.1:54321');
    expect(
        () => BackendEnvironment.parse(
            publicKey: 'x', url: 'https://remote.example'),
        throwsStateError);
  });
  for (final profile in ['testing', 'live']) {
    test('$profile needs explicit matching HTTPS origin', () {
      expect(
          () => BackendEnvironment.parse(
              profile: profile, url: 'https://target.example', publicKey: 'x'),
          throwsStateError);
      expect(
          () => BackendEnvironment.parse(
              profile: profile,
              url: 'http://target.example',
              publicKey: 'x',
              expectedOrigin: 'http://target.example'),
          throwsStateError);
      final env = BackendEnvironment.parse(
          profile: profile,
          url: 'https://target.example/',
          publicKey: 'x',
          expectedOrigin: 'https://target.example');
      expect(env.url, 'https://target.example');
    });
  }
  test(
      'invalid profiles, credentials, URL paths and privileged keys fail closed',
      () {
    expect(() => BackendEnvironment.parse(profile: 'prod', publicKey: 'x'),
        throwsStateError);
    for (final url in [
      'https://user:pass@target.example',
      'http://localhost/rest/v1',
      'http://localhost?key=private'
    ]) {
      expect(() => BackendEnvironment.parse(url: url, publicKey: 'x'),
          throwsStateError);
    }
    for (final key in [
      '',
      'sb_secret_hidden',
      'e30.${base64Url.encode(utf8.encode(jsonEncode({
            'role': 'service_role'
          })))}.test'
    ]) {
      expect(() => BackendEnvironment.parse(publicKey: key), throwsStateError);
    }
  });
}
