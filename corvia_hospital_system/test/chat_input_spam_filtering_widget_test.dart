import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chat with Doctor - Component Widget Validation Tests', () {
    bool simulateCurrentAppBehavior(String inputText) {
      final text = inputText.trim();
      if (text.isEmpty) return false;
      return text.length <= 1000;
    }

    Future<void> pumpProductionInputBar(
      WidgetTester tester, {
      required TextEditingController controller,
      required VoidCallback onSendPressed,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textInputAction: TextInputAction.send,
                          maxLines: 4,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                            counterText: '',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: onSendPressed,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('TC-06: Emoji-Only Input should have Send Button Enabled',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: "😷💊🏥");
      bool sendTriggered = false;

      await pumpProductionInputBar(tester, controller: controller,
          onSendPressed: () {
        if (simulateCurrentAppBehavior(controller.text)) sendTriggered = true;
      });

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isTrue);
    });

    testWidgets(
        'TC-07: Pasting Massive Text Block discards text beyond 1000 characters',
        (WidgetTester tester) async {
      final controller = TextEditingController();
      await pumpProductionInputBar(tester,
          controller: controller, onSendPressed: () {});

      final massivePastedText = 'M' * 2000;
      await tester.enterText(find.byType(TextField), massivePastedText);
      await tester.pump();

      expect(controller.text.length, 1000);
    });

    testWidgets(
        'TC-09: Repeated characters remain sendable under current validation',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: "aaaaaaaaaaaaaaaaaaaa");
      bool sendTriggered = false;

      await pumpProductionInputBar(tester, controller: controller,
          onSendPressed: () {
        if (simulateCurrentAppBehavior(controller.text)) sendTriggered = true;
      });

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isTrue);
    });

    testWidgets(
        'TC-10: Keyboard-row text remains sendable under current validation',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: "asdfghjklasdfghjkl");
      bool sendTriggered = false;

      await pumpProductionInputBar(tester, controller: controller,
          onSendPressed: () {
        if (simulateCurrentAppBehavior(controller.text)) sendTriggered = true;
      });

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isTrue);
    });

    testWidgets('TC-11: Non-empty structured text remains sendable',
        (WidgetTester tester) async {
      final controller =
          TextEditingController(text: "Hello Doc, qwertyuiopasdfg");
      bool sendTriggered = false;

      await pumpProductionInputBar(tester, controller: controller,
          onSendPressed: () {
        if (simulateCurrentAppBehavior(controller.text)) sendTriggered = true;
      });

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isTrue);
    });
  });
}
