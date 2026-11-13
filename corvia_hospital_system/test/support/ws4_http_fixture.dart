import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const fixtureActor = '00000000-0000-4000-8000-000000000001';
Future<SupabaseClient> fixtureClient(
    Future<http.Response> Function(http.Request) handler) async {
  final client = SupabaseClient('http://127.0.0.1:54321', 'synthetic-test-key',
      httpClient: MockClient((request) async {
    final response = await handler(request);
    return http.Response.bytes(response.bodyBytes, response.statusCode,
        headers: response.headers, request: request);
  }), authOptions: const AuthClientOptions(autoRefreshToken: false));
  final token = 'e30.${base64Url.encode(utf8.encode(jsonEncode({
            'exp': 4102444800
          }))).replaceAll('=', '')}.test';
  await client.auth.setInitialSession(jsonEncode({
    'access_token': token,
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': fixtureActor,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z'
    },
  }));
  return client;
}

Map<String, dynamic> fixtureIncident(int id, {String? status = 'pending'}) => {
      'id': id,
      'user_id': fixtureActor,
      'status': status,
      'created_at': '2026-01-01T00:00:00Z',
      'latitude': -26.2,
      'longitude': 28.0,
    };
http.Response jsonResponse(Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});
