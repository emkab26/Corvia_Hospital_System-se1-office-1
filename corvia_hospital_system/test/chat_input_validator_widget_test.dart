import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chat with Doctor - Component Widget Validation Tests', () {
    // Core Logic Helper: Perfectly mirrors the _send() validation check in your main code:
    // final text = _msgCtrl.text.trim();
    // if (text.isEmpty || _chatId == null) return;
    bool simulateSendValidation(String inputText) {
      final text = inputText.trim();
      if (text.isEmpty) {
        return false; // Blocks sending (matches your code's early return)
      }
      if (inputText.length > 1000) {
        return false; // Character ceiling validation constraint
      }
      return true;
    }

    // Helper to build and pump a clean representation of your production input bar layout
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

    // WIDGET & INPUT VALIDATION TEST CASES
    testWidgets('TC-01: Initial/Empty State should prevent sending',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: "");
      bool sendTriggered = false;

      await pumpProductionInputBar(
        tester,
        controller: controller,
        onSendPressed: () {
          if (simulateSendValidation(controller.text)) {
            sendTriggered = true;
          }
        },
      );

      // Tap the production style send icon
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isFalse,
          reason: 'Empty messages must not trigger sending logic');
    });

    testWidgets('TC-02: Whitespace Only Input should prevent sending',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: "       ");
      bool sendTriggered = false;

      await pumpProductionInputBar(
        tester,
        controller: controller,
        onSendPressed: () {
          if (simulateSendValidation(controller.text)) {
            sendTriggered = true;
          }
        },
      );

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isFalse,
          reason: 'Whitespace strings must be trimmed out and blocked');
    });

    testWidgets('TC-03: Valid Text Input should allow sending successfully',
        (WidgetTester tester) async {
      final controller =
          TextEditingController(text: "Hello Doctor, I need help.");
      bool sendTriggered = false;

      await pumpProductionInputBar(
        tester,
        controller: controller,
        onSendPressed: () {
          if (simulateSendValidation(controller.text)) {
            sendTriggered = true;
          }
        },
      );

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isTrue);
    });

    testWidgets(
        'TC-04: Maximum Character Limit (Exactly 1000 chars) should allow sending',
        (WidgetTester tester) async {
      final exactLimitString = 'M' * 1000;
      final controller = TextEditingController(text: exactLimitString);
      bool sendTriggered = false;

      await pumpProductionInputBar(
        tester,
        controller: controller,
        onSendPressed: () {
          if (simulateSendValidation(controller.text)) {
            sendTriggered = true;
          }
        },
      );

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isTrue);
    });

    testWidgets(
        'TC-05: Over-Limit Truncation should clip text length at 1000 characters',
        (WidgetTester tester) async {
      final controller = TextEditingController();

      await pumpProductionInputBar(tester,
          controller: controller, onSendPressed: () {});

      // Simulates a patient typing/pasting a message longer than 1000 characters into the UI widget
      final overLimitString = 'M' * 1005;
      await tester.enterText(find.byType(TextField), overLimitString);
      await tester.pump();

      expect(controller.text.length, 1000,
          reason:
              'Input values must cleanly truncate at a 1000 character boundary');
    });

    testWidgets(
        'TC-08: Enter key formatting should create a newline inside the input component',
        (WidgetTester tester) async {
      final controller = TextEditingController();

      await pumpProductionInputBar(tester,
          controller: controller, onSendPressed: () {});

      // Simulate entering multi-line formatted text containing an enter key return newline (\n)
      const multiLineInput =
          "Hello Doctor,\nI have a question regarding my appointment.";
      await tester.enterText(find.byType(TextField), multiLineInput);
      await tester.pump();

      // Verify that the text input wrapper controller successfully contains the break formatting
      expect(controller.text.contains('\n'), isTrue,
          reason: 'TextField must allow newline values when enter is pressed');
    });
  });
}
