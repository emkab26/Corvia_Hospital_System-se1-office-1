
import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/pages/dispatch/incoming_call_session_panel.dart';
import 'package:mycorvia/services/dispatch_voice_session_reader.dart';

void main() {
  test(
    'Ringing sessions are visible but cannot be answered',
    () {
      final result =
          SupabaseDispatchVoiceSessionReader.parseRows(
        [
          {
            'id': 18,
            'incident_id': 123,
            'status': 'ringing',
          },
        ],
        authorisedIncidentIds: {'123'},
      );

      expect(result, hasLength(1));
      expect(result.single.id, '18');
      expect(result.single.incidentId, '123');

      expect(
        result.single.state,
        IncomingCallState.ringing,
      );

      expect(result.single.canAnswer, isFalse);
      expect(result.single.canDecline, isFalse);
      expect(result.single.hasValidIdentity, isFalse);
    },
  );

  test(
    'Answered does not prove connected media',
    () {
      final result =
          SupabaseDispatchVoiceSessionReader.parseRows(
        [
          {
            'id': '19',
            'incident_id': '123',
            'status': 'answered',
          },
        ],
        authorisedIncidentIds: {'123'},
      );

      expect(
        result.single.state,
        IncomingCallState.connecting,
      );

      expect(result.single.canHangUp, isFalse);
    },
  );

  test(
    'Out-of-scope incident is rejected',
    () {
      expect(
        () =>
            SupabaseDispatchVoiceSessionReader.parseRows(
          [
            {
              'id': 18,
              'incident_id': 777,
              'status': 'ringing',
            },
          ],
          authorisedIncidentIds: {'123'},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Repeated session identity is rejected',
    () {
      expect(
        () =>
            SupabaseDispatchVoiceSessionReader.parseRows(
          [
            {
              'id': 18,
              'incident_id': 123,
              'status': 'ringing',
            },
            {
              'id': 18,
              'incident_id': 123,
              'status': 'ended',
            },
          ],
          authorisedIncidentIds: {'123'},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Missing session identity is rejected',
    () {
      expect(
        () =>
            SupabaseDispatchVoiceSessionReader.parseRows(
          [
            {
              'id': null,
              'incident_id': 123,
              'status': 'ringing',
            },
          ],
          authorisedIncidentIds: {'123'},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Unknown call state never grants control',
    () {
      final result =
          SupabaseDispatchVoiceSessionReader.parseRows(
        [
          {
            'id': 21,
            'incident_id': 123,
            'status': 'active',
          },
        ],
        authorisedIncidentIds: {'123'},
      );

      expect(
        result.single.state,
        IncomingCallState.unknown,
      );

      expect(result.single.canAnswer, isFalse);
      expect(result.single.canHangUp, isFalse);
    },
  );
}
