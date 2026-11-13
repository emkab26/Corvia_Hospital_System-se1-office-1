import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// Handles getting GPS location and permissions
Future<LatLng?> determineCurrentPosition() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  // If GPS is off, it opens the phone’s location settings
  if (!serviceEnabled) {
    await Geolocator.openLocationSettings();
    // Returns null because the app cannot fetch a location
    return null;
  }
  // Checks if the user has already granted permission
  LocationPermission permission = await Geolocator.checkPermission();
  // If the user denied it once, ask again
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    // If they deny again then return null
    if (permission == LocationPermission.denied) return null;
  }
  // This means the user hit “Don’t ask again”. you cannot request permission anymore and return null
  if (permission == LocationPermission.deniedForever) return null;
  // This gets the phone’s real-time GPS location
  Position pos = await Geolocator.getCurrentPosition();
  return LatLng(pos.latitude, pos.longitude);
}
