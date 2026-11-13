import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/patient/scan_qr_code.dart';
import 'package:mycorvia/services/qr_scanner_service.dart';

class MockQrScannerService implements QrScannerService {
  void Function(QrScanResult)? _onResult;
  void Function(String)? _onUnknown;

  bool torchToggled = false;
  bool cameraSwitched = false;
  bool disposed = false;

  void simulateScan(String raw) {
    final resolver = const QrRouteResolver();
    final result = resolver.resolve(raw);
    if (result != null) {
      _onResult?.call(result);
    } else {
      _onUnknown?.call(raw);
    }
  }

  @override
  Widget buildScanner({
    required void Function(QrScanResult result) onResult,
    required void Function(String raw) onUnknown,
    void Function(bool granted)? onPermissionSet,
  }) {
    _onResult = onResult;
    _onUnknown = onUnknown;
    // Return a plain placeholder — no real camera widget needed in tests.
    return const SizedBox.expand(key: Key('mock_scanner_view'));
  }

  @override
  void toggleTorch() => torchToggled = true;

  @override
  void switchCamera() => cameraSwitched = true;

  @override
  void dispose() => disposed = true;

  bool _hasCameraValue = true;

  void setHasCamera(bool value) => _hasCameraValue = value;

  @override
  Future<bool> hasCamera() async => _hasCameraValue;
}

Widget _buildTestApp(
  MockQrScannerService service, {
  required List<String> pushedRoutes,
  required List<Map<String, String>?> pushedArgs,
}) {
  return MaterialApp(
    onGenerateRoute: (settings) {
      pushedRoutes.add(settings.name ?? '');
      pushedArgs.add(settings.arguments as Map<String, String>?);
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => Scaffold(
          body: Center(child: Text('Destination: ${settings.name}')),
        ),
      );
    },
    home: ScanQrCodePage(scannerService: service),
  );
}

Future<void> _startScanner(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.text('Enable Camera'), findsOneWidget);
  await tester.tap(find.text('Enable Camera'));
  await tester.pumpAndSettle();
}

void main() {
  group('QrRouteResolver', () {
    const resolver = QrRouteResolver();

    test('resolves CORVIA_CHECKIN to /dashboard', () {
      final result = resolver
          .resolve('CORVIA_CHECKIN|patient_id=abc123|appointment_id=appt456');
      expect(result, isNotNull);
      expect(result!.route, '/dashboard');
      expect(result.params['patient_id'], 'abc123');
      expect(result.params['appointment_id'], 'appt456');
    });

    test('resolves CORVIA_DOCTOR to /patient-records', () {
      final result = resolver.resolve('CORVIA_DOCTOR|doctor_id=doc789');
      expect(result, isNotNull);
      expect(result!.route, '/patient-records');
      expect(result.params['doctor_id'], 'doc789');
    });

    test('resolves CORVIA_EMERGENCY to /emergency', () {
      final result = resolver.resolve('CORVIA_EMERGENCY|patient_id=abc123');
      expect(result, isNotNull);
      expect(result!.route, '/emergency');
    });

    test('resolves CORVIA_PATIENT to /profile', () {
      final result = resolver.resolve('CORVIA_PATIENT|patient_id=p001');
      expect(result, isNotNull);
      expect(result!.route, '/profile');
    });

    test('returns null for unknown prefix', () {
      final result = resolver.resolve('UNKNOWN_CODE|data=xyz');
      expect(result, isNull);
    });

    test('returns null for empty string', () {
      final result = resolver.resolve('');
      expect(result, isNull);
    });
  });

  group('ScanQrCodePage navigation', () {
    late MockQrScannerService mockService;
    late List<String> pushedRoutes;
    late List<Map<String, String>?> pushedArgs;

    setUp(() {
      mockService = MockQrScannerService();
      pushedRoutes = [];
      pushedArgs = [];
    });

    testWidgets(
        'shows camera check loading then scanner view when camera is available',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );

      // Initially should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Checking camera availability...'), findsOneWidget);

      await _startScanner(tester);

      expect(find.byKey(const Key('mock_scanner_view')), findsOneWidget);
      expect(
          find.text('Point your camera at a Corvia QR code.'), findsOneWidget);
    });

    testWidgets('CORVIA_CHECKIN scan navigates to /dashboard with params',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);

      mockService.simulateScan(
          'CORVIA_CHECKIN|patient_id=abc123|appointment_id=appt456');
      await tester.pumpAndSettle();

      expect(pushedRoutes, contains('/dashboard'));
      expect(pushedArgs.last?['patient_id'], 'abc123');
      expect(pushedArgs.last?['appointment_id'], 'appt456');
      expect(find.text('Destination: /dashboard'), findsOneWidget);
    });

    testWidgets('CORVIA_DOCTOR scan navigates to /patient-records',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);

      mockService.simulateScan('CORVIA_DOCTOR|doctor_id=doc789');
      await tester.pumpAndSettle();

      expect(pushedRoutes, contains('/patient-records'));
      expect(find.text('Destination: /patient-records'), findsOneWidget);
    });

    testWidgets('CORVIA_EMERGENCY scan navigates to /emergency',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);

      mockService.simulateScan('CORVIA_EMERGENCY|patient_id=abc123');
      await tester.pumpAndSettle();

      expect(pushedRoutes, contains('/emergency'));
      expect(find.text('Destination: /emergency'), findsOneWidget);
    });

    testWidgets('CORVIA_PATIENT scan navigates to /profile', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);

      mockService.simulateScan('CORVIA_PATIENT|patient_id=p001');
      await tester.pumpAndSettle();

      expect(pushedRoutes, contains('/profile'));
      expect(find.text('Destination: /profile'), findsOneWidget);
    });

    testWidgets('unknown QR payload shows bottom sheet instead of navigating',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);

      mockService.simulateScan('NOT_A_CORVIA_CODE');
      await tester.pumpAndSettle();

      expect(pushedRoutes, isEmpty);
      // Bottom sheet should appear with the raw code
      expect(find.text('QR Code Scanned'), findsOneWidget);
      expect(find.text('NOT_A_CORVIA_CODE'), findsOneWidget);
    });

    testWidgets(
        'second scan is ignored while first is being handled (debounce)',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);

      mockService.simulateScan('CORVIA_CHECKIN|patient_id=first');
      mockService.simulateScan('CORVIA_CHECKIN|patient_id=second');
      await tester.pumpAndSettle();

      // Only the first scan should have triggered navigation
      expect(pushedRoutes.where((r) => r == '/dashboard').length, 1);
      expect(pushedArgs.first?['patient_id'], 'first');
    });

    testWidgets('torch button calls toggleTorch on service', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);

      await tester.tap(find.byTooltip('Flash'));
      await tester.pump();

      expect(mockService.torchToggled, isTrue);
    });

    testWidgets('switch camera button calls switchCamera on service',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);

      await tester.tap(find.byTooltip('Switch camera'));
      await tester.pump();

      expect(mockService.cameraSwitched, isTrue);
    });

    testWidgets('service is disposed when page is removed', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await _startScanner(tester);
      // Replace the app with an empty widget to trigger dispose
      await tester.pumpWidget(const SizedBox.shrink());

      expect(mockService.disposed, isTrue);
    });

    testWidgets('shows no camera state when camera is unavailable',
        (tester) async {
      mockService.setHasCamera(false);

      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );

      // Initially shows loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // After camera check completes with false
      await tester.pumpAndSettle();

      // Should show no camera message
      expect(find.text('No Camera Available'), findsOneWidget);
      expect(find.text('Check Again'), findsOneWidget);
      // Scanner should not be shown
      expect(find.byKey(const Key('mock_scanner_view')), findsNothing);
    });

    testWidgets('check again button retries camera availability',
        (tester) async {
      mockService.setHasCamera(false);

      await tester.pumpWidget(
        _buildTestApp(mockService,
            pushedRoutes: pushedRoutes, pushedArgs: pushedArgs),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Camera Available'), findsOneWidget);

      // Now set camera available and tap "Check Again"
      mockService.setHasCamera(true);
      await tester.tap(find.text('Check Again'));
      await tester.pumpAndSettle();

      expect(find.text('Enable Camera'), findsOneWidget);
      await tester.tap(find.text('Enable Camera'));
      await tester.pumpAndSettle();

      // Should now show the scanner after permission is requested.
      expect(find.byKey(const Key('mock_scanner_view')), findsOneWidget);
      expect(
          find.text('Point your camera at a Corvia QR code.'), findsOneWidget);
    });
  });
}
