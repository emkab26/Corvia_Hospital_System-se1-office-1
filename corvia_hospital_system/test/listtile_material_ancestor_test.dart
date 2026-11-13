import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The framework complains when a coloured `DecoratedBox`/`ColoredBox` sits
/// between a ListTile-family widget and its nearest `Material`, because the tile
/// paints its fill and ink onto that Material and the box hides them. It only
/// checks tiles that have something to paint - `onTap`, `onLongPress`, or an
/// opaque tile colour - which is why an inert tile in the same card is fine.
///
/// These tests pin the shape of the fix rather than any one screen: several
/// pages wrap interactive tiles in coloured "card" Containers, and a transparent
/// Material restores the ancestor without painting anything itself.
Widget _card({required Widget child}) => Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B263B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );

void main() {
  testWidgets('a coloured container around a tappable tile trips the framework',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _card(
            child: ListTile(title: const Text('Unprotected'), onTap: () {}),
          ),
        ),
      ),
    );

    // Guards the premise. If this ever stops throwing, the framework check has
    // changed and the Material wrappers below can be revisited.
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('an inert tile in the same card is not affected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _card(child: const ListTile(title: Text('Inert'))),
        ),
      ),
    );

    // No onTap and no opaque tile colour means the tile has nothing to paint,
    // so the framework never runs the check. Wrapping tiles like this one would
    // be noise.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a transparent Material restores the tile ancestor',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _card(
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(title: const Text('Protected'), onTap: () {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Protected'), findsOneWidget);
  });

  testWidgets('the transparent Material does not paint over the card colour',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _card(
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(title: const Text('Protected'), onTap: () {}),
            ),
          ),
        ),
      ),
    );

    // MaterialType.transparency draws no background, so the card's colour is
    // still the thing on screen. This is why the fix is visually a no-op.
    final material = tester.widget<Material>(
      find.byType(Material).last,
    );
    expect(material.color, isNull);
    expect(material.type, MaterialType.transparency);
  });

  testWidgets('ExpansionTile is affected, and the wrapper fixes it',
      (tester) async {
    // ExpansionTile builds a ListTile with an onTap for the expand handle, so
    // it is always subject to the check. This is the my_prescriptions case.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _card(child: const ExpansionTile(title: Text('Section'))),
        ),
      ),
    );
    expect(tester.takeException(), isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _card(
            child: const Material(
              type: MaterialType.transparency,
              child: ExpansionTile(title: Text('Section')),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Section'), findsOneWidget);
  });

  testWidgets('SwitchListTile is affected, and the wrapper fixes it',
      (tester) async {
    // SwitchListTile forwards onChanged to the underlying ListTile's onTap.
    // This is the hospital_departments case.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _card(
            child: SwitchListTile(
              value: true,
              onChanged: (_) {},
              title: const Text('Toggle'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _card(
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                value: true,
                onChanged: (_) {},
                title: const Text('Toggle'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Toggle'), findsOneWidget);
  });

  testWidgets('a gradient-only container does not need the wrapper',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Colors.red, Colors.blue]),
            ),
            child: ListTile(title: const Text('Gradient'), onTap: () {}),
          ),
        ),
      ),
    );

    // The check reads BoxDecoration.color, which a gradient leaves null. Page
    // background gradients are therefore fine as they are.
    expect(tester.takeException(), isNull);
  });
}
