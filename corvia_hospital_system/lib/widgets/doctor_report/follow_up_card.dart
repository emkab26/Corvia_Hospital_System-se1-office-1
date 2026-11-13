import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'report_card.dart';
import 'report_models.dart';

class FollowUpCard extends StatelessWidget {
  final FollowUpData followUp;

  const FollowUpCard({super.key, required this.followUp});

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      child: Row(
        children: [
          // Calendar icon box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CorviaColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.event_rounded,
              color: context.cAccentReadable,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),

          // Date + location
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next Appointment',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  followUp.dateTime,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.cAccentReadable,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  followUp.location,
                  style: TextStyle(fontSize: 12, color: context.cTextMuted),
                ),
              ],
            ),
          ),

          Icon(Icons.chevron_right_rounded, color: context.cTextMuted),
        ],
      ),
    );
  }
}
