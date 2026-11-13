import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'report_models.dart';

class VitalsGrid extends StatelessWidget {
  final List<VitalData> vitals;

  const VitalsGrid({super.key, required this.vitals});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: vitals.length,
      itemBuilder: (_, i) => _VitalCard(vital: vitals[i]),
    );
  }
}

class _VitalCard extends StatelessWidget {
  final VitalData vital;

  const _VitalCard({required this.vital});

  Color _bgColor(BuildContext context) {
    final dark = context.isDarkTheme;
    switch (vital.status) {
      case VitalStatus.critical:
        return CorviaColors.danger.withValues(alpha: dark ? 0.15 : 0.08);
      case VitalStatus.warning:
        return CorviaColors.warning.withValues(alpha: dark ? 0.15 : 0.08);
      case VitalStatus.normal:
        return context.cBgSecondary;
    }
  }

  Color get _iconColor {
    switch (vital.status) {
      case VitalStatus.critical:
        return CorviaColors.danger;
      case VitalStatus.warning:
        return CorviaColors.warning;
      case VitalStatus.normal:
        return CorviaColors.accent;
    }
  }

  Color get _dotColor {
    switch (vital.status) {
      case VitalStatus.critical:
        return CorviaColors.danger;
      case VitalStatus.warning:
        return CorviaColors.warning;
      case VitalStatus.normal:
        return CorviaColors.success;
    }
  }

  IconData get _icon {
    switch (vital.iconKey) {
      case 'heart':
        return Icons.favorite_rounded;
      case 'speed':
        return Icons.speed_rounded;
      case 'thermostat':
        return Icons.thermostat_rounded;
      case 'air':
        return Icons.air_rounded;
      case 'waves':
        return Icons.waves_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      default:
        return Icons.monitor_heart_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon + status dot
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(_icon, size: 18, color: _iconColor),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),

          // Value + label
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    vital.value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: context.cTextPrimary,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      vital.unit,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.cTextMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                vital.label,
                style: TextStyle(fontSize: 11, color: context.cTextSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
