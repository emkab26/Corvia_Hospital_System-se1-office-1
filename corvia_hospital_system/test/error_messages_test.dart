import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mycorvia/utils/error_messages.dart';

void main() {
  group('never leaks the raw error', () {
    test('a message carrying internals is not passed through', () {
      // What these messages actually look like in the wild.
      final error = PostgrestException(
        message: 'new row violates row-level security policy for table '
            '"medical_records", user 8f2c-9d11-uuid',
        code: '42501',
      );

      final message =
          friendlyErrorMessage(error, whatFailed: "Couldn't save the record.");

      expect(message, isNot(contains('medical_records')));
      expect(message, isNot(contains('8f2c')));
      expect(message, isNot(contains('row-level')));
    });

    test('an unrecognised error still says nothing about internals', () {
      final error = Exception('PGRST301: jwt payload xyz.abc.def malformed');

      final message =
          friendlyErrorMessage(error, whatFailed: "Couldn't load your profile.");

      expect(message, "Couldn't load your profile. Please try again.");
      expect(message, isNot(contains('xyz.abc.def')));
    });

    test('always names what failed', () {
      for (final error in <Object>[
        TimeoutException('x'),
        Exception('SocketException: failed host lookup'),
        AuthException('bad', statusCode: '401'),
        Exception('something nobody has seen before'),
      ]) {
        expect(
          friendlyErrorMessage(error, whatFailed: 'Couldn\'t do the thing.'),
          startsWith("Couldn't do the thing."),
          reason: '$error',
        );
      }
    });
  });

  group('classifies by type and code, not by digits in the text', () {
    test('a timeout is recognised by its type', () {
      expect(
        friendlyErrorReason(TimeoutException('elapsed')),
        'The server took too long to respond. Please try again.',
      );
    });

    test('an auth 401 becomes a session message', () {
      expect(
        friendlyErrorReason(AuthException('bad jwt', statusCode: '401')),
        'Your session has expired. Please sign in and try again.',
      );
    });

    test('an RLS denial becomes a permission message', () {
      expect(
        friendlyErrorReason(
          PostgrestException(message: 'denied', code: '42501'),
        ),
        'You do not have permission to do that.',
      );
    });

    test('a unique violation becomes a conflict message', () {
      expect(
        friendlyErrorReason(
          PostgrestException(message: 'dup', code: '23505'),
        ),
        'Check your details and try again.',
      );
    });

    test('the overlap constraint reads as a conflict too', () {
      // 23P01 is what the appointments exclusion constraint raises.
      expect(
        friendlyErrorReason(
          PostgrestException(message: 'overlap', code: '23P01'),
        ),
        'Check your details and try again.',
      );
    });

    test('no rows where one was expected reads as not found', () {
      expect(
        friendlyErrorReason(
          PostgrestException(message: 'none', code: 'PGRST116'),
        ),
        'We could not find what you were looking for.',
      );
    });

    test('digits inside an id are not mistaken for a status code', () {
      // The reason codes are read from the typed error rather than the string:
      // this message contains 404, 500 and 401 and means none of them.
      final error = PostgrestException(
        message: 'row 404 of batch 500 for patient 401e-uuid could not be read',
        code: null,
      );

      expect(friendlyErrorReason(error), isNull);
    });

    test('a duration in milliseconds is not read as a server error', () {
      expect(friendlyErrorReason(Exception('completed in 1500ms')), isNull);
    });
  });

  group('errors that carry no code', () {
    test('a dead socket reads as offline', () {
      expect(
        friendlyErrorReason(Exception('SocketException: Failed host lookup')),
        'Check your connection and try again.',
      );
    });

    test('a refused connection reads as offline', () {
      expect(
        friendlyErrorReason(Exception('Connection refused')),
        'Check your connection and try again.',
      );
    });

    test('an unrecognised error has no reason invented for it', () {
      expect(friendlyErrorReason(Exception('kaboom')), isNull);
    });
  });
}
