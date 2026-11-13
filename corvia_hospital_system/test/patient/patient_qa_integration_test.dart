import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mycorvia/pages/patient/my_prescriptions.dart';
import 'package:mycorvia/pages/patient/profile.dart';
import '../support/ws4_http_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> profile;
  Completer<http.Response>? pendingSave;
  final writes = <Map<String, dynamic>>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'synthetic-key',
      authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(), autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final table = request.url.pathSegments.last;
        if (table == 'profiles' && request.method == 'PATCH') {
          final update =
              Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          writes.add(update);
          final response = await (pendingSave?.future ??
              Future.value(http.Response('', 204)));
          if (response.statusCode == 204) profile.addAll(update);
          return http.Response.bytes(response.bodyBytes, response.statusCode,
              headers: response.headers, request: request);
        }
        if (request.method != 'GET' && !request.url.path.contains('/rpc/')) {
          throw StateError(
              'Unexpected mutation: ${request.method} ${request.url}');
        }
        final Object value = switch (table) {
          'corvia_current_mode_access' => {
              'signed_in': true,
              'profile_found': true,
              'auth_user_id': fixtureActor,
              'profile_id': 'profile-a',
              'role': 'patient',
              'is_active': true,
              'has_patient_profile': true,
            },
          'profiles' => [profile],
          'patients' => [
              {'id': 'patient-a', 'profile_id': fixtureActor}
            ],
          'prescriptions' => [
              {
                'id': 'prescription-a',
                'patient_id': 'patient-a',
                'doctor_id': 'doctor-a',
                'medication_name': 'Synthetic medicine',
                'dosage': 'One tablet',
                'frequency': 'Daily',
                'duration': '7 days',
                'issued_at': DateTime.now().toIso8601String(),
                'status': 'active',
              }
            ],
          _ => [],
        };
        return http.Response(jsonEncode(value), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
    final auth = await fixtureClient((_) async => jsonResponse(null));
    await Supabase.instance.client.auth
        .setInitialSession(jsonEncode(auth.auth.currentSession!.toJson()));
    await auth.dispose();
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    writes.clear();
    pendingSave = null;
    profilePageHasChangesNotifier.value = false;
    profilePageIsSavingNotifier.value = false;
    profile = {
      'id': 'profile-a',
      'user_id': fixtureActor,
      'role': 'patient',
      'is_active': true,
      'first_name': 'Synthetic',
      'surname': 'Patient',
      'address': '12 Long Street',
      'phone_number': '0821234567',
    };
  });

  Future<void> open(WidgetTester tester, Widget page,
      {double width = 1200}) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester, String address) async {
    await tester.ensureVisible(find.text('Edit details'));
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Address');
    await tester.ensureVisible(field);
    await tester.enterText(field, address);
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
  }

  testWidgets(
      'real Profile preserves its draft and warnings after a failed pending save',
      (tester) async {
    pendingSave = Completer<http.Response>();
    await open(tester, const ProfilePage());
    await edit(tester, '14 Long Street');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(writes, [
      {'address': '14 Long Street', 'phone_number': '082 123 4567'}
    ]);
    expect(profilePageIsSavingNotifier.value, isTrue);
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Address'))
            .enabled,
        isFalse);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.text('Unsaved Changes'), findsNothing);
    expect(profilePageHasChangesNotifier.value, isTrue);

    pendingSave!.complete(jsonResponse(
        {'code': '503', 'message': 'Synthetic unavailable'},
        status: 503));
    await tester.pumpAndSettle();
    expect(profilePageIsSavingNotifier.value, isFalse);
    expect(profilePageHasChangesNotifier.value, isTrue);
    expect(find.text('14 Long Street'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved Changes'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('14 Long Street'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real Profile normalises a no-op save and disables Save on reopening',
      (tester) async {
    await open(tester, const ProfilePage());
    await edit(tester, '12 Long Street ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes.single['address'], '12 Long Street');
    expect(find.byType(TextFormField), findsNothing);
    expect(profilePageHasChangesNotifier.value, isFalse);
    await tester.ensureVisible(find.text('Edit details'));
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Address'))
            .controller!
            .text,
        '12 Long Street');
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  for (final width in [430.0, 1200.0]) {
    testWidgets(
        'prescription cards only offer the full-width pharmacy action at $width px',
        (tester) async {
      await open(tester, const MyPrescriptionsPage(), width: width);
      await tester.ensureVisible(find.text('Synthetic medicine'));
      await tester.tap(find.text('Synthetic medicine'));
      await tester.pumpAndSettle();
      expect(find.text('Pharmacy Status & Collection'), findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join('\n'));
      final button = find.ancestor(
          of: find.text('Pharmacy Status & Collection'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      expect(find.text('Show QR'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.byTooltip('Export prescriptions'), findsNothing);
      final container = find
          .ancestor(
              of: button,
              matching: find.byWidgetPredicate((widget) =>
                  widget is SizedBox && widget.width == double.infinity))
          .first;
      expect(tester.getSize(button).width, tester.getSize(container).width);
      expect(tester.getSize(button).width, greaterThan(width * .7));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
