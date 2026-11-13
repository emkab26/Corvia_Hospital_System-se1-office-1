import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycorvia/pages/patient/profile.dart';

void main() {
  // This runs once before the test executes
  setUpAll(() async {
    // Mock SharedPreferences for Supabase's local storage needs
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});

    // Initialize Supabase with dummy credentials so the instance doesn't throw a null error
    await Supabase.initialize(
      url:
          'https://mock-project-id.supabase.co', //This is juct for mock up there is no database linkined to this!!
      publishableKey: 'mock-anon-key-abcde12345',
    );
  });

  testWidgets(
      'ProfilePage shows "No profile found." when user is unauthenticated',
      (WidgetTester tester) async {
    // Build our widget tree
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfilePage(),
      ),
    );

    // Allow async profile loading code to complete and UI to update
    await tester.pumpAndSettle();

    // 1. VERIFY EMPTY STATE TEXT APPEARS
    // The mock client returns a null user.
    expect(find.text('No profile found.'), findsOneWidget);

    // 2. VERIFY THAT FORM FIELDS DO NOT EXIST IN THIS STATE
    // This confirms that the form fields are safely hidden when data is missing.
    expect(find.byType(TextField), findsNothing);
  });
}
