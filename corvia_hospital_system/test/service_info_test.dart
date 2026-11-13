import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mycorvia/service_info.dart';
import 'package:mycorvia/service_place.dart';

void main() {
  testWidgets('shows full service info when all fields are present', (WidgetTester tester) async {
    final place = ServicePlace(
      id: '1',
      location: LatLng(10.0, 20.0),
      name: 'Health Center',
      type: 'clinic',
      hours: '8AM - 5PM',
      phone: '+1 234 567 8900',
      website: 'https://example.com',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () => showServiceInfo(context, place),
                child: const Text('Show Service Info'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Service Info'));
    await tester.pumpAndSettle();

    expect(find.text('Health Center'), findsOneWidget);
    expect(find.text('Type: Clinic / health centre'), findsOneWidget);
    expect(find.text('Opening Hours: 8AM - 5PM'), findsOneWidget);
    expect(find.text('Phone: +1 234 567 8900'), findsOneWidget);
    expect(find.text('Website: https://example.com'), findsOneWidget);
    expect(find.text('No additional details available'), findsNothing);
    expect(find.widgetWithIcon(ElevatedButton, Icons.navigation), findsOneWidget);
  });

  testWidgets('shows fallback text when optional fields are missing', (WidgetTester tester) async {
    final place = ServicePlace(
      id: '2',
      location: LatLng(10.0, 20.0),
      name: 'Basic Clinic',
      type: 'pharmacy',
      hours: null,
      phone: null,
      website: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () => showServiceInfo(context, place),
                child: const Text('Show Service Info'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Service Info'));
    await tester.pumpAndSettle();

    expect(find.text('Basic Clinic'), findsOneWidget);
    expect(find.text('Type: Pharmacy'), findsOneWidget);
    expect(find.text('Opening Hours:'), findsNothing);
    expect(find.text('Phone:'), findsNothing);
    expect(find.text('Website:'), findsNothing);
    expect(find.text('No additional details available'), findsOneWidget);
    expect(find.widgetWithIcon(ElevatedButton, Icons.navigation), findsOneWidget);
  });
}
