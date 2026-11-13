import 'package:flutter/material.dart';

import '../../services/paramedic_workspace_service.dart';

/// Presentation only. Vehicle data comes from the authorised EMS workspace,
/// never from the legacy sample FleetService.
enum FleetUnitFilter {
  all('All'),
  available('Available'),
  assigned('On dispatch'),
  maintenance('Maintenance'),
  offDuty('Off duty'),
  other('Other');

  const FleetUnitFilter(this.label);
  final String label;
}

FleetUnitFilter classifyFleetUnit(EmsRow unit) {
  if (unit['is_active'] == false) return FleetUnitFilter.other;
  final status = '${unit['status'] ?? ''}'.trim().toLowerCase();
  final readiness = '${unit['readiness_status'] ?? ''}'.trim().toLowerCase();
  if (readiness == 'maintenance' || status == 'out of service') {
    return FleetUnitFilter.maintenance;
  }
  if (readiness == 'off_duty') return FleetUnitFilter.offDuty;
  if (status == 'assigned' ||
      const {'en_route', 'on_scene', 'transporting'}.contains(readiness)) {
    return FleetUnitFilter.assigned;
  }
  if (unit['is_active'] != false &&
      status == 'available' &&
      const {'ready', 'idle'}.contains(readiness)) {
    return FleetUnitFilter.available;
  }
  return FleetUnitFilter.other;
}

class FleetLiveUnitCard extends StatelessWidget {
  const FleetLiveUnitCard({
    super.key,
    required this.unit,
    this.onEdit,
    this.onChangeReadiness,
  });

  final EmsRow unit;
  final VoidCallback? onEdit;
  final VoidCallback? onChangeReadiness;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = classifyFleetUnit(unit);
    final statusColor = switch (status) {
      FleetUnitFilter.available => const Color(0xFF16A76A),
      FleetUnitFilter.assigned => const Color(0xFF13B7D9),
      FleetUnitFilter.maintenance => const Color(0xFFFFAD27),
      FleetUnitFilter.offDuty => scheme.error,
      FleetUnitFilter.other || FleetUnitFilter.all => scheme.outline,
    };
    final number = _display(unit['unit_number'], 'Unnumbered vehicle');
    final registration =
        _display(unit['registration_number'], 'No registration');
    final type = _display(unit['vehicle_type'], 'Vehicle type unknown');
    final availability = _display(unit['status'], 'Status not recorded');
    final readiness =
        _display(unit['readiness_status'], 'Not recorded').replaceAll('_', ' ');
    final capability = _display(unit['response_capability'], '');
    final baseLocation = _display(unit['base_location'], '');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child:
                      Icon(Icons.airport_shuttle_rounded, color: statusColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(number,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('$type • $registration',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(text: status.label, color: statusColor),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _Fact(
                    icon: Icons.fact_check_outlined,
                    label: 'Readiness: $readiness'),
                _Fact(
                    icon: Icons.local_shipping_outlined,
                    label: 'Backend status: $availability'),
                if (capability.isNotEmpty)
                  _Fact(
                      icon: Icons.medical_services_outlined,
                      label: 'Capability: $capability'),
                if (baseLocation.isNotEmpty)
                  _Fact(icon: Icons.location_on_outlined, label: baseLocation),
                if (unit['is_active'] == false)
                  const _Fact(
                      icon: Icons.block_outlined, label: 'Inactive record'),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit details'),
                ),
                OutlinedButton.icon(
                  onPressed: onChangeReadiness,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Change readiness'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _display(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
