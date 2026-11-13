import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/widgets/input_device_button.dart';

void main() {
  testWidgets('starts at Default, selects a device, and can restore Default',
      (tester) async {
    var selected = '';
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
                  body: InputDeviceButton(
                      label: 'microphone',
                      selectedId: selected,
                      loadDevices: () async =>
                          [const InputDevice('usb', 'USB microphone')],
                      onSelected: (id) async => setState(() => selected = id)),
                ))));
    await tester.tap(find.byTooltip('Select microphone'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Default'), findsOneWidget);
    expect(
        find.descendant(
            of: find.widgetWithText(ListTile, 'Default'),
            matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget);
    await tester.tap(find.text('USB microphone'));
    await tester.pumpAndSettle();
    expect(selected, 'usb');
    await tester.tap(find.byTooltip('Select microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();
    expect(selected, '');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('failed selection stays open and Cancel makes no change',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InputDeviceButton(
      label: 'camera',
      selectedId: 'missing',
      loadDevices: () async => [const InputDevice('usb', 'USB camera')],
      onSelected: (_) async => throw StateError('disconnected'),
    ))));
    await tester.tap(find.byTooltip('Select camera'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('selected device is unavailable'), findsOneWidget);
    await tester.tap(find.text('USB camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not use that device'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('enumeration failure can be refreshed', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InputDeviceButton(
      label: 'camera',
      loadDevices: () async {
        if (attempts++ == 0) throw StateError('unavailable');
        return [const InputDevice('usb', 'USB camera')];
      },
      onSelected: (_) async {},
    ))));
    await tester.tap(find.byTooltip('Select camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not list devices'), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('USB camera'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
