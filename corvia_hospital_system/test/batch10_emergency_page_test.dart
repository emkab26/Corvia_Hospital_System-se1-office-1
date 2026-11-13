import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mycorvia/services/dispatch_call_controller.dart';
import 'package:mycorvia/pages/patient/emergency.dart';

/// Drives [Permission.location] so both branches of the permission card can be
/// exercised. Only the members the emergency screen actually calls are
/// overridden; anything else keeps the base class's throwing default so a new
/// dependency shows up as a failure rather than a silent pass.
class _FakePermissionHandler extends PermissionHandlerPlatform {
  _FakePermissionHandler(this.status);

  final PermissionStatus status;
  int openedAppSettings = 0;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      status;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async =>
      {for (final p in permissions) p: status};

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async =>
      ServiceStatus.enabled;

  @override
  Future<bool> openAppSettings() async {
    openedAppSettings++;
    return true;
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(
          Permission permission) async =>
      false;
}

/// The emergency screen runs an unbounded pulse animation, so `pumpAndSettle`
/// would never return. Pump explicit frames instead.
Future<void> _pumpEmergencyPage(WidgetTester tester) async {
  await tester
      .pumpWidget(const MaterialApp(home: LegacyDispatchEmergencyPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

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

  group('Dispatch countdown', () {
    /// Builds the real controller without calling `startup()`, which would hit
    /// Supabase, WebRTC and the filesystem. The countdown is self-contained.
    Future<DispatchCallController> buildController(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      return DispatchCallController(
        incidentId: null,
        context: context,
        onStateChanged: () {},
      );
    }

    testWidgets('opens a three second window before the call is placed',
        (tester) async {
      final controller = await buildController(tester);

      expect(controller.isCountingDown, isFalse);

      controller.startCallWithCountdown();

      expect(controller.isCountingDown, isTrue);
      expect(controller.countdown, 3);

      controller.cancelCountdown();
    });

    testWidgets('ticks down once per second', (tester) async {
      final controller = await buildController(tester);
      controller.startCallWithCountdown();

      await tester.pump(const Duration(seconds: 1));
      expect(controller.countdown, 2);

      await tester.pump(const Duration(seconds: 1));
      expect(controller.countdown, 1);

      controller.cancelCountdown();
    });

    testWidgets('cancelling inside the window stops the call being placed',
        (tester) async {
      final controller = await buildController(tester);
      controller.startCallWithCountdown();

      await tester.pump(const Duration(seconds: 1));
      controller.cancelCountdown();

      expect(controller.isCountingDown, isFalse);
      expect(controller.countdown, 3, reason: 'window must re-arm at 3');

      // Well past the point the call would have gone out. `startVoiceCallAndSignal`
      // is what moves the status off its initial value, so an unchanged status is
      // proof the cancel actually stopped the dispatch rather than just hiding the
      // countdown UI.
      await tester.pump(const Duration(seconds: 10));
      expect(controller.statusMessage, 'Preparing emergency...');
    });

    testWidgets('letting the window elapse places the call', (tester) async {
      final controller = await buildController(tester);
      controller.startCallWithCountdown();

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(controller.isCountingDown, isFalse);
      // The counterpart to the cancel test: dispatch was reached. With no
      // incident on the controller it stops there and says so, which is the
      // observable that proves the countdown fired rather than silently expired.
      expect(controller.statusMessage, 'No incident');
    });
  });

  group('Emergency call button', () {
    setUp(() {
      PermissionHandlerPlatform.instance =
          _FakePermissionHandler(PermissionStatus.granted);
    });

    testWidgets('is rendered on the emergency screen', (tester) async {
      await _pumpEmergencyPage(tester);

      expect(find.text('Call Dispatch'), findsOneWidget);
    });

    testWidgets('a tap does not dispatch on its own', (tester) async {
      await _pumpEmergencyPage(tester);

      await tester.tap(find.text('Call Dispatch'));
      await tester.pump();

      // Dispatch is always behind an explicit confirmation, so a single tap must
      // never reach the operator.
      expect(find.text('Calling in 3...'), findsNothing);
    });

    testWidgets('cannot dispatch while there is no incident to attach to',
        (tester) async {
      await _pumpEmergencyPage(tester);

      // No incident could be created here, so the button is inert. Confirming an
      // emergency that has nothing to attach to would strand the caller.
      await tester.tap(find.text('Call Dispatch'));
      await tester.pump();

      expect(find.text('Confirm Emergency'), findsNothing);
    });
  });

  group('Location permission card', () {
    testWidgets('is hidden once location is granted', (tester) async {
      PermissionHandlerPlatform.instance =
          _FakePermissionHandler(PermissionStatus.granted);

      await _pumpEmergencyPage(tester);

      // Regression guard: the card used to render unconditionally, telling users
      // to enable a permission they had already granted, with no way to dismiss
      // it, on the emergency screen.
      expect(find.text('Location sharing in emergencies'), findsNothing);
      expect(find.text('Enable location'), findsNothing);
    });

    testWidgets('is shown, with a way out, when location is denied',
        (tester) async {
      PermissionHandlerPlatform.instance =
          _FakePermissionHandler(PermissionStatus.denied);

      await _pumpEmergencyPage(tester);

      expect(find.text('Location sharing in emergencies'), findsOneWidget);
      expect(find.text('Enable location'), findsOneWidget);
    });

    testWidgets('stays hidden when location is granted only while in use',
        (tester) async {
      PermissionHandlerPlatform.instance =
          _FakePermissionHandler(PermissionStatus.limited);

      await _pumpEmergencyPage(tester);

      // `limited` still lets dispatch see the caller, so prompting would be noise.
      expect(find.text('Location sharing in emergencies'), findsNothing);
    });
  });
}
