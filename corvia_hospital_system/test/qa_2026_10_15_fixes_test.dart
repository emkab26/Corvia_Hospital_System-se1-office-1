import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mycorvia/widgets/corvia_scanner.dart';
import 'package:mycorvia/widgets/nav_label_fit.dart';
import 'package:mycorvia/widgets/text_controller_scope.dart';

Future<BuildContext> _host(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          context = c;
          return const Scaffold();
        },
      ),
    ),
  );
  return context;
}

Future<String?> _openNotesDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => TextControllerScope(
      initialText: 'existing note',
      builder: (controller) => AlertDialog(
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('TextControllerScope (#230, #232, #233, #235)', () {
    testWidgets('cancelling a dialog does not throw while it animates out', (tester) async {
      final context = await _host(tester);
      final result = _openNotesDialog(context);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'CORVIA_CHECKIN|x');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(await result, isNull);
    });

    testWidgets('returns the edited text and starts from initialText', (tester) async {
      final context = await _host(tester);
      final result = _openNotesDialog(context);
      await tester.pumpAndSettle();

      expect(find.text('existing note'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Arrived early');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(await result, 'Arrived early');
    });
  });

  group('fitNavigationLabelFontSize (#226, #228)', () {
    // flutter_test lays text out in its own font where every glyph is one em
    // wide, so a label of n characters at size s and scale k is n * s * k px.
    // "Prescriptions" (13 characters) is the longest label.
    const labels = ['Home', 'Appointments', 'Patients', 'Prescriptions', 'Labs'];
    const base = TextStyle(fontSize: 12);

    double fit(double slotWidth, {double scale = 1}) => fitNavigationLabelFontSize(
          labels: labels,
          baseStyle: base,
          slotWidth: slotWidth,
          textScaler: TextScaler.linear(scale),
        );

    test('keeps the base size when the longest label already fits', () {
      expect(fit(13 * 12), 12);
    });

    test('shrinks to the largest half-step size at which the longest label fits', () {
      expect(fit(13 * 10), 10);
      expect(fit(13 * 10 - 1), 9.5);
    });

    test('accounts for the text scale', () {
      expect(fit(13 * 10 * 1.3, scale: 1.3), 10);
    });

    test('stops at the minimum when nothing fits', () {
      expect(fit(10), 9);
    });
  });

  group('ScannerErrorView (#229)', () {
    Future<void> pump(WidgetTester tester, MobileScannerException error, Future<void> Function() onRetry) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ScannerErrorView(error: error, onRetry: onRetry),
            ),
          ),
        ),
      );
    }

    testWidgets('permission denied shows plain text inside the scan frame and retries', (tester) async {
      var retries = 0;
      await pump(
        tester,
        const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied,
          errorDetails: MobileScannerErrorDetails(message: 'NotAllowedError: Permission dismissed'),
        ),
        () async => retries++,
      );

      expect(find.textContaining('NotAllowedError'), findsNothing);
      final message = find.textContaining('Camera access is blocked');
      expect(message, findsOneWidget);
      expect(tester.getSize(message).width, lessThanOrEqualTo(ScannerErrorView.maxTextWidth));

      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('unsupported camera offers no retry', (tester) async {
      await pump(
        tester,
        const MobileScannerException(errorCode: MobileScannerErrorCode.unsupported),
        () async {},
      );

      expect(find.textContaining('no camera'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });
}
