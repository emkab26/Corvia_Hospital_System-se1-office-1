import 'dart:async';
import 'dart:convert';

import '../config/env.dart';
import '../config/backend_environment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CorviaChatMessage {
  const CorviaChatMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;
}

class CorviaAiReply {
  const CorviaAiReply({
    required this.text,
    required this.engine,
    required this.provider,
    required this.patientId,
    required this.sessionId,
    required this.usedCache,
    required this.usedOllama,
    required this.usedFallback,
  });

  final String text;
  final String engine;
  final String provider;
  final String? patientId;
  final String? sessionId;
  final bool usedCache;
  final bool usedOllama;
  final bool usedFallback;
}

class CorviaAiRouterService {
  CorviaAiRouterService._();

  static SupabaseClient? _aiClient;
  static String? _aiClientUrl;

  static Future<CorviaAiReply> ask({
    required String question,
    required List<CorviaChatMessage> history,
  }) async {
    final cleanQuestion = question.trim();

    if (cleanQuestion.isEmpty) {
      return const CorviaAiReply(
        text: 'Please type a question for Corvia AI nurse.',
        engine: 'AI nurse ready',
        provider: 'fallback',
        patientId: null,
        sessionId: null,
        usedCache: false,
        usedOllama: false,
        usedFallback: true,
      );
    }

    final cloudReply = await _tryCloudAi(
      question: cleanQuestion,
      history: _removeCurrentQuestion(
        question: cleanQuestion,
        history: history,
      ),
    );

    if (cloudReply != null) {
      return cloudReply;
    }

    return CorviaAiReply(
      text: _safetyFallback(cleanQuestion),
      engine: 'AI nurse unavailable',
      provider: 'fallback',
      patientId: null,
      sessionId: null,
      usedCache: false,
      usedOllama: false,
      usedFallback: true,
    );
  }

  static SupabaseClient? _getAiClient() {
    final url = const String.fromEnvironment('AI_SUPABASE_URL').trim();
    final anonKey = const String.fromEnvironment('AI_SUPABASE_ANON_KEY').trim();

    if (url.isEmpty ||
        anonKey.isEmpty ||
        url.contains('YOUR_') ||
        anonKey.contains('YOUR_')) {
      return null;
    }

    try {
      BackendEnvironment.parse(
        profile: Env.backend.environment.name,
        url: url,
        publicKey: anonKey,
        expectedOrigin:
            const String.fromEnvironment('CORVIA_EXPECTED_AI_ORIGIN'),
      );
    } catch (_) {
      return null;
    }
    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return null;
    }

    if (_aiClient == null || _aiClientUrl != url) {
      _aiClient = SupabaseClient(url, anonKey);
      _aiClientUrl = url;
    }

    return _aiClient;
  }

  static String get _functionName {
    final value = const String.fromEnvironment('AI_FUNCTION_NAME').trim();
    return value.isEmpty ? 'corvia-ai' : value;
  }

  static Future<CorviaAiReply?> _tryCloudAi({
    required String question,
    required List<CorviaChatMessage> history,
  }) async {
    final client = _getAiClient();

    if (client == null) {
      return null;
    }

    try {
      final session = await _ensureAnonymousAiSession(client);

      if (session == null) {
        return null;
      }

      final response = await client.functions.invoke(
        _functionName,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: {
          'question': question,
          'history': history
              .where((message) => message.content.trim().isNotEmpty)
              .take(10)
              .map(
                (message) => {
                  'role': message.role == 'assistant' ? 'assistant' : 'user',
                  'content': message.content.trim(),
                },
              )
              .toList(),
        },
      ).timeout(const Duration(seconds: 45));

      final data = _decodeFunctionData(response.data);
      final answer = data['answer']?.toString().trim() ?? '';

      if (answer.isEmpty) {
        return null;
      }

      final engine = data['engine']?.toString().trim() ?? '';
      final provider = data['provider']?.toString().trim() ?? '';

      return CorviaAiReply(
        text: answer,
        engine: engine.isEmpty ? 'Cloud AI nurse' : engine,
        provider: provider.isEmpty ? 'cloud' : provider,
        patientId: _cleanNullable(data['patientId']?.toString()),
        sessionId: null,
        usedCache: false,
        usedOllama: false,
        usedFallback: data['usedFallback'] == true ||
            data['usedFallback']?.toString().toLowerCase() == 'true',
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Session?> _ensureAnonymousAiSession(
    SupabaseClient client,
  ) async {
    final currentSession = client.auth.currentSession;

    if (currentSession != null) {
      return currentSession;
    }

    final response = await client.auth.signInAnonymously();

    return response.session ?? client.auth.currentSession;
  }

  static List<CorviaChatMessage> _removeCurrentQuestion({
    required String question,
    required List<CorviaChatMessage> history,
  }) {
    final cleanedHistory = List<CorviaChatMessage>.from(history);

    if (cleanedHistory.isNotEmpty &&
        cleanedHistory.last.role == 'user' &&
        cleanedHistory.last.content.trim() == question) {
      cleanedHistory.removeLast();
    }

    return cleanedHistory;
  }

  static Map<String, dynamic> _decodeFunctionData(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    if (data is String) {
      try {
        final decoded = jsonDecode(data);

        if (decoded is Map<String, dynamic>) {
          return decoded;
        }

        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return {};
      }
    }

    return {};
  }

  static String? _cleanNullable(String? value) {
    if (value == null) {
      return null;
    }

    final clean = value.trim();

    if (clean.isEmpty || clean.toLowerCase() == 'null') {
      return null;
    }

    return clean;
  }

  static String _safetyFallback(String question) {
    final text = question.toLowerCase();

    if (_containsAny(text, [
      'chest pain',
      'cannot breathe',
      'cant breathe',
      'can’t breathe',
      'shortness of breath',
      'difficulty breathing',
      'passed out',
      'fainting',
      'unconscious',
      'seizure',
      'stroke',
      'face droop',
      'arm weakness',
      'speech problem',
      'severe allergic',
      'swollen throat',
      'severe bleeding',
      'heavy bleeding',
      'choking',
      'severe pain',
    ])) {
      return '''
This may be urgent.

Please contact emergency medical services or go to the nearest emergency department immediately, especially if symptoms are sudden, severe, or getting worse.

Do not drive yourself if you feel seriously unwell. Ask someone nearby for help.
''';
    }

    return '''
AI nurse could not respond right now.

Please try again in a moment. I cannot diagnose you or replace a doctor.

For safer guidance, include:
• What symptom or concern you have
• Where it is
• When it started
• Whether it is getting worse
• Any fever, swelling, bleeding, breathing problems, chest pain, dizziness, fainting, or severe pain

If symptoms are severe, sudden, worsening, or worrying, contact a doctor, clinic, hospital, or emergency medical service.
''';
  }

  static bool _containsAny(String text, List<String> words) {
    return words.any(text.contains);
  }
}
