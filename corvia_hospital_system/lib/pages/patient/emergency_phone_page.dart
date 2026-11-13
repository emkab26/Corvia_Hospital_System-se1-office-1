import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/location_service.dart';
import '../../widgets/emergency_phone_card.dart';

/// Call preparation only. No incident, backend write, map, or in-app call.
/// Optional details live in this page's memory and are cleared on disposal.
class EmergencyPhonePage extends StatefulWidget {
  const EmergencyPhonePage({super.key, this.readLocation});

  final Future<Position?> Function()? readLocation;

  @override
  State<EmergencyPhonePage> createState() => _EmergencyPhonePageState();
}

class _EmergencyPhonePageState extends State<EmergencyPhonePage> {
  final _address = TextEditingController();
  final _details = TextEditingController();
  Position? _position;
  bool _locating = false;
  bool _locationFailed = false;

  Future<void> _getLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locationFailed = false;
      _position = null;
    });
    Position? position;
    try {
      // Bound the entire operation, including an unanswered permission prompt.
      final result = await (widget.readLocation?.call() ??
              LocationService.currentPosition(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 15));
      if (result != null) {
        final age = DateTime.now().difference(result.timestamp);
        if (result.latitude.isFinite &&
            result.longitude.isFinite &&
            result.latitude.abs() <= 90 &&
            result.longitude.abs() <= 180 &&
            result.accuracy.isFinite &&
            result.accuracy >= 0 &&
            age >= const Duration(seconds: -30) &&
            age <= const Duration(minutes: 2)) {
          position = result;
        }
      }
    } catch (_) {
      // Location must never prevent calling; do not log sensitive details.
    }
    if (!mounted) return;
    setState(() {
      _position = position;
      _locating = false;
      _locationFailed = position == null;
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency help')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EmergencyPhoneCard(),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Details to tell the operator',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          const Text(
                            'Call first if you need urgent help. These optional '
                            'details are for you to read out. They are not saved '
                            'or sent to ER24 or Corvia dispatch and are cleared '
                            'when you leave this screen.',
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'You can use your device location to help describe '
                            'where you are. It may be approximate; confirm your '
                            'address or a nearby landmark with the operator.',
                          ),
                          if (position != null) ...[
                            const SizedBox(height: 8),
                            SelectableText(
                              'Latitude: ${position.latitude.toStringAsFixed(6)}\n'
                              'Longitude: ${position.longitude.toStringAsFixed(6)}\n'
                              'Estimated accuracy: ${position.accuracy.round()} m\n'
                              'Recorded: ${position.timestamp.toLocal()}',
                            ),
                            const Text(
                                'This is a location snapshot, not live tracking.'),
                          ],
                          if (_locationFailed) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Location unavailable. Tell the operator your '
                              'address or a nearby landmark. You can still call.',
                            ),
                          ],
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _locating ? null : _getLocation,
                            icon: const Icon(Icons.my_location),
                            label: Text(_locating
                                ? 'Finding location…'
                                : 'Get my location'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _address,
                            maxLength: 300,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText:
                                  'Address or nearby landmark (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _details,
                            maxLength: 1000,
                            minLines: 2,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'What happened? (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
