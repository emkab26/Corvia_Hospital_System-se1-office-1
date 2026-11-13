import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:mycorvia/maptiler_map_screen_state.dart';
import 'package:mycorvia/service_place.dart';

/// A mock HTTP client that returns a valid, blank 1x1 transparent image 
/// whenever the Map Tile Layer attempts to fetch map graphics from the web.
class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
  
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientResponse implements HttpClientResponse {
  static const _transparentImage =
      'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

  @override
  int get statusCode => 200;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable([base64Decode(_transparentImage)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final mockUserLocation = LatLng(-25.747, 28.229);

  setUpAll(() {
    dotenv.loadFromString(envString: '''
      MAPTILER_KEY=test-key
    ''');

    HttpOverrides.global = TestHttpOverrides();
  });

  group('MapTilerMapScreen Widget Tests', () {

    testWidgets('Shows Location Denied screen when location is unavailable', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MapTilerMapScreen(
            positionProvider: () async => null,
            servicesProvider: ({required lat, required lon, required radius}) async => [],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Location access needed'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('Shows bottom warning card when map is loaded but zero services are found', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MapTilerMapScreen(
            positionProvider: () async => mockUserLocation,
            servicesProvider: ({required lat, required lon, required radius}) async => [],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(
        find.text('No clinics, hospitals, or pharmacies were found within 5 km of your location.'),
        findsOneWidget,
      );
    });

    testWidgets('Displays the correct service count badge and markers when mock services are found', (WidgetTester tester) async {
      final mockServicesList = [
        ServicePlace(
          id: 'osm-node-123',
          name: 'Corvia Central Hospital',
          type: 'hospital',
          location: LatLng(-25.748, 28.230),
        ),
        ServicePlace(
          id: 'osm-node-456',
          name: 'St. Jude Pharmacy',
          type: 'pharmacy',
          location: LatLng(-25.746, 28.228),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MapTilerMapScreen(
            positionProvider: () async => mockUserLocation,
            servicesProvider: ({required lat, required lon, required radius}) async => mockServicesList,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the map and top badge container state
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('2 nearby services'), findsOneWidget);

      // Verify specific map icons are rendered (Hospital and Medication icons)
      expect(find.byIcon(Icons.local_hospital), findsOneWidget);
      expect(find.byIcon(Icons.medication), findsOneWidget);
    });

    testWidgets('Shows error screen when services provider throws an exception', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MapTilerMapScreen(
            positionProvider: () async => mockUserLocation,
            servicesProvider: ({required lat, required lon, required radius}) async {
              throw Exception('Overpass API server timeout');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Asserts that the StatusView.error friendly message is rendered
      expect(find.text("We couldn't reach the nearby-services service."), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

  });
}