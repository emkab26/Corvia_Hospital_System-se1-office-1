import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/patient/contact_details_editor.dart';
import 'package:mycorvia/pages/patient/profile.dart';

/// Stands in for the patient dashboard: the editor wired the way ProfilePage
/// wires it, plus a "Home" control that switches tabs the way the dashboard
/// does, through confirmLeaveProfile.
class _Host extends StatefulWidget {
  const _Host({this.save});
  final Future<bool> Function()? save;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool onProfile = true;
  String address = '123 Takalani Road';
  String phone = '082 123 4567';

  @override
  void dispose() {
    profilePageHasChangesNotifier.value = false;
    profilePageIsSavingNotifier.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Offstage(
            offstage: !onProfile,
            child: ContactDetailsEditor(
              address: address,
              phone: phone,
              onSave: (nextAddress, nextPhone) async {
                final result =
                    await (widget.save?.call() ?? Future.value(true));
                if (result && mounted) {
                  setState(() {
                    address = nextAddress;
                    phone = nextPhone;
                  });
                }
                return result;
              },
              onDirtyChanged: (dirty) =>
                  profilePageHasChangesNotifier.value = dirty,
              onSavingChanged: (saving) =>
                  profilePageIsSavingNotifier.value = saving,
              discardSignal: profileLeaveSignal,
            ),
          ),
          TextButton(
            onPressed: () async {
              if (await confirmLeaveProfile(context)) {
                setState(() => onProfile = false);
              }
            },
            child: const Text('Home'),
          ),
          TextButton(
            onPressed: () => setState(() => onProfile = true),
            child: const Text('Profile'),
          ),
        ],
      ),
    );
  }
}

Future<void> _editAddress(WidgetTester tester, String text) async {
  await tester.tap(find.text('Edit details'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Address'), text);
  await tester.pump();
}

void main() {
  setUp(() {
    profilePageHasChangesNotifier.value = false;
    profilePageIsSavingNotifier.value = false;
  });

  for (final saved in [false, true]) {
    testWidgets(
        'leaving waits for a pending ${saved ? 'successful' : 'failed'} save without clearing the draft flag',
        (tester) async {
      final pending = Completer<bool>();
      await tester
          .pumpWidget(MaterialApp(home: _Host(save: () => pending.future)));
      await _editAddress(tester, 'QA UNSAVED ROAD');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(profilePageIsSavingNotifier.value, isTrue);

      await tester.tap(find.text('Home'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state<_HostState>(find.byType(_Host)).onProfile, isTrue);
      expect(find.text('Unsaved Changes'), findsNothing);
      expect(profilePageHasChangesNotifier.value, isTrue);

      pending.complete(saved);
      await tester.pumpAndSettle();
      expect(profilePageIsSavingNotifier.value, isFalse);
      expect(profilePageHasChangesNotifier.value, !saved);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      if (saved) {
        expect(tester.state<_HostState>(find.byType(_Host)).onProfile, isFalse);
        expect(find.text('Unsaved Changes'), findsNothing);
      } else {
        expect(find.text('Unsaved Changes'), findsOneWidget);
        await tester.tap(find.text('Stay'));
        await tester.pumpAndSettle();
        expect(find.text('QA UNSAVED ROAD'), findsOneWidget);
      }
    });
  }

  testWidgets(
      'leaving with unsaved changes asks first, and Stay keeps the edit',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await _editAddress(tester, 'QA UNSAVED ROAD');

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved Changes'), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    expect(tester.state<_HostState>(find.byType(_Host)).onProfile, isTrue);
    expect(find.text('QA UNSAVED ROAD'), findsOneWidget);
    expect(profilePageHasChangesNotifier.value, isTrue);
  });

  testWidgets(
      'Discard leaves and the form is back to the saved values next time',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await _editAddress(tester, 'QA UNSAVED ROAD');

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(tester.state<_HostState>(find.byType(_Host)).onProfile, isFalse);
    expect(profilePageHasChangesNotifier.value, isFalse);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing,
        reason: 'edit mode must not survive leaving the tab');
    expect(find.text('123 Takalani Road'), findsOneWidget);
    expect(find.text('QA UNSAVED ROAD'), findsNothing);
  });

  testWidgets(
      'leaving edit mode with no changes does not ask, and closes the editor',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved Changes'), findsNothing);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Edit details'), findsOneWidget);
  });
}
