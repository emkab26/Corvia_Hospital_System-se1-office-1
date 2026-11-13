import 'package:latlong2/latlong.dart';

/// Represents a health or emergency service (e.g. hospital, clinic,
/// pharmacy, doctor, or fire station) fetched from the Overpass API.
class ServicePlace {
  final String id; // OSM element ID (node, way, or relation)
  final LatLng location; // Latitude & longitude for marker
  final String? name; // Name of the service
  final String? type; // OSM "amenity" type
  final String? hours; // Opening hours (if available)
  final String? phone; // Phone number (if available)
  final String? website; // Website (if available)

  // NEW
  final double? distanceMeters;

  ServicePlace({
    required this.id,
    required this.location,
    this.name,
    this.type,
    this.hours,
    this.phone,
    this.website,
    this.distanceMeters, // NEW
  });

  /// Converts OSM "amenity" codes into readable UI labels.
  String readableType() {
    switch (type) {
      case "doctors":
        return "Doctor / GP";
      case "clinic":
        return "Clinic";
      case "hospital":
        return "Hospital";
      case "pharmacy":
        return "Pharmacy";
      case "fire_station":
        return "Fire Station";
      default:
        return type ?? "Unknown";
    }
  }
}
