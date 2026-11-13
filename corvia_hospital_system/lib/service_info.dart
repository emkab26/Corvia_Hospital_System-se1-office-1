import 'package:flutter/material.dart';
import 'service_place.dart';
import 'open_map.dart';

/// Displays a modal bottom sheet containing the details of a nearby
/// health service (name, type, hours, contact info) and a button to
/// route there via external map applications.
void showServiceInfo(BuildContext context, ServicePlace place,
    {double? distanceMetres}) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name (always present or default)
            Text(
              place.name ?? "Unnamed Location",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            if (distanceMetres != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text(
                  distanceMetres >= 1000
                      ? '${(distanceMetres / 1000).toStringAsFixed(1)} km away'
                      : '${distanceMetres.toInt()} m away',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),

            const SizedBox(height: 10),

            Text("Type: ${serviceTypeLabel(place.type)}"),

            if (place.distanceMeters != null)
              Text(
                place.distanceMeters! < 1000
                    ? "Distance: ${place.distanceMeters!.round()} m"
                    : "Distance: ${(place.distanceMeters! / 1000).toStringAsFixed(1)} km",
              ),

            // Only show hours if available
            if (place.hours != null) Text("Opening Hours: ${place.hours}"),

            // Only show phone if available
            if (place.phone != null) Text("Phone: ${place.phone}"),

            // Only show website if available
            if (place.website != null) Text("Website: ${place.website}"),

            // If EVERYTHING is missing
            if (place.hours == null &&
                place.phone == null &&
                place.website == null &&
                place.distanceMeters == null) //added
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  "No additional details available",
                  style: TextStyle(color: Colors.grey),
                ),
              ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: () {
                openInMaps(
                  place.location.latitude,
                  place.location.longitude,
                  label: place.name,
                );
              },
              icon: const Icon(Icons.navigation),
              label: const Text("Open in Maps"),
            ),
          ],
        ),
      );
    },
  );
}

/// Human-readable label for a nearby-service type.
String serviceTypeLabel(String? type) {
  switch (type) {
    case 'hospital':
      return 'Hospital';
    case 'clinic':
      return 'Clinic / health centre';
    case 'doctors':
      return 'Doctor / GP practice';
    case 'dentist':
      return 'Dentist';
    case 'pharmacy':
      return 'Pharmacy';
    case 'ambulance_station':
      return 'Ambulance station';
    case 'fire_station':
      return 'Fire station';
    case 'police':
      return 'Police station';
    case null:
    case '':
      return 'Health service';
    default:
      return type[0].toUpperCase() + type.substring(1).replaceAll('_', ' ');
  }
}
