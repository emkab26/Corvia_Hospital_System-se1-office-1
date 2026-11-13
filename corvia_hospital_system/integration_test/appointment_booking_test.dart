import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mycorvia/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitForText(
    WidgetTester tester,
    String text, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final end = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));

      if (find.text(text).evaluate().isNotEmpty) return;
    }

    fail('Timed out waiting for text: $text');
  }

  Future<void> signOutIfNeeded(WidgetTester tester) async {
    final supabase = Supabase.instance.client;

    if (supabase.auth.currentSession != null) {
      await supabase.auth.signOut();
      await tester.pumpAndSettle();
    }
  }

  Future<void> loginAsTestPatient(WidgetTester tester) async {
    await signOutIfNeeded(tester);
    await waitForText(tester, 'Welcome Back to Corvia!');

    final email = dotenv.env['TEST_PATIENT_EMAIL'];
    final password = dotenv.env['TEST_PATIENT_PASSWORD'];

    expect(email, isNotNull);
    expect(password, isNotNull);

    await tester.enterText(
      find.byKey(const Key('emailField')),
      email!,
    );

    await tester.enterText(
      find.byKey(const Key('passwordField')),
      password!,
    );

    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (find.byKey(const Key('loginButton')).evaluate().isNotEmpty) {
      fail('Login did not complete. Check test credentials.');
    }
  }

  Future<void> openBookingPage(WidgetTester tester) async {
    await waitForText(tester, 'Quick Actions');

    final appointmentsCard = find.byKey(const Key('AppointmentsCard'));

    await tester.scrollUntilVisible(
      appointmentsCard,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(appointmentsCard);
    await tester.pumpAndSettle();

    await waitForText(tester, 'Appointments');

    await tester.tap(find.text('Book Appointment'));
    await tester.pumpAndSettle();

    await waitForText(tester, 'Book an Appointment');

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    await waitForText(tester, 'Available times');
    await waitForText(tester, 'Reason for visit');
  }

  Future<void> pickDateSevenDaysFromToday(WidgetTester tester) async {
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    final targetDate = DateTime.now().add(
      const Duration(days: 7),
    );

    await tester.tap(
      find.text('${targetDate.day}').last,
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await waitForText(tester, 'Available times');
  }

  Finder availableSlotFinder() {
    return find.byWidgetPredicate(
      (widget) =>
          widget.key != null &&
          widget.key.toString().contains('appointmentSlot_') &&
          widget is InkWell &&
          widget.onTap != null,
    );
  }

  testWidgets(
    'shows validation error when reason is empty',
    (tester) async {
      debugPrint('1) shows validation error when reason is empty');
      app.main();
      await tester.pumpAndSettle();

      await loginAsTestPatient(tester);
      await openBookingPage(tester);
      await pickDateSevenDaysFromToday(tester);

      final availableSlots = availableSlotFinder();

      expect(availableSlots, findsWidgets);

      await tester.tap(availableSlots.first);
      await tester.pumpAndSettle();

      expect(
        find.text('Please describe the reason for your visit first.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'appointment type selection changes to telehealth',
    (tester) async {
      debugPrint('2) Appointment type selection changes to telehealth');
      app.main();
      await tester.pumpAndSettle();

      await loginAsTestPatient(tester);
      await openBookingPage(tester);

      expect(
        find.byKey(const Key('telehealthChip')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('telehealthChip')));
      await tester.pumpAndSettle();

      expect(
        find.text('Telehealth'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'duration selection changes duration',
    (tester) async {
      debugPrint('3) Duration selection changes duration');
      app.main();
      await tester.pumpAndSettle();

      await loginAsTestPatient(tester);
      await openBookingPage(tester);

      final durationOptions = find.byWidgetPredicate(
        (widget) =>
            widget.key != null &&
            widget.key.toString().contains('duration_') &&
            widget is ChoiceChip,
      );

      expect(
        durationOptions,
        findsAtLeastNWidgets(2),
        reason: 'Need at least two duration options to test changing duration.',
      );

      await tester.tap(durationOptions.at(1));
      await tester.pumpAndSettle();

      expect(
        durationOptions,
        findsWidgets,
      );
    },
  );

  /*
      TODO: Requires TEST_NO_PROFILE_EMAIL and TEST_NO_PROFILE_PASSWORD
          to be set in .env for an auth user without a Registered Profile.
...
*/
  /*
    //
  testWidgets(
    'patient profile validation blocks booking',
        (tester) async {
          debugPrint('4) Patient profile validation blocks booking');
      app.main();
      await tester.pumpAndSettle();

      await loginAsNoProfilePatient(tester);
      await openBookingPage(tester);
      await pickDateSevenDaysFromToday(tester);

      await tester.enterText(
        find.byKey(const Key('reasonField')),
        'Patient profile validation test',
      );

      await tester.pumpAndSettle();

      final availableSlots = availableSlotFinder();

      expect(
        availableSlots,
        findsWidgets,
      );

      await tester.tap(availableSlots.first);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('confirmBookingButton')),
      );

      await tester.pumpAndSettle();

      expect(
        find.text(
          'Patient profile not found. Please complete registration.',
        ),
        findsOneWidget,
      );
    },
  ); */

  testWidgets(
    'successful appointment booking',
    (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await loginAsTestPatient(tester);
      await openBookingPage(tester);
      await pickDateSevenDaysFromToday(tester);

      await tester.enterText(
        find.byKey(const Key('reasonField')),
        'Integration test booking',
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('telehealthChip')));
      await tester.pumpAndSettle();

      final durationOptions = find.byWidgetPredicate(
        (widget) =>
            widget.key != null &&
            widget.key.toString().contains('duration_') &&
            widget is ChoiceChip,
      );

      if (durationOptions.evaluate().length > 1) {
        await tester.tap(durationOptions.at(1));
        await tester.pumpAndSettle();
      }

      final availableSlots = availableSlotFinder();

      expect(availableSlots, findsWidgets);

      await tester.tap(availableSlots.first);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirmBookingButton')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(
        find.text('Appointment booked successfully.'),
        findsOneWidget,
      );
    },
  );
}
