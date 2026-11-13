import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/patient/contact_details_editor.dart';

class _Harness {
  final saves = <(String, String)>[];
  final dirtyEvents = <bool>[];
  Completer<bool>? pendingSave;

  Widget build(
      {String address = '12 Long Street', String phone = '082 123 4567'}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ContactDetailsEditor(
            address: address,
            phone: phone,
            onSave: (a, p) {
              saves.add((a, p));
              return (pendingSave = Completer<bool>()).future;
            },
            onDirtyChanged: dirtyEvents.add,
          ),
        ),
      ),
    );
  }
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  testWidgets('shows saved details read-only with no text fields',
      (tester) async {
    await tester.pumpWidget(_Harness().build());

    expect(find.text('12 Long Street'), findsOneWidget);
    expect(find.text('082 123 4567'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Edit details'), findsOneWidget);
  });

  testWidgets('labels missing details instead of showing blanks',
      (tester) async {
    await tester.pumpWidget(_Harness().build(address: '', phone: ''));

    expect(find.text('Not provided'), findsNWidgets(2));
  });

  testWidgets('Save stays disabled until a field changes', (tester) async {
    await tester.pumpWidget(_Harness().build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();

    FilledButton saveButton() => tester.widget<FilledButton>(find.ancestor(
        of: find.text('Save'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(saveButton().onPressed, isNull);

    await tester.enterText(_field('Address'), '14 Long Street');
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('Cancel restores the saved values and leaves edit mode',
      (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();

    await tester.enterText(_field('Address'), 'typed by accident');
    await tester.pump();
    expect(h.dirtyEvents, [true]);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('12 Long Street'), findsOneWidget);
    expect(h.dirtyEvents, [true, false]);
    expect(h.saves, isEmpty);

    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    expect(find.text('12 Long Street'), findsOneWidget,
        reason: 'the discarded edit must not reappear');
  });

  testWidgets('a successful save leaves edit mode', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Phone Number'), '0831112222');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    expect(h.saves.single, ('12 Long Street', '083 111 2222'));

    h.pendingSave!.complete(true);
    await tester.pumpWidget(h.build(phone: '083 111 2222'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('083 111 2222'), findsOneWidget);
  });

  testWidgets('a failed save keeps the edit so nothing typed is lost',
      (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Address'), '14 Long Street');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    h.pendingSave!.complete(false);
    await tester.pumpAndSettle();

    expect(_field('Address'), findsOneWidget);
    expect(find.text('14 Long Street'), findsOneWidget);
  });

  testWidgets('fields stay locked until the pending save finishes',
      (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Address'), '14 Long Street');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(tester.widget<TextFormField>(_field('Address')).enabled, isFalse);
    expect(
        tester.widget<TextFormField>(_field('Phone Number')).enabled, isFalse);
    expect(h.saves, [('14 Long Street', '082 123 4567')]);

    h.pendingSave!.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(_field('Address')).enabled, isTrue);
    expect(
        tester.widget<TextFormField>(_field('Phone Number')).enabled, isTrue);
    expect(find.text('14 Long Street'), findsOneWidget);
    expect(h.dirtyEvents, [true]);
  });

  testWidgets(
      'a trimmed no-op save resets fields and disables Save when reopened',
      (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Address'), '12 Long Street ');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(h.saves, [('12 Long Street', '082 123 4567')]);
    h.pendingSave!.complete(true);
    await tester.pumpAndSettle();
    expect(h.dirtyEvents, [true, false]);

    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(_field('Address')).controller!.text,
        '12 Long Street');
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull);
  });

  testWidgets('two Save callbacks before a rebuild send only one request',
      (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Address'), '14 Long Street');
    await tester.pump();
    final save = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
        .onPressed!;
    save();
    save();
    await tester.pump();
    expect(h.saves, hasLength(1));
    h.pendingSave!.complete(false);
    await tester.pumpAndSettle();
  });

  testWidgets('an invalid phone number is not saved', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();

    await tester.enterText(_field('Phone Number'), '12');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(h.saves, isEmpty);
  });

  testWidgets('Ctrl+Z restores a cleared phone number', (tester) async {
    await tester.pumpWidget(_Harness().build());
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();

    await tester.tap(_field('Phone Number'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(_field('Phone Number'), '');
    await tester.pump(const Duration(milliseconds: 600));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.text('082 123 4567'), findsOneWidget);
  },
      variant: const TargetPlatformVariant(
          <TargetPlatform>{TargetPlatform.windows, TargetPlatform.android}));
}
