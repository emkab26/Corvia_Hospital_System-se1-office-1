
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/incoming_call_session_panel.dart';

void main() {
  const ringing = IncomingCallSession(
    id: 'session-1',
    revision: 'revision-1',
    state: IncomingCallState.ringing,
    canAnswer: true,
    canDecline: true,
  );

  Widget screen({
    List<IncomingCallSession> sessions = const [ringing],
    IncomingCallCommand? answer,
    IncomingCallCommand? decline,
    IncomingCallCommand? hangUp,
    String Function()? operationId,
    Future<void> Function()? onRefresh,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IncomingCallSessionPanel(
            sessions: sessions,
            onAnswer: answer,
            onDecline: decline,
            onHangUp: hangUp,
            newOperationId: operationId,
            onRefresh: onRefresh,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Unconnected voice controller cannot answer',
    (tester) async {
      await tester.pumpWidget(
        screen(),
      );

      expect(
        find.textContaining(
          'Voice controller is not connected',
        ),
        findsOneWidget,
      );

      final answerButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Answer'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(answerButton.onPressed, isNull);
    },
  );

  testWidgets(
    'Another responder cannot answer',
    (tester) async {
      await tester.pumpWidget(
        screen(
          sessions: const [
            IncomingCallSession(
              id: 'session-2',
              revision: 'revision-2',
              state: IncomingCallState.ringing,
              canAnswer: true,
              ownedByOther: true,
            ),
          ],
          operationId: () => 'operation-1',
          answer: ({
            required sessionId,
            required expectedRevision,
            required operationId,
          }) async {},
        ),
      );

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Answer'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'Unknown answer outcome retries same operation ID',
    (tester) async {
      final operations = <String>[];

      await tester.pumpWidget(
        screen(
          operationId: () => 'same-operation',
          onRefresh: () async {},
          answer: ({
            required sessionId,
            required expectedRevision,
            required operationId,
          }) async {
            operations.add(operationId);

            if (operations.length == 1) {
              throw StateError('timeout');
            }
          },
        ),
      );

      await tester.tap(
        find.text('Answer'),
      );

      await tester.pumpAndSettle();

      expect(
        find.textContaining('Outcome unknown'),
        findsOneWidget,
      );

      final retryBeforeRefresh =
          tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Retry same answer operation'),
          matching: find.byType(OutlinedButton),
        ),
      );

      expect(
        retryBeforeRefresh.onPressed,
        isNull,
      );

      await tester.tap(
        find.byTooltip('Refresh saved call sessions'),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Retry same answer operation'),
      );

      await tester.pumpAndSettle();

      expect(
        operations,
        ['same-operation', 'same-operation'],
      );
    },
  );

  testWidgets(
    'Hang up is disabled without ownership',
    (tester) async {
      await tester.pumpWidget(
        screen(
          sessions: const [
            IncomingCallSession(
              id: 'session-3',
              revision: 'revision-3',
              state: IncomingCallState.active,
              canHangUp: true,
              ownedByMe: false,
            ),
          ],
          operationId: () => 'operation-3',
          hangUp: ({
            required sessionId,
            required expectedRevision,
            required operationId,
          }) async {},
        ),
      );

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Hang up'),
          matching: find.byType(OutlinedButton),
        ),
      );

      expect(button.onPressed, isNull);
    },
  );
}
