import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status.toLowerCase().trim();

    Color backgroundColor;
    Color textColor;
    String displayText;

    switch (normalizedStatus) {
      case 'scheduled':
        backgroundColor = Colors.blue.withValues(alpha: 0.12);
        textColor = Colors.blue.shade700;
        displayText = 'Scheduled';
        break;

      case 'confirmed':
        backgroundColor = Colors.green.withValues(alpha: 0.12);
        textColor = Colors.green.shade700;
        displayText = 'Confirmed';
        break;

      case "completed":
        backgroundColor = Colors.green.withValues(alpha: 0.12);
        textColor = CorviaColors.success;
        displayText = 'Completed';
        break;

      case 'cancelled':
      case 'canceled':
        backgroundColor = Colors.red.withValues(alpha: 0.12);
        textColor = Colors.red.shade700;
        displayText = 'Cancelled';
        break;

      case 'no-show':
      case 'no show':
      case 'noshow':
        backgroundColor = Colors.orange.withValues(alpha: 0.12);
        textColor = Colors.orange.shade800;
        displayText = 'No-show';
        break;

      case 'pending':
        backgroundColor = Colors.orange.withValues(alpha: 0.18);
        textColor = Colors.orange.shade900;
        displayText = 'Pending';
        break;

      case 'active':
        backgroundColor = Colors.green.withValues(alpha: 0.12);
        textColor = Colors.green.shade700;
        displayText = 'Active';
        break;

      default:
        backgroundColor = Colors.grey.withValues(alpha: 0.12);
        textColor = Colors.teal.shade700;
        displayText = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
