
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/pages/dispatch/incoming_call_session_panel.dart';
import 'package:mycorvia/services/dispatch_voice_session_reader.dart';
import 'package:mycorvia/services/emergency_dispatch_service.dart';
import 'package:mycorvia/theme/app_theme.dart';

import 'support/ws4_access_fixture.dart';

class _FakeVoiceGateway implements DispatchVoiceSessionGateway {
  int calls = 0;

  @override
  String? get currentUserId =>
      '00000000-0000-4000-8000-000000000001';

  @override
  Stream<String?> get userChanges =>
      const Stream<String?>.empty();

  @override
  Future<List<IncomingCallSession>> load() async {
    calls++;

    return const [
      IncomingCallSession(
        id: '11',
        incidentId: '42',
        revision: '',
        state: IncomingCallState.ringing,
        displayName: 'Incident 42 voice session',
      ),
    ];
  }
}

void main() {
  setUp(() {
    CorviaColors.setPalette(
      CorviaPalette.modern,
    );

    CorviaColors.setBrightness(
      Brightness.light,
    );
  });

  testWidgets(
    'Incoming Calls keeps incident queue and shows '
    'read-only voice session metadata',
    (tester) async {
      tester.view.physicalSize =
          const Size(1500, 1000);

      tester.view.devicePixelRatio = 1;

      addTearDown(
        tester.view.resetPhysicalSize,
      );

      addTearDown(
        tester.view.resetDevicePixelRatio,
      );

      final voice = _FakeVoiceGateway();

      await tester.pumpWidget(
        MaterialApp(
          theme: CorviaTheme.resolve(),
          home: EmergencyDispatchDashboard(
            accessLoader: () async =>
                fixtureDispatchAccess(),

            incomingEmergencyLoader: () async => [
              DispatchEmergency(
                id: '42',
                userId: 'patient-42',
                status: 'pending',
                createdAt: DateTime(
                  2026,
                  10,
                  12,
                  12,
                ),
              ),
            ],

            voiceSessionGateway: voice,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Incoming Calls'),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Incoming incidents'),
        findsOneWidget,
      );

      expect(
        find.text('Voice call sessions (read only)'),
        findsOneWidget,
      );

      expect(
        find.text('Incident 42 voice session'),
        findsOneWidget,
      );

      expect(
        voice.calls,
        1,
      );

      final answerButton =
          tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Answer'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(
        answerButton.onPressed,
        isNull,
      );

      expect(
        tester.takeException(),
        isNull,
      );
    },
  );
}
