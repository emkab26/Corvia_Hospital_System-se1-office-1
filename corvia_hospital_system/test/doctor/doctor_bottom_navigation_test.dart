import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/doctor/doctor_bottom_navigation.dart';

/// The Flutter SDK ships Roboto, the font the app renders with on Android and
/// web. The default test font has one-em-wide glyphs, which says nothing about
/// whether a real label fits.
String _materialFontsDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    final fonts = Directory('${dir.path}/bin/cache/artifacts/material_fonts');
    if (fonts.existsSync()) return fonts.path;
    dir = dir.parent;
  }
  throw StateError('Flutter material_fonts directory not found');
}

const _labels = ['Home', 'Appts', 'Patients', 'Meds', 'Labs'];

void main() {
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    for (final file in ['roboto-regular.ttf', 'roboto-medium.ttf']) {
      final bytes = File('${_materialFontsDir()}/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  Future<void> pumpBar(WidgetTester tester, double width, double textScale) async {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            bottomNavigationBar: DoctorBottomNavigation(selectedIndex: 3, onDestinationSelected: (_) {}),
          ),
        ),
      ),
    );
  }

  for (final width in [320.0, 360.0, 412.0]) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets('every label stays on one line at $width px, text scale $textScale', (tester) async {
        await pumpBar(tester, width, textScale);

        // A label that wraps is twice as tall as one that does not, and
        // "Home" is too short to wrap at any of these widths.
        final singleLine = tester.renderObject<RenderParagraph>(find.text('Home')).size.height;
        for (final label in _labels) {
          final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
          expect(paragraph.size.height, singleLine, reason: '"$label" wrapped');
          expect(paragraph.text.style?.fontSize, greaterThanOrEqualTo(11), reason: '"$label" shrank below a readable size');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('full tab names are the tooltips', (tester) async {
    await pumpBar(tester, 360, 1);

    for (final name in ['Appointments', 'Prescriptions', 'Lab orders']) {
      expect(find.byTooltip(name), findsOneWidget);
    }
  });

  testWidgets('tapping a tab reports its index', (tester) async {
    int? tapped;
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: DoctorBottomNavigation(selectedIndex: 0, onDestinationSelected: (i) => tapped = i),
        ),
      ),
    );

    await tester.tap(find.text('Meds'));
    expect(tapped, 3);
  });
}
