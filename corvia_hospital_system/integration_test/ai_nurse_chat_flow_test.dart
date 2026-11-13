import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mycorvia/pages/patient/ai_nurse.dart';
import 'package:mycorvia/services/corvia_ai_router_service.dart';

Future<CorviaAiReply> _fakeAiAsk({
  required String question,
  required List<CorviaChatMessage> history,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 250));

  return CorviaAiReply(
    text: 'Fake AI nurse response for: $question',
    engine: 'Fake AI test engine',
    provider: 'test',
    patientId: null,
    sessionId: null,
    usedCache: false,
    usedOllama: false,
    usedFallback: false,
  );
}

Finder get _textField => find.byType(TextField);
Finder get _sendButton => find.byType(FloatingActionButton);
Finder get _editableText => find.byType(EditableText);

FloatingActionButton _sendFab(WidgetTester tester) {
  return tester.widget<FloatingActionButton>(_sendButton);
}

EditableText _editable(WidgetTester tester) {
  return tester.widget<EditableText>(_editableText);
}

Future<void> _pumpAiNurse(
  WidgetTester tester, {
  AiNurseAsk ask = _fakeAiAsk,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AiNursePage(ask: ask),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('AI nurse chat flow', () {
    testWidgets('shows the initial screen state', (tester) async {
      await _pumpAiNurse(tester);

      expect(find.text('AI nurse'), findsOneWidget);
      expect(find.textContaining('Hi, I am Corvia AI nurse'), findsOneWidget);
      expect(find.text('Hybrid AI ready'), findsOneWidget);
      expect(find.text('0 / 1000'), findsOneWidget);
      expect(_sendFab(tester).onPressed, isNull);
    });

    testWidgets('disables send for empty and whitespace-only input', (
      tester,
    ) async {
      await _pumpAiNurse(tester);

      expect(_sendFab(tester).onPressed, isNull);

      await tester.enterText(_textField, '     ');
      await tester.pump();

      expect(find.text('5 / 1000'), findsOneWidget);
      expect(_sendFab(tester).onPressed, isNull);
      expect(
          find.text('AI nurse is checking your Corvia data...'), findsNothing);
    });

    testWidgets('updates the counter and enforces the 1000 character limit', (
      tester,
    ) async {
      await _pumpAiNurse(tester);

      const message = 'Hello AI nurse';
      await tester.enterText(_textField, message);
      await tester.pump();

      expect(find.text('${message.length} / 1000'), findsOneWidget);
      expect(_sendFab(tester).onPressed, isNotNull);

      final longMessage = 'a' * 1200;
      await tester.enterText(_textField, longMessage);
      await tester.pump();

      expect(find.text('1000 / 1000'), findsOneWidget);
      expect(_editable(tester).controller.text.length, 1000);
    });

    testWidgets('button submission sends a valid message and clears input', (
      tester,
    ) async {
      await _pumpAiNurse(tester);

      const question = 'I have a headache';
      await tester.enterText(_textField, question);
      await tester.pump();

      expect(_sendFab(tester).onPressed, isNotNull);

      await tester.tap(_sendButton);
      await tester.pump();

      expect(find.text(question), findsOneWidget);
      expect(find.text('AI nurse is checking your Corvia data...'),
          findsOneWidget);
      expect(find.text('0 / 1000'), findsOneWidget);
      expect(_editable(tester).controller.text, isEmpty);
      expect(_sendFab(tester).onPressed, isNull);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.text('Fake AI nurse response for: $question'),
        findsOneWidget,
      );
      expect(find.text('Fake AI test engine'), findsWidgets);
      expect(
          find.text('AI nurse is checking your Corvia data...'), findsNothing);
    });

    testWidgets('keyboard submission uses the same validation and fake AI', (
      tester,
    ) async {
      await _pumpAiNurse(tester);

      const question = 'What medication do I have?';
      await tester.enterText(_textField, question);
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(find.text(question), findsOneWidget);
      expect(find.text('0 / 1000'), findsOneWidget);
      expect(_editable(tester).controller.text, isEmpty);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.text('Fake AI nurse response for: $question'),
        findsOneWidget,
      );
    });
  });
}
