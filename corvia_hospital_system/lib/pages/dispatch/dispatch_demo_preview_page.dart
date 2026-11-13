import 'package:flutter/material.dart';

/// Read-only presentation of synthetic cases while the reviewed WS4 backend
/// remains uninstalled. This widget has no Supabase client or command path.
class DispatchDemoPreviewPage extends StatelessWidget {
  const DispatchDemoPreviewPage({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  static const _cases = <({String reference, String priority, String summary})>[
    (
      reference: 'DEMO-001',
      priority: 'High',
      summary: 'Synthetic medical response request'
    ),
    (
      reference: 'DEMO-002',
      priority: 'Medium',
      summary: 'Synthetic patient transport request'
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: onSignOut == null
            ? null
            : AppBar(
                title: const Text('Corvia EMS Preview'),
                actions: [
                  TextButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Emergency Dispatch Preview',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              MaterialBanner(
                content: const Text(
                  'DEMO DATA — no real EMS dispatch. These are synthetic examples; no ambulance has been assigned or contacted.',
                ),
                leading: const Icon(Icons.info_outline),
                actions: const [SizedBox.shrink()],
              ),
              const SizedBox(height: 16),
              const Text('Example incident queue (read-only)'),
              const SizedBox(height: 8),
              for (final item in _cases)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.medical_services_outlined),
                    title: Text(item.reference),
                    subtitle: Text(item.summary),
                    trailing: Chip(label: Text(item.priority)),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Live claiming, crew assignment and dispatch remain unavailable until the backend is reviewed and installed.',
              ),
            ],
          ),
        ),
      );
}
