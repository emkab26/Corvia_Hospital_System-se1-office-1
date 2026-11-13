import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/patient/book_appointment.dart';

/// The three acceptance cases from the duplicate-booking spec, plus the edges it
/// did not cover. The rule under test is an overlap of two ranges, not equality
/// of start times: the schema stores a start plus duration_minutes, so "the same
/// time slot" only means anything as an overlap.
Map<String, dynamic> appt(
  String iso, {
  int minutes = 60,
  String status = 'confirmed',
}) =>
    {
      'appointment_date': iso,
      'duration_minutes': minutes,
      'status': status,
    };

bool clash(DateTime slot, List<dynamic> rows, {int minutes = 60}) =>
    bookingClashesWith(
      slot: slot,
      durationMinutes: minutes,
      defaultDurationMinutes: 30,
      rows: rows,
    );

void main() {
  // Local time throughout: the rows carry UTC, the slot is local, and the
  // comparison has to survive that.
  final tenAm = DateTime(2026, 6, 25, 10, 0);

  String isoLocal(DateTime d) => d.toUtc().toIso8601String();

  group('spec acceptance criteria', () {
    test('case 1: booking a slot the patient already holds is a clash', () {
      expect(clash(tenAm, [appt(isoLocal(tenAm))]), isTrue);
    });

    test('case 2: a different, non-overlapping slot is free', () {
      final elevenAm = DateTime(2026, 6, 25, 11, 0);

      // 10:00-11:00 and 11:00-12:00 touch but do not overlap.
      expect(clash(elevenAm, [appt(isoLocal(tenAm))]), isFalse);
    });

    test('case 3: a cancelled appointment does not block rebooking', () {
      expect(
        clash(tenAm, [appt(isoLocal(tenAm), status: 'cancelled')]),
        isFalse,
      );
    });
  });

  group('which statuses hold a slot', () {
    for (final status in kActiveAppointmentStatuses) {
      test('$status blocks the slot', () {
        expect(clash(tenAm, [appt(isoLocal(tenAm), status: status)]), isTrue);
      });
    }

    for (final status in ['cancelled', 'completed', 'no_show', 'missed']) {
      test('$status leaves the slot free', () {
        expect(clash(tenAm, [appt(isoLocal(tenAm), status: status)]), isFalse);
      });
    }
  });

  group('overlap, not equality', () {
    test('a later start inside an existing appointment clashes', () {
      // 10:30 lands inside 10:00-11:00. An equality check on start times - what
      // the spec's SQL proposed - would have let this through.
      final tenThirty = DateTime(2026, 6, 25, 10, 30);

      expect(clash(tenThirty, [appt(isoLocal(tenAm))], minutes: 30), isTrue);
    });

    test('an earlier booking that runs into an existing one clashes', () {
      // 09:30 + 60min = 10:30, which runs into the 10:00 appointment.
      final nineThirty = DateTime(2026, 6, 25, 9, 30);

      expect(clash(nineThirty, [appt(isoLocal(tenAm))]), isTrue);
    });

    test('a long existing appointment blocks a later slot', () {
      // 10:00 for two hours reaches 12:00, so 11:00 is not free.
      final elevenAm = DateTime(2026, 6, 25, 11, 0);

      expect(clash(elevenAm, [appt(isoLocal(tenAm), minutes: 120)]), isTrue);
    });

    test('ending exactly when another starts is free', () {
      final nineAm = DateTime(2026, 6, 25, 9, 0);

      expect(clash(nineAm, [appt(isoLocal(tenAm))]), isFalse);
    });
  });

  group('rows that cannot be trusted', () {
    test('no appointments means no clash', () {
      expect(clash(tenAm, const []), isFalse);
    });

    test('a null duration falls back to the default slot length', () {
      final row = {
        'appointment_date': isoLocal(tenAm),
        'duration_minutes': null,
        'status': 'confirmed',
      };

      // Falls back to 30 minutes, so 10:00-10:30 is taken but 10:45 is free.
      expect(clash(tenAm, [row], minutes: 15), isTrue);
      expect(clash(DateTime(2026, 6, 25, 10, 45), [row], minutes: 15), isFalse);
    });

    test('an unparseable date is skipped rather than throwing', () {
      expect(clash(tenAm, [appt('not-a-date')]), isFalse);
    });

    test('a missing status is not treated as active', () {
      expect(
        clash(tenAm, [
          {'appointment_date': isoLocal(tenAm), 'duration_minutes': 60}
        ]),
        isFalse,
      );
    });
  });
}
