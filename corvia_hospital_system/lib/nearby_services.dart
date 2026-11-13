// Overpass API service - fetches nearby healthcare and emergency places.
// HTTP 406 fix: explicit Content-Type, Accept, and User-Agent headers added.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'service_place.dart';

/// Public Overpass API mirrors, tried in order. The kumi mirror is usually
/// the fastest and least rate-limited; the main `overpass-api.de` host is
/// the official fallback. We POST the query body (the GET URL grows long
/// enough to hit URL-length issues on some networks).
const _overpassEndpoints = <String>[
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass-api.de/api/interpreter',
  'https://lz4.overpass-api.de/api/interpreter',
];

/// Fetch hospitals, clinics, doctors, pharmacies, and fire stations around
/// [lat] / [lon] within [radius] metres via the Overpass API.
Future<List<ServicePlace>> fetchNearbyServices({
  required double lat,
  required double lon,
  required double radius,
}) async {
  // [timeout:90] tells the Overpass server to give up after 90 s - keeps
  // the call bounded even when its load is high. Increased from 25 s to
  // match the expanded 30 km search radius.
  // Many South African practices are tagged only with `healthcare=*`, and
  // chain pharmacies are often `shop=chemist`, so query all three schemes.
  const amenities =
      'hospital|clinic|doctors|dentist|pharmacy|fire_station|police';
  const healthcare = 'hospital|clinic|centre|doctor|dentist|pharmacy|'
      'laboratory|physiotherapist|optometrist|blood_donation';
  final around = '(around:$radius,$lat,$lon)';
  final query = '''
[out:json][timeout:90];
(
  nwr["amenity"~"^($amenities)\$"]$around;
  nwr["healthcare"~"^($healthcare)\$"]$around;
  nwr["emergency"="ambulance_station"]$around;
  nwr["shop"="chemist"]$around;
);
out center;
''';

  http.Response? response;
  Object? lastError;

  final distance = Distance();
  final resultsWithDistance = <_PlaceWithDistance>[];
  final seen = <String>{};

  for (final endpoint in _overpassEndpoints) {
    try {
      final r = await http.post(
        Uri.parse(endpoint),
        // Explicit headers required by Overpass.
        // Without Content-Type the server returns HTTP 406 Not Acceptable.
        // User-Agent is required by Overpass usage policy.
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          'User-Agent': 'MyCorvia/1.0 (corvia.co.za healthcare app)',
        },
        body: {'data': query},
      ).timeout(const Duration(seconds: 30));

      if (r.statusCode == 200) {
        response = r;
        break;
      }

      lastError = 'HTTP ${r.statusCode} from $endpoint';
    } catch (e) {
      lastError = '$endpoint → $e';
    }
  }

  if (response == null) {
    throw Exception(
      'All Overpass mirrors failed. Last error: ${lastError ?? "unknown"}',
    );
  }

  final data = jsonDecode(response.body);
  final elements = (data['elements'] as List?) ?? const [];

  for (final element in elements) {
    final tags = (element['tags'] as Map?) ?? const {};

    // For node elements OSM puts lat/lon at the top level; for way/relation
    // elements with `out center;` the centroid sits under `center`. Accept
    // both, and parse defensively in case the API returns ints.
    final num? rawLat = element['lat'] ?? element['center']?['lat'];
    final num? rawLon = element['lon'] ?? element['center']?['lon'];

    if (rawLat == null || rawLon == null) continue;

    final distMeters = distance.as(
      LengthUnit.Meter,
      LatLng(lat, lon),
      LatLng(rawLat.toDouble(), rawLon.toDouble()),
    );

    final place = ServicePlace(
      id: element['id'].toString(),
      name: tags['name'] as String?,
      type: _serviceType(tags),
      hours: tags['opening_hours'] as String?,
      phone: (tags['phone'] ?? tags['contact:phone']) as String?,
      website: (tags['website'] ?? tags['contact:website']) as String?,
      location: LatLng(rawLat.toDouble(), rawLon.toDouble()),
      distanceMeters: distMeters,
    );

    final key = '${element['type']}/${element['id']}';
    if (!seen.add(key)) continue;

    resultsWithDistance.add(_PlaceWithDistance(place, distMeters));
  }

  resultsWithDistance
      .sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

  return resultsWithDistance.map((e) => e.place).toList();
}

/// Maps OSM tagging schemes onto the marker types the map understands.
String? _serviceType(Map tags) {
  final amenity = tags['amenity']?.toString();
  if (amenity != null && amenity.isNotEmpty) return amenity;

  if (tags['emergency'] == 'ambulance_station') return 'ambulance_station';
  if (tags['shop'] == 'chemist') return 'pharmacy';

  switch (tags['healthcare']?.toString()) {
    case 'doctor':
      return 'doctors';
    case 'centre':
    case 'laboratory':
    case 'physiotherapist':
    case 'optometrist':
    case 'blood_donation':
      return 'clinic';
    case final String value when value.isNotEmpty:
      return value;
  }
  return null;
}

class _PlaceWithDistance {
  final ServicePlace place;
  final double distanceMeters;

  _PlaceWithDistance(this.place, this.distanceMeters);
}
