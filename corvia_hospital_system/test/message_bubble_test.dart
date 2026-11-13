import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/widgets/message_bubble.dart';

void main() {
  testWidgets('renders message text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: 'Hello world'),
        ),
      ),
    );

    expect(find.text('Hello world'), findsOneWidget);
  });

  testWidgets('renders empty message without crashing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: ''),
        ),
      ),
    );

    expect(find.byType(MessageBubble), findsOneWidget);
  });

  testWidgets('wraps text in Padding with 8px insets', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: 'Test'),
        ),
      ),
    );

    final padding = tester.widget<Padding>(
      find.ancestor(of: find.text('Test'), matching: find.byType(Padding)).first,
    );
    expect(padding.padding, const EdgeInsets.all(8.0));
  });
}
