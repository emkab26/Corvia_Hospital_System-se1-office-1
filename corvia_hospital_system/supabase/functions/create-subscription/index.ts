import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mycorvia/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitForText(
    WidgetTester tester,
    String text, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));

      if (find.text(text).evaluate().isNotEmpty) {
        return;
      }
    }

    fail('Timed out waiting for text: $text');
  }

  Future<void> loginAsTestPatient(
    WidgetTester tester,
  ) async {
    await waitForText(
      tester,
      'Welcome Back to Corvia!',
    );

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

    await tester.tap(
      find.byKey(const Key('loginButton')),
    );

    await tester.pumpAndSettle(
      const Duration(seconds: 5),
    );
  }

  Future<void> openBookingPage(
    WidgetTester tester,
  ) async {
    await waitForText(
      tester,
      'Quick Actions',
    );

    await tester.tap(
      find.byKey(
        const Key('AppointmentsCard'),
      ),
    );

    await tester.pumpAndSettle();

    await waitForText(
      tester,
      'Appointments',
    );

    await tester.tap(
      find.text('Book Appointment'),
    );

    await tester.pumpAndSettle();

    await waitForText(
      tester,
      'Book an Appointment',
    );

    await tester.tap(
      find.byType(ListTile).first,
    );

    await tester.pumpAndSettle();

    await waitForText(
      tester,
      'Available times',
    );
  }

  Finder availableSlotFinder() {
    return find.byWidgetPredicate(
      (widget) =>
          widget.key != null &&
          widget.key.toString().contains(
                'appointmentSlot_',
              ) &&
          widget is InkWell &&
          widget.onTap != null,
    );
  }

  testWidgets(
    'shows validation error when reason is empty',
    (tester) async {
      // Start app
      app.main();

      await tester.pumpAndSettle();

      // Login
      await loginAsTestPatient(
        tester,
      );

      // Navigate to booking page
      await openBookingPage(
        tester,
      );

      // Find available slots
      final availableSlots =
          availableSlotFinder();

      expect(
        availableSlots,
        findsWidgets,
      );

      // Do NOT enter a reason

      // Select slot
      await tester.tap(
        availableSlots.first,
      );

      await tester.pumpAndSettle();

      // Verify validation error
      expect(
        find.text(
          'Please describe the reason for your visit first.',
        ),
        findsOneWidget,
      );
    },
  );
}
```
