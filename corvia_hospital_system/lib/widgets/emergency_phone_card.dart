import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A phone handoff, with no dependency on Corvia incident or calling state.
/// Opening a dialler does not establish that ER24 answered or dispatched help.
class EmergencyPhoneCard extends StatefulWidget {
  const EmergencyPhoneCard({super.key});

  @override
  State<EmergencyPhoneCard> createState() => _EmergencyPhoneCardState();
}

class _EmergencyPhoneCardState extends State<EmergencyPhoneCard> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _openPhone() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    var opened = false;
    try {
      // Verified against https://www.er24.co.za/en/corporate/contact.html
      // on 2026-10-07. No patient data is passed to the phone application.
      opened = await launchUrl(
        Uri(scheme: 'tel', path: '084124'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Unsupported platforms/plugins still retain the visible phone number.
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Call ER24 directly',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const SelectableText('084 124'),
            const SizedBox(height: 8),
            const Text(
              'Opens your phone app. Tell the operator your location and '
              'what happened. Corvia does not send incident details to ER24 '
              'or confirm that help is on the way.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _opening ? null : _openPhone,
              icon: const Icon(Icons.phone_outlined),
              label: Text(_opening ? 'Opening phone app…' : 'Call ER24'),
            ),
            if (_failed) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: const Text(
                  'Could not open a phone app. Dial 084 124 on a phone.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
