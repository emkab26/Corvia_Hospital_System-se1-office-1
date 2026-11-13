// Local UI harness only. No Supabase initialization, credentials or network data.
// Production starts at lib/main.dart and never imports this file.
import 'package:flutter/material.dart';
import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/services/emergency_dispatch_service.dart';
import 'package:mycorvia/theme/app_theme.dart';
import 'package:mycorvia/widgets/emergency_phone_card.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Corvia WS4 — Local Preview',
    theme: CorviaTheme.resolve(),
    home: const _LocalPreview(),
  ));
}

class _LocalPreview extends StatefulWidget {
  const _LocalPreview();

  @override
  State<_LocalPreview> createState() => _LocalPreviewState();
}

class _LocalPreviewState extends State<_LocalPreview> {
  int generation = 0;
  String scenario = 'Sample queue';
  bool supervisor = false;
  bool patientView = true;
  late List<DispatchEmergency> incidents;

  @override
  void initState() {
    super.initState();
    seed();
  }

  void seed() {
    final now = DateTime.now();
    incidents = [
      DispatchEmergency(
        id: '1001',
        userId: 'SAMPLE-PATIENT-A',
        status: 'pending',
        createdAt: now.subtract(const Duration(minutes: 3)),
      ),
      DispatchEmergency(
        id: '1002',
        userId: 'SAMPLE-PATIENT-B',
        status: 'pending',
        createdAt: now.subtract(const Duration(minutes: 1)),
      ),
      DispatchEmergency(
        id: '1003',
        userId: 'SAMPLE-PATIENT-C',
        status: 'in_progress',
        createdAt: now.subtract(const Duration(minutes: 8)),
        acceptedAt: now.subtract(const Duration(minutes: 5)),
        assignedDispatcherUserId: 'SAMPLE-DISPATCHER',
      ),
    ];
  }

  void reset() => setState(() {
        generation++;
        seed();
      });

  Future<List<DispatchEmergency>> load() async {
    if (scenario == 'Read failure') {
      throw StateError('Simulated local queue read failure');
    }
    return scenario == 'Empty queue' ? [] : List.of(incidents);
  }

  Future<DispatchEmergency> accept(String id) async {
    final index = incidents.indexWhere((item) => item.id == id);
    final old = incidents[index];
    final claimed = DispatchEmergency(
      id: old.id,
      userId: old.userId,
      status: 'in_progress',
      createdAt: old.createdAt,
      acceptedAt: DateTime.now(),
      assignedDispatcherUserId: 'SAMPLE-DISPATCHER',
    );
    incidents[index] = claimed;
    return claimed;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('LOCAL PREVIEW • Sample data • No database',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                                value: true, label: Text('Patient view')),
                            ButtonSegment(
                                value: false, label: Text('Dispatcher view')),
                          ],
                          selected: {patientView},
                          onSelectionChanged: (values) =>
                              setState(() => patientView = values.single),
                        ),
                        if (!patientView) ...[
                          DropdownButton<String>(
                            value: scenario,
                            items: [
                              'Sample queue',
                              'Empty queue',
                              'Read failure'
                            ]
                                .map((value) => DropdownMenuItem(
                                    value: value, child: Text(value)))
                                .toList(),
                            onChanged: (value) {
                              scenario = value!;
                              reset();
                            },
                          ),
                          FilterChip(
                              label: const Text('Supervisor view'),
                              selected: supervisor,
                              onSelected: (value) {
                                supervisor = value;
                                reset();
                              }),
                          TextButton.icon(
                              onPressed: reset,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset sample data')),
                        ],
                      ]),
                )),
          ),
          Expanded(
              child: patientView
                  ? const _PatientPhonePreview()
                  : EmergencyDispatchDashboard(
                      key: ValueKey(generation),
                      accessLoader: () async => DispatchAccessContext.fromMap({
                        'user_id': '00000000-0000-4000-8000-000000000001',
                        'memberships': [
                          {
                            'organisation_id':
                                '00000000-0000-4000-8000-000000000002',
                            'role': supervisor
                                ? 'dispatch_supervisor'
                                : 'dispatcher',
                          }
                        ],
                        'capabilities': ['read_incidents', 'claim_incident'],
                        'policy_version': 'ws4-dev-core-1',
                        'server_time': DateTime.now().toUtc().toIso8601String(),
                      },
                          expectedUserId:
                              '00000000-0000-4000-8000-000000000001'),
                      accessLevel: supervisor
                          ? DispatchAccessLevel.supervisor
                          : DispatchAccessLevel.dispatcher,
                      incomingEmergencyLoader: load,
                      incomingEmergencyAccepter: accept,
                      onSignOut: () async => reset(),
                    )),
        ]),
      );
}

/// Shows the production patient phone card without starting EmergencyPage's
/// incident, GPS, permission, or WebRTC lifecycle.
class _PatientPhonePreview extends StatelessWidget {
  const _PatientPhonePreview();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Patient emergency')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EmergencyPhoneCard(),
                  SizedBox(height: 16),
                  Text(
                    'This is the actual phone card from the patient emergency '
                    'screen. Incident creation, location sharing and Corvia '
                    'internet calls are not running in this local preview.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'The phone button can open your device’s phone app. '
                    'Do not place a test call to ER24.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
