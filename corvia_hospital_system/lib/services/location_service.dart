import 'package:geolocator/geolocator.dart';

/// Thin wrapper around `geolocator` so the rest of the app does not have to
/// know about service-enable / permission flows.
class LocationService {
  /// Returns the user's current position, or null if location is
  /// unavailable, denied, or service is off. Never throws.
  static Future<Position?> currentPosition({
    LocationAccuracy accuracy = LocationAccuracy.medium,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeout,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Distance in metres between two lat/lng points (Haversine). Returns
  /// `double.infinity` if either input is null.
  static double distanceMeters({
    required double? aLat,
    required double? aLng,
    required double? bLat,
    required double? bLng,
  }) {
    if (aLat == null || aLng == null || bLat == null || bLng == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(aLat, aLng, bLat, bLng);
  }

  /// Friendly label for a distance in metres.
  /// Returns "Location unavailable" if the distance could not be computed.
  static String formatDistance(double meters) {
    if (meters.isInfinite || meters.isNaN) return 'Location unavailable';
    if (meters < 1000) return '${meters.round()} m away';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km away';
  }

  /// Convenience method: computes distance and returns a ready-to-display
  /// label, handling the "no current position" case as well.
  /// Safe fallback for every failure mode — never null, never throws.
  static String distanceLabel({
    required Position? userPosition,
    required double? targetLat,
    required double? targetLng,
  }) {
    if (userPosition == null) return 'Location unavailable';

    final meters = distanceMeters(
      aLat: userPosition.latitude,
      aLng: userPosition.longitude,
      bLat: targetLat,
      bLng: targetLng,
    );

    return formatDistance(meters);
  }
}
