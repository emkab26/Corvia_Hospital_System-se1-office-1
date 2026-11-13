import 'corvia_ai_router_service.dart';

class CorviaChatTurn {
  const CorviaChatTurn({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;
}

class CorviaAiAnswer {
  const CorviaAiAnswer({
    required this.text,
    required this.sourceLabel,
    required this.usedCachedContext,
    required this.usedOllama,
    required this.usedFallback,
  });

  final String text;
  final String sourceLabel;
  final bool usedCachedContext;
  final bool usedOllama;
  final bool usedFallback;
}

/// Compatibility wrapper for older pages that still import corvia_ai_service.dart.
/// The real hybrid AI logic now lives in CorviaAiRouterService.
class CorviaAiService {
  CorviaAiService._();

  static Future<CorviaAiAnswer> ask({
    required String question,
    required List<CorviaChatTurn> history,
  }) async {
    final reply = await CorviaAiRouterService.ask(
      question: question,
      history: history
          .map(
            (message) => CorviaChatMessage(
              role: message.role,
              content: message.content,
            ),
          )
          .toList(),
    );

    return CorviaAiAnswer(
      text: reply.text,
      sourceLabel: reply.engine,
      usedCachedContext: reply.usedCache,
      usedOllama: reply.usedOllama,
      usedFallback: reply.usedFallback,
    );
  }
}
