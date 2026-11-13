import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/services/qr_scanner_service.dart';

/// The existing scanner tests feed the resolver hand-written payloads, so both
/// sides passed while the emergency screen emitted a string the resolver could
/// not read. These tests bind the two together: everything asserted here starts
/// from what a generator actually produces.
void main() {
  const resolver = QrRouteResolver();
  const patientId = '9f2c1d7e-0000-4a1b-9c3d-patient';

  group('emergency profile payload', () {
    test('what the emergency screen builds is what the scanner reads', () {
      final built = QrPayload.emergencyProfile(patientId);

      final result = resolver.resolve(built);

      expect(result, isNotNull, reason: 'the app must scan its own QR code');
      expect(result!.route, '/emergency');
      expect(result.params['patient_id'], patientId);
    });

    test('carries a version so a scanner can tell the parameter set', () {
      final result = resolver.resolve(QrPayload.emergencyProfile(patientId));

      expect(result!.params['v'], '1');
    });

    test('identifies the patient, not their name', () {
      // Two patients can share a name; encoding one would make their codes
      // interchangeable, which on an emergency screen is a safety problem.
      final a = QrPayload.emergencyProfile('patient-a');
      final b = QrPayload.emergencyProfile('patient-b');

      expect(a, isNot(b));
      expect(resolver.resolve(a)!.params['patient_id'], 'patient-a');
    });

    test('the format shipped before this fix did not resolve', () {
      // Pins the bug this replaced: a colon-separated payload. The resolver
      // splits on '|', so the whole string was read as an unknown prefix and
      // every emergency code fell through to the unknown handler.
      final legacy = 'corvia-emergency-profile:$patientId';

      expect(resolver.resolve(legacy), isNull);
    });
  });

  group('payload builder', () {
    test('produces the shape the check-in screen already emits', () {
      // reception_check_in_qr composes this string by hand and it works, so it
      // is the reference for the format. If the builder ever drifts from it,
      // this fails.
      final built = QrPayload.build(QrPayload.checkIn, {
        'patient_id': 'abc',
        'appointment_id': 'def',
      });

      expect(built, 'CORVIA_CHECKIN|v=1|patient_id=abc|appointment_id=def');
    });

    test('every built prefix resolves to a route', () {
      for (final prefix in [
        QrPayload.checkIn,
        QrPayload.doctor,
        QrPayload.emergency,
        QrPayload.patient,
      ]) {
        final result = resolver.resolve(
          QrPayload.build(prefix, {'patient_id': patientId}),
        );

        expect(result, isNotNull, reason: '$prefix must resolve');
        expect(result!.params['patient_id'], patientId);
      }
    });
  });
}
