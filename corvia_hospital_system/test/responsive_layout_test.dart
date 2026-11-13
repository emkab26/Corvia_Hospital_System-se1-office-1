import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/responsive_layout.dart';

/// Reads a value out of [ResponsiveLayout] at a given viewport size.
Future<T> at<T>(
  WidgetTester tester,
  Size size,
  T Function(BuildContext context) read,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late T value;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          value = read(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return value;
}

void main() {
  group('getMainContentWidth', () {
    testWidgets('a phone gets the full width', (tester) async {
      final w = await at(tester, const Size(430, 932),
          ResponsiveLayout.getMainContentWidth);

      expect(w, 430);
    });

    testWidgets('a tablet gets most of the width', (tester) async {
      final w = await at(tester, const Size(900, 1200),
          ResponsiveLayout.getMainContentWidth);

      expect(w, closeTo(900 * 0.8, 0.01));
    });

    testWidgets('a modest desktop is unchanged by the cap', (tester) async {
      // 1400 * 0.7 = 980, still under the ceiling, so the proportion wins.
      final w = await at(tester, const Size(1400, 900),
          ResponsiveLayout.getMainContentWidth);

      expect(w, closeTo(980, 0.01));
    });

    testWidgets('a wide monitor is capped', (tester) async {
      // 1920 * 0.7 = 1344, which is past the ceiling.
      final w = await at(tester, const Size(1920, 1080),
          ResponsiveLayout.getMainContentWidth);

      expect(w, ResponsiveLayout.maxContentWidth);
    });

    testWidgets('an ultrawide is capped to the same width', (tester) async {
      // The point of the cap: 3440 * 0.7 would be a 2408px line of text.
      final w = await at(tester, const Size(3440, 1440),
          ResponsiveLayout.getMainContentWidth);

      expect(w, ResponsiveLayout.maxContentWidth);
    });

    testWidgets('never returns more than the ceiling, at any width',
        (tester) async {
      for (final width in [320.0, 600.0, 900.0, 1200.0, 1715.0, 2560.0, 5120.0]) {
        final w = await at(tester, Size(width, 900),
            ResponsiveLayout.getMainContentWidth);

        expect(w, lessThanOrEqualTo(ResponsiveLayout.maxContentWidth),
            reason: 'at ${width}px wide');
      }
    });

    testWidgets('a phone never gets more than its own width', (tester) async {
      // The cap must not widen anything - min, not clamp.
      final w = await at(tester, const Size(320, 640),
          ResponsiveLayout.getMainContentWidth);

      expect(w, 320);
    });
  });

  group('breakpoints use the short side', () {
    testWidgets('a landscape phone is still a phone', (tester) async {
      // The regression that sank the responsive-padding-helper branch: judging
      // on raw width makes a rotated phone look like a tablet.
      final isMobile =
          await at(tester, const Size(932, 430), ResponsiveLayout.isMobile);

      expect(isMobile, isTrue);
    });

    testWidgets('a landscape phone gets phone padding', (tester) async {
      final padding =
          await at(tester, const Size(932, 430), ResponsiveLayout.getScreenPadding);

      expect(padding, const EdgeInsets.all(16));
    });
  });
}
