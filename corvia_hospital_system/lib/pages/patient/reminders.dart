import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';
import 'medication_reminders.dart';

/// Reminders aggregated from the patient's upcoming appointments and
/// active prescription refills. Joins are kept shallow so a single
/// misnamed FK constraint doesn't crash the whole page.
class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

enum _Filter { all, appointments, refills }

class _RemindersPageState extends State<RemindersPage> {
  _Filter _filter = _Filter.all;
  Future<List<_Reminder>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<List<_Reminder>> _load() async {
    final patientId = await SupabaseService.currentPatientId();
    if (patientId == null) return const [];

    final client = SupabaseService.client;
    final reminders = <_Reminder>[];

    // 1) Upcoming appointments - fetch raw rows, then fetch doctor names
    //    in a separate query (more resilient than a nested join).
    try {
      final apptRows = await client
          .from('appointments')
          .select('appointment_date, reason, type, status, doctor_id')
          .eq('patient_id', patientId)
          .gte('appointment_date', DateTime.now().toIso8601String())
          .neq('status', 'cancelled')
          .order('appointment_date');

      final doctorIds = <String>{
        for (final r in (apptRows as List))
          if (r['doctor_id'] != null) r['doctor_id'].toString(),
      };

      final Map<String, String> doctorNames = {};
      if (doctorIds.isNotEmpty) {
        try {
          final docs = await client
              .from('doctors')
              .select('id, profile_id')
              .inFilter('id', doctorIds.toList());
          final profileIds = <String>{
            for (final d in (docs as List))
              if (d['profile_id'] != null) d['profile_id'].toString(),
          };
          if (profileIds.isNotEmpty) {
            final profiles = await client
                .from('profiles')
                .select('user_id, first_name, surname')
                .inFilter('user_id', profileIds.toList());
            final profileById = {
              for (final p in (profiles as List)) p['user_id'].toString(): p
            };
            for (final d in docs) {
              final p = profileById[d['profile_id']?.toString()];
              if (p != null) {
                final name =
                    '${p['first_name'] ?? ''} ${p['surname'] ?? ''}'.trim();
                doctorNames[d['id'].toString()] =
                    name.isEmpty ? 'Doctor' : 'Dr. $name';
              }
            }
          }
        } catch (_) {
          // Names are optional decoration - keep going if this fails.
        }
      }

      for (final r in apptRows) {
        final ts = DateTime.tryParse(r['appointment_date']?.toString() ?? '');
        if (ts == null) continue;
        final docId = r['doctor_id']?.toString();
        final doctorLabel = (docId != null && doctorNames.containsKey(docId))
            ? doctorNames[docId]!
            : 'Appointment';
        reminders.add(_Reminder(
          icon: r['type'] == 'telehealth'
              ? Icons.video_call
              : Icons.calendar_today,
          title: doctorLabel,
          subtitle: '${(r['reason'] ?? '').toString()} (${r['type']})'.trim(),
          when: ts,
        ));
      }
    } catch (_) {
      // Re-throw so the page can show an error state.
      rethrow;
    }

    // 2) Prescription refills - failures here shouldn't kill appointments.
    try {
      final rxRows = await client
          .from('prescriptions')
          .select('medication_name, refill_date, status')
          .eq('patient_id', patientId)
          .eq('status', 'active')
          .not('refill_date', 'is', null)
          .order('refill_date');

      for (final r in (rxRows as List)) {
        final ts = DateTime.tryParse(r['refill_date']?.toString() ?? '');
        if (ts == null) continue;
        reminders.add(_Reminder(
          icon: Icons.medication,
          title: 'Refill: ${r['medication_name']}',
          subtitle: 'Active prescription',
          when: ts,
        ));
      }
    } catch (_) {
      // Swallow - appointments still display.
    }

    reminders.sort((a, b) => a.when.compareTo(b.when));
    return reminders;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.cBgPrimary,
        appBar: AppBar(
          title: const Text('Reminders'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.notifications_active_outlined),
                text: 'General',
              ),
              Tab(
                icon: Icon(Icons.medication_outlined),
                text: 'Medication',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGeneralReminders(),
            const MedicationRemindersPage(
              embedded: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralReminders() {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final filter in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      filter.name[0].toUpperCase() + filter.name.substring(1),
                    ),
                    selected: _filter == filter,
                    onSelected: (_) {
                      setState(() {
                        _filter = filter;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: FutureBuilder<List<_Reminder>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return StatusView.loading(message: 'Loading reminders...');
                }
                if (snap.hasError) {
                  return StatusView.error(
                    friendlyMessage: "We couldn't load your reminders.",
                    error: snap.error,
                    stackTrace: snap.stackTrace,
                    onRetry: _refresh,
                  );
                }
                final all = snap.data ?? const [];
                final items = _filter == _Filter.all
                    ? all
                    : all
                        .where(
                          (reminder) => _filter == _Filter.appointments
                              ? reminder.icon != Icons.medication
                              : reminder.icon == Icons.medication,
                        )
                        .toList();
                if (items.isEmpty) {
                  return StatusView.empty(
                    icon: Icons.notifications_none,
                    title: 'No upcoming reminders',
                    subtitle:
                        'Appointments and prescription refills will appear here.',
                    onRetry: _refresh,
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final reminder = items[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          reminder.icon,
                          color: CorviaColors.accent,
                        ),
                        title: Text(
                          reminder.title,
                          style: TextStyle(
                            color: CorviaColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          reminder.subtitle,
                          style: TextStyle(
                            color: CorviaColors.textSecondary,
                          ),
                        ),
                        trailing: Text(
                          DateFormat('d MMM\nHH:mm').format(
                            reminder.when.toLocal(),
                          ),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: CorviaColors.accentLight,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Reminder {
  _Reminder({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.when,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime when;
}
