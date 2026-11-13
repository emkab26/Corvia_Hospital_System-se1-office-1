import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/dispatch/dispatch_emergency.dart';

class IncidentLocationPanel extends StatefulWidget {
  const IncidentLocationPanel({super.key, this.incident, this.openMap});
  final DispatchEmergency? incident;
  final Future<bool> Function(Uri)? openMap;
  @override
  State<IncidentLocationPanel> createState() => _IncidentLocationPanelState();
}

class _IncidentLocationPanelState extends State<IncidentLocationPanel> {
  String? _error;
  Future<void> _open() async {
    final incident = widget.incident;
    if (incident == null ||
        incident.needsReview ||
        incident.latitude == null ||
        incident.longitude == null) {
      return;
    }
    final uri = Uri.https('www.openstreetmap.org', '/', {
      'mlat': '${incident.latitude}',
      'mlon': '${incident.longitude}'
    }).replace(fragment: 'map=16/${incident.latitude}/${incident.longitude}');
    var success = false;
    try {
      success = await (widget.openMap?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {}
    if (mounted) {
      setState(() => _error = success
          ? null
          : 'The map could not open. Use the recorded coordinates or address below.');
    }
  }

  @override
  void didUpdateWidget(covariant IncidentLocationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incident != widget.incident) _error = null;
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.incident;
    final valid = i != null &&
        !i.needsReview &&
        i.latitude != null &&
        i.longitude != null;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Incident location',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text(i == null
                      ? 'Select an incident to inspect its recorded location.'
                      : i.coordinateLabel),
                  if (i?.address != null)
                    SelectableText('Patient-reported address: ${i!.address}'),
                  if (valid) ...[
                    Text(i.locationCapturedAt == null
                        ? 'Capture time and accuracy are unknown.'
                        : 'Recorded ${i.locationCapturedAt!.toUtc().toIso8601String()} · accuracy ${i.locationAccuracy} m'),
                    const Text(
                        'This is a recorded location, not live tracking. Confirm the location with the patient.'),
                    OutlinedButton.icon(
                        onPressed: _open,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Open recorded location in map')),
                    const Text(
                        'Opens OpenStreetMap with these coordinates. Map access needs an internet connection.'),
                  ] else if (i != null)
                    const Text(
                        'No verified coordinates are available. Confirm an address or landmark.'),
                  if (_error != null) Text(_error!),
                  const Divider(),
                  const Text(
                      'Fleet positions and receiving-hospital availability are not connected. No unit location, bed availability or hospital acceptance is assumed.'),
                ])));
  }
}
