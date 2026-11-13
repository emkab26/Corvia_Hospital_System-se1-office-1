import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'report_card.dart';
import 'report_models.dart';

class PatientInfoCard extends StatelessWidget {
  final PatientData patient;

  const PatientInfoCard({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 30,
            backgroundColor: CorviaColors.accent.withValues(alpha: 0.12),
            child: Text(
              patient.initials,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.cAccentReadable,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.fullName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill(
                        label: patient.gender,
                        icon: Icons.person_outline_rounded),
                    _Pill(label: patient.age, icon: Icons.cake_outlined),
                    _Pill(
                        label: patient.bloodType,
                        icon: Icons.bloodtype_outlined),
                  ],
                ),
                const SizedBox(height: 8),
                _MetaRow(
                    icon: Icons.badge_outlined,
                    text: 'ID: ${patient.patientId}'),
                const SizedBox(height: 3),
                _MetaRow(icon: Icons.phone_outlined, text: patient.phone),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Pill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: CorviaColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: context.cTextSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: context.cTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: context.cTextMuted),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: context.cTextSecondary),
        ),
      ],
    );
  }
}
