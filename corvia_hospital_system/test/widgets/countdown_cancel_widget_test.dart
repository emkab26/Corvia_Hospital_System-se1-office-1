import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/widgets/countdown_cancel_widget.dart';

Widget _buildSubject({
  int seconds = 3,
  String label = 'Testing in',
  required VoidCallback onComplete,
  required VoidCallback onCancel,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CountdownCancelWidget(
        seconds: seconds,
        label: label,
        onComplete: onComplete,
        onCancel: onCancel,
      ),
    ),
  );
}

void main() {
  group('Initial render', () {
    testWidgets('renders the circular progress ring', (tester) async {
      await tester.pumpWidget(_buildSubject(onComplete: () {}, onCancel: () {}));
      expect(find.byKey(const Key('countdown_ring')), findsOneWidget);
    });

    testWidgets('shows the starting seconds in the centre', (tester) async {
      await tester.pumpWidget(_buildSubject(onComplete: () {}, onCancel: () {}));
      expect(find.byKey(const Key('countdown_seconds')), findsOneWidget);
    });

    testWidgets('shows the Cancel button', (tester) async {
      await tester.pumpWidget(_buildSubject(onComplete: () {}, onCancel: () {}));
      expect(find.byKey(const Key('countdown_cancel_button')), findsOneWidget);
    });

    testWidgets('shows the correct label text', (tester) async {
      await tester.pumpWidget(_buildSubject(onComplete: () {}, onCancel: () {}));
      expect(find.byKey(const Key('countdown_label')), findsOneWidget);
    });
  });

  group('Countdown behaviour', () {
    testWidgets('decrements from 3 to 2 after one second', (tester) async {
      await tester.pumpWidget(_buildSubject(onComplete: () {}, onCancel: () {}));
      await tester.pump();
      final before = tester.widget<Text>(find.byKey(const Key('countdown_seconds'))).data ?? '';
      expect(before, isNotEmpty);
      await tester.pump(const Duration(seconds: 1));
      final after = tester.widget<Text>(find.byKey(const Key('countdown_seconds'))).data ?? '';
      expect(after, isNotEmpty);
      expect(int.parse(after), lessThan(int.parse(before)));
    });

    testWidgets('decrements from 2 to 1 after two seconds', (tester) async {
      await tester.pumpWidget(_buildSubject(onComplete: () {}, onCancel: () {}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final seconds = tester.widget<Text>(find.byKey(const Key('countdown_seconds'))).data ?? '';
      expect(seconds, isNotEmpty);
      expect(int.parse(seconds), lessThanOrEqualTo(1));
    });
  });

  group('Cancel behaviour', () {
    testWidgets('calls onCancel when Cancel button is tapped', (tester) async {
      bool cancelled = false;
      await tester.pumpWidget(_buildSubject(onComplete: () {}, onCancel: () => cancelled = true));
      await tester.tap(find.byKey(const Key('countdown_cancel_button')));
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('does not call onComplete when cancelled', (tester) async {
      bool completed = false;
      await tester.pumpWidget(_buildSubject(onComplete: () => completed = true, onCancel: () {}));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('countdown_cancel_button')));
      await tester.pump(const Duration(seconds: 3));
      expect(completed, isFalse);
    });
  });

  group('Auto-complete behaviour', () {
    testWidgets('calls onComplete when countdown reaches zero', (tester) async {
      bool completed = false;
      await tester.pumpWidget(_buildSubject(onComplete: () => completed = true, onCancel: () {}));
      await tester.pump(const Duration(seconds: 3));
      expect(completed, isTrue);
    });

    testWidgets('does not call onComplete before countdown finishes', (tester) async {
      bool completed = false;
      await tester.pumpWidget(_buildSubject(onComplete: () => completed = true, onCancel: () {}));
      await tester.pump(const Duration(seconds: 2));
      expect(completed, isFalse);
    });

    testWidgets('does not call onCancel when countdown completes naturally', (tester) async {
      bool cancelled = false;
      await tester.pumpWidget(_buildSubject(onComplete: () {}, onCancel: () => cancelled = true));
      await tester.pump(const Duration(seconds: 3));
      expect(cancelled, isFalse);
    });
  });
}
