import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'add_user.dart';
import 'determine_position.dart';
import 'nearby_services.dart';
import 'service_info.dart';
import 'service_place.dart';
import 'theme/app_theme.dart';
import 'widgets/map_tiles.dart';
import 'widgets/status_view.dart';

/// Resolves the user's current location. Injectable so widget tests can
/// supply a fixed position without touching the platform location plugin.
typedef PositionProvider = Future<LatLng?> Function();

/// Fetches nearby services around a coordinate. Injectable so widget tests
/// can stub the Overpass call.
typedef ServicesProvider = Future<List<ServicePlace>> Function({
  required double lat,
  required double lon,
  required double radius,
});

/// Map of nearby health and emergency services around the user's current
/// location. Shows themed loading / empty / error states instead of an
/// indefinite spinner when location is unavailable or the Overpass API
/// returns nothing.
class MapTilerMapScreen extends StatefulWidget {
  const MapTilerMapScreen({
    super.key,
    this.positionProvider = determineCurrentPosition,
    this.servicesProvider = fetchNearbyServices,
  });

  final PositionProvider positionProvider;
  final ServicesProvider servicesProvider;

  @override
  State<MapTilerMapScreen> createState() => _MapTilerMapScreenState();
}

/// Represents the current loading or error state of the Map view.
enum _MapState { loading, ready, locationDenied, error, empty }

class _MapTilerMapScreenState extends State<MapTilerMapScreen> {
  LatLng? _currentPosition;
  final List<Marker> _markers = [];
  _MapState _state = _MapState.loading;
  Object? _lastError;
  StackTrace? _lastStack;
  int _serviceCount = 0;

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  /// Requests the user's location, plots the user on the map, and
  /// fetches nearby health services via the Overpass API.
  Future<void> _loadEverything() async {
    setState(() => _state = _MapState.loading);

    final pos = await widget.positionProvider();
    if (pos == null) {
      setState(() => _state = _MapState.locationDenied);
      return;
    }
    _currentPosition = pos;
    _markers
      ..clear()
      ..add(userMarker(pos));

    try {
      final services = await widget.servicesProvider(
        lat: pos.latitude,
        lon: pos.longitude,
        radius: 5000,
      );

      _serviceCount = services.length;
      for (final place in services) {
        _markers.add(_serviceMarker(place));
      }

      if (!mounted) return;
      setState(() {
        _state = services.isEmpty ? _MapState.empty : _MapState.ready;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _state = _MapState.error;
        _lastError = e;
        _lastStack = st;
      });
    }
  }

  /// Helper method that builds a Map Marker with an appropriate icon
  /// and color depending on the [place] type (hospital, pharmacy, etc.).
  Marker _serviceMarker(ServicePlace place) {
    Icon icon;
    switch (place.type) {
      case 'hospital':
        icon = const Icon(Icons.local_hospital,
            color: CorviaColors.danger, size: 36);
        break;
      case 'pharmacy':
        icon = Icon(Icons.medication, color: CorviaColors.success, size: 36);
        break;
      case 'fire_station':
        icon = const Icon(Icons.local_fire_department,
            color: CorviaColors.warning, size: 36);
        break;
      case 'doctors':
        icon =
            Icon(Icons.medical_services, color: CorviaColors.accent, size: 36);
        break;
      case 'clinic':
        icon = const Icon(Icons.local_hospital_outlined,
            color: Color(0xFFDB2777), size: 34);
        break;
      case 'dentist':
        icon = const Icon(Icons.medical_information,
            color: Color(0xFF7C3AED), size: 32);
        break;
      case 'ambulance_station':
        icon =
            const Icon(Icons.emergency, color: CorviaColors.danger, size: 34);
        break;
      case 'police':
        icon =
            const Icon(Icons.local_police, color: Color(0xFF1E3A8A), size: 34);
        break;
      default:
        icon =
            Icon(Icons.location_pin, color: CorviaColors.accentLight, size: 32);
    }
    return Marker(
      point: place.location,
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () => showServiceInfo(context, place),
        child: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Services')),
      backgroundColor: context.cBgPrimary,
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadEverything,
        backgroundColor: CorviaColors.accent,
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  /// Returns the corresponding UI body based on the current [_MapState].
  Widget _buildBody() {
    switch (_state) {
      case _MapState.loading:
        return StatusView.loading(message: 'Finding services near you...');
      case _MapState.locationDenied:
        return StatusView.empty(
          icon: Icons.location_off_outlined,
          title: 'Location access needed',
          subtitle:
              'Allow location permission in your device settings to find nearby hospitals, pharmacies, and clinics.',
          onRetry: _loadEverything,
          retryLabel: 'Try again',
        );
      case _MapState.error:
        return StatusView.error(
          friendlyMessage: "We couldn't reach the nearby-services service.",
          error: _lastError,
          stackTrace: _lastStack,
          onRetry: _loadEverything,
        );
      case _MapState.empty:
        return Stack(
          children: [
            _map(),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  color: context.cBgSecondary,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No clinics, hospitals, or pharmacies were '
                      'found within 5 km of your location.',
                      style: TextStyle(color: context.cTextPrimary),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case _MapState.ready:
        return Stack(
          children: [
            _map(),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.cBgSecondary.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_serviceCount nearby service${_serviceCount == 1 ? '' : 's'}',
                    style: TextStyle(color: CorviaColors.textPrimary),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _map() {
    final center = _currentPosition!;
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 14),
      children: [
        mapTileLayer(),
        MarkerLayer(markers: _markers),
        mapAttribution(),
      ],
    );
  }
}
