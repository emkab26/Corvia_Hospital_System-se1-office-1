import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Creates a blue marker representing the user's current GPS location on the map.
Marker userMarker(LatLng pos) {
  // The LatLng is the user’s GPS location (latitude & longitude).
  return Marker(
    // This tells the marker where on the map to be placed, it uses the coordinates passed into the function.
    point: pos,
    // Defines how large the marker area should be.
    width: 80,
    height: 80,
    //This is what the marker looks like visually.
    child: const Icon(
      Icons.my_location,
      // It's a blue "you are here" icon.
      color: Colors.blue,
      // Sized at 40 pixels.
      size: 40,
    ),
  );
}
