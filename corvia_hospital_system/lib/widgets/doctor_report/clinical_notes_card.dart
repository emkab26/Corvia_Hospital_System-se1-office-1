import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'report_card.dart';
import 'report_models.dart';

class ClinicalNotesCard extends StatelessWidget {
  final ClinicalNotesData notes;

  const ClinicalNotesCard({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Doctor attribution
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: CorviaColors.accent,
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notes.doctorName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${notes.doctorSpecialty} · ${notes.hospital}',
                      style: TextStyle(
                        color: context.cTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(color: context.cDivider, height: 1),
          const SizedBox(height: 14),

          // Notes body
          Text(
            notes.notes,
            style: TextStyle(
              fontSize: 14,
              color: context.cTextSecondary,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}
