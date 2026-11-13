import 'package:flutter/material.dart';

import '../services/nurse_service.dart';

class NurseWardPicker extends StatelessWidget {
  const NurseWardPicker({
    super.key,
    required this.wards,
    required this.selectedWardId,
    required this.onChanged,
  });

  final List<NurseWard> wards;
  final String? selectedWardId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (wards.isEmpty) {
      return const Text(
        'No active wards are configured for this hospital. '
        'Ask the hospital administrator to add a ward in Hospital Structure, '
        'then refresh this page.',
      );
    }

    final selection =
        wards.any((ward) => ward.id == selectedWardId) ? selectedWardId : null;
    return DropdownButtonFormField<String>(
      key: ValueKey([selection, ...wards.map((ward) => ward.id)].join('|')),
      initialValue: selection,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Hospital ward',
        border: OutlineInputBorder(),
      ),
      hint: const Text('Select a ward'),
      items: wards
          .map((ward) => DropdownMenuItem(
                value: ward.id,
                child: Text(ward.label, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
