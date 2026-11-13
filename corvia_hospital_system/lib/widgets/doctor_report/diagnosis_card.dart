import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'report_card.dart';
import 'report_models.dart';

class DiagnosisCard extends StatelessWidget {
  final List<DiagnosisData> diagnoses;

  const DiagnosisCard({super.key, required this.diagnoses});

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      child: Column(
        children: [
          for (int i = 0; i < diagnoses.length; i++) ...[
            _DiagnosisRow(entry: diagnoses[i]),
            if (i < diagnoses.length - 1)
              Divider(height: 20, color: context.cDivider),
          ],
        ],
      ),
    );
  }
}

class _DiagnosisRow extends StatelessWidget {
  final DiagnosisData entry;

  const _DiagnosisRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ICD code badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: CorviaColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            entry.icdCode,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.cAccentReadable,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Name + tag
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                style: TextStyle(
                  fontSize: 14,
                  color: context.cTextPrimary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 5),
              if (entry.isPrimary)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: CorviaColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Primary Diagnosis',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: CorviaColors.success,
                    ),
                  ),
                )
              else
                Text(
                  'Secondary',
                  style: TextStyle(fontSize: 12, color: context.cTextMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
