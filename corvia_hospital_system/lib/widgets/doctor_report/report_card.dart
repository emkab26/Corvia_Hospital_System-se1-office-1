import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Themed card shell used by every section of the doctor report.
/// Reads all colours through [CorviaContext] extensions so it
/// repaints automatically when the active theme changes.
class ReportCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ReportCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
