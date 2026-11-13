import 'package:flutter/material.dart';

import '../services/doctor_directory.dart';
import '../theme/app_theme.dart';

class DoctorAvailabilityAvatar extends StatelessWidget {
  const DoctorAvailabilityAvatar({super.key, required this.doctor});

  final DoctorEntry doctor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          backgroundColor:
              doctor.available ? CorviaColors.accent : CorviaColors.textMuted,
          child: const Icon(Icons.medical_services, color: Colors.white),
        ),
        if (doctor.available)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: CorviaColors.success,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).cardColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
