import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'report_card.dart';
import 'report_models.dart';

class MedicationsCard extends StatelessWidget {
  final List<MedicationData> medications;

  const MedicationsCard({super.key, required this.medications});

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      child: Column(
        children: [
          for (int i = 0; i < medications.length; i++) ...[
            _MedRow(med: medications[i]),
            if (i < medications.length - 1)
              Divider(height: 20, color: context.cDivider),
          ],
        ],
      ),
    );
  }
}

class _MedRow extends StatelessWidget {
  final MedicationData med;

  const _MedRow({required this.med});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon box
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: CorviaColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.medication_rounded,
            color: context.cAccentReadable,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),

        // Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      med.name,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: CorviaColors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      med.dosage,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.cAccentReadable,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                med.frequency,
                style: TextStyle(fontSize: 13, color: context.cTextSecondary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 12, color: context.cTextMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Duration: ${med.duration}',
                    style: TextStyle(fontSize: 12, color: context.cTextMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
