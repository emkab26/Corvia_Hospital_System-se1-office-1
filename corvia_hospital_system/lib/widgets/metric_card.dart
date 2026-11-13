import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MetricCard extends StatelessWidget {
  final IconData icon;
  final String val;
  final String unit;
  final Color color;

  const MetricCard({
    super.key,
    required this.icon,
    required this.val,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 130),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (w, a) => FadeTransition(opacity: a, child: w),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                val,
                key: ValueKey(val),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.cTextPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: TextStyle(
                fontSize: 11,
                color: context.cTextSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
