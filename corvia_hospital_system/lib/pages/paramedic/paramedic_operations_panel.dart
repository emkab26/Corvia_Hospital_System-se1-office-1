import 'package:flutter/material.dart';
import '../../services/paramedic_workspace_service.dart';
import 'paramedic_forms.dart';

typedef OperationsForm = Future<EmsRow?> Function(String action, String title,
    List<EmsField> fields, EmsRow extra, EmsRow initial);

class ParamedicOperationsPanel extends StatelessWidget {
  const ParamedicOperationsPanel(
      {super.key,
      required this.data,
      required this.admin,
      required this.onForm});
  final EmsRow data;
  final bool admin;
  final OperationsForm onForm;
  List<EmsRow> rows(String key) => emsRows(data[key]);

  @override
  Widget build(BuildContext context) {
    if (!data.containsKey('operations_role')) {
      return const Text(
          'Install the Dispatch & Fleet SQL upgrade, then refresh to open fleet inspections and dispatch controls.');
    }
    final vehicles = {
      for (final r in rows('units_actual'))
        r['unit_id'].toString():
            '${r['unit_number']} • ${r['registration_number'] ?? ''}'
    };
    final vehicle =
        EmsField('unit_id', 'Vehicle', required: true, options: vehicles);
    Widget action(String title, String key, List<EmsField> fields,
            {EmsRow extra = const {}, EmsRow initial = const {}}) =>
        Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: FilledButton.tonal(
                onPressed: () => onForm(key, title, fields, extra, initial),
                child: Text(title)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Fleet operations',
          style: Theme.of(context).textTheme.headlineSmall),
      const Text(
          'Dispatch eligibility includes compliance, capabilities, inspection, open faults and the current verified crew shift. Refresh to see changes.'),
      const SizedBox(height: 12),
      Wrap(children: [
        if (admin)
          action('Record inspection', 'readiness', [
            vehicle,
            for (final item in const {
              'vehicle_ok': 'Vehicle',
              'equipment_ok': 'Equipment',
              'oxygen_ok': 'Oxygen',
              'fuel_ok': 'Fuel',
              'communications_ok': 'Communications',
              'cleaning_ok': 'Cleaning'
            }.entries)
              EmsField(item.key, item.value,
                  required: true,
                  options: const {'true': 'Pass', 'false': 'Fail'}),
            const EmsField('notes', 'Inspection notes',
                required: true, multiline: true, max: 1000)
          ]),
        action('Report vehicle fault', 'fault', [
          vehicle,
          const EmsField('description', 'Fault details',
              required: true, multiline: true, max: 1000)
        ]),
        if (admin)
          action('Add base', 'base', const [
            EmsField('name', 'Base name', required: true),
            EmsField('address', 'Address', required: true, max: 300),
            EmsField('phone', 'Contact number', max: 30),
            EmsField('latitude', 'Latitude', number: true),
            EmsField('longitude', 'Longitude', number: true)
          ]),
        if (admin)
          action('Dispatcher access', 'operator', [
            const EmsField('email', 'Existing account email', required: true),
            EmsField('role', 'Role',
                required: true, options: choices(['dispatcher', 'supervisor'])),
            EmsField('active', 'Access enabled',
                required: true, options: choices(['true', 'false']))
          ], initial: const {
            'role': 'dispatcher',
            'active': true
          })
      ]),
      for (final r in rows('units_actual'))
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['unit_number']} • ${r['response_capability']}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(r['eligibility_reason']?.toString() ??
                          'Eligible for BLS dispatch; incident capability is checked at assignment.'),
                      Text(
                          'Compliance expiry: ${r['compliance_expiry_date'] ?? 'Not captured'}'),
                      Text(
                          'Location: ${r['location_stale'] == true ? 'Stale / unavailable' : 'Recent'} • ${emsTime(r['location_updated_at'])}'),
                      if (r['latitude'] != null)
                        Text('${r['latitude']}, ${r['longitude']}'),
                      if (admin && rows('bases').isNotEmpty)
                        action('Assign base', 'unit', [
                          EmsField('base_id', 'Base', required: true, options: {
                            for (final b in rows('bases'))
                              b['base_id'].toString(): b['name'].toString()
                          })
                        ], extra: {
                          ...r,
                          'id': r['unit_id']
                        })
                    ]))),
      const SizedBox(height: 16),
      Text('Faults and repairs', style: Theme.of(context).textTheme.titleLarge),
      if (rows('faults').isEmpty) const Text('No reported faults.'),
      for (final r in rows('faults').reversed)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${vehicles[r['unit_id'].toString()] ?? 'Vehicle'} • ${r['resolved_at'] == null ? 'OPEN' : 'Repaired'}'),
                      Text('${r['description']}'),
                      Text('Reported ${emsTime(r['reported_at'])}'),
                      if (r['resolution'] != null)
                        Text(
                            'Repair: ${r['resolution']} • ${emsTime(r['resolved_at'])}'),
                      if (admin && r['resolved_at'] == null)
                        action('Record repair', 'fault_resolve', const [
                          EmsField('resolution',
                              'Repair details (a new inspection is required)',
                              required: true, multiline: true, max: 1000)
                        ], extra: {
                          'fault_id': r['fault_id'],
                          'unit_id': r['unit_id']
                        })
                    ]))),
      const SizedBox(height: 16),
      Text('Inspection history', style: Theme.of(context).textTheme.titleLarge),
      for (final r in rows('readiness').reversed.take(50))
        Card(
            child: ListTile(
                title: Text(
                    '${vehicles[r['unit_id'].toString()] ?? 'Vehicle'} • ${emsTime(r['recorded_at'])}'),
                subtitle: Text(
                    '${r['notes']}\nExpires ${emsTime(r['expires_at'])}\n${[
                  'vehicle',
                  'equipment',
                  'oxygen',
                  'fuel',
                  'communications',
                  'cleaning'
                ].map((k) => '$k: ${r['${k}_ok'] == true ? 'Pass' : 'Fail'}').join(' • ')}'))),
      const SizedBox(height: 16),
      Text('Bases', style: Theme.of(context).textTheme.titleLarge),
      for (final r in rows('bases'))
        ListTile(
            title: Text('${r['name']}'),
            subtitle: Text('${r['address']} • ${r['phone'] ?? ''}')),
      if (admin) ...[
        Text('Dispatch access', style: Theme.of(context).textTheme.titleLarge),
        for (final r in rows('operators'))
          ListTile(
              title: Text('${r['email']}'),
              subtitle: Text(
                  '${r['role']} • ${r['active'] == true ? 'Active' : 'Disabled'}'))
      ]
    ]);
  }
}
