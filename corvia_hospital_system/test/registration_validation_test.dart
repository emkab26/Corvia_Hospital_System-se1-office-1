import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/auth/register.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  group('Registration Form Validation', () {
    Future<void> loadForm(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: RegisterPage(),
        ),
      );
      await tester.pump();
    }

    Future<void> submitForm(WidgetTester tester) async {
      final button = find.byKey(const Key('registerButton'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
    }

    testWidgets('should show required errors when fields are empty',
        (tester) async {
      await loadForm(tester);

      await submitForm(tester);

      expect(find.text('First Name is required'), findsOneWidget);
      expect(find.text('Surname is required'), findsOneWidget);
      expect(find.text('ID Number is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('should validate ID number length', (tester) async {
      await loadForm(tester);

      await tester.enterText(find.byKey(const Key('idField')), '12345');
      await submitForm(tester);

      expect(find.text('Must be exactly 13 digits'), findsOneWidget);
    });

    testWidgets('should validate email format correctness', (tester) async {
      await loadForm(tester);

      await tester.enterText(
          find.byKey(const Key('emailField')), 'invalidemail.com');
      await submitForm(tester);

      expect(
        find.text('Enter a valid email address (e.g. name@example.co.za).'),
        findsOneWidget,
      );
    });

    testWidgets('should enforce minimum password length', (tester) async {
      await loadForm(tester);

      await tester.enterText(find.byKey(const Key('passwordField')), '123');
      await submitForm(tester);

      expect(
          find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('should fail when confirm password does not match',
        (tester) async {
      await loadForm(tester);

      await tester.enterText(
          find.byKey(const Key('passwordField')), 'password123');
      await tester.enterText(
          find.byKey(const Key('confirmPasswordField')), 'password456');
      await submitForm(tester);

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('should pass validation with completely valid inputs',
        (tester) async {
      await loadForm(tester);

      await tester.enterText(find.byKey(const Key('firstNameField')), 'John');
      await tester.enterText(find.byKey(const Key('surnameField')), 'Doe');
      await tester.enterText(find.byKey(const Key('idField')), '9001015001081');
      await tester.enterText(
          find.byKey(const Key('emailField')), 'valid@example.com');
      await tester.enterText(
          find.byKey(const Key('passwordField')), 'secure123');
      await tester.enterText(
          find.byKey(const Key('confirmPasswordField')), 'secure123');

      final FormState formState = tester.state<FormState>(find.byType(Form));
      expect(formState.validate(), isTrue);
    });
  });
}
