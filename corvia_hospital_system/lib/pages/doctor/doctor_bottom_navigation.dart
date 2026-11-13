import 'package:flutter/material.dart';

import '../../widgets/nav_label_fit.dart';

/// Doctor portal bottom navigation. Labels shrink to stay on one line on
/// narrow phones instead of wrapping.
class DoctorBottomNavigation extends StatelessWidget {
  const DoctorBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  // Short labels so five tabs fit on one line on 360 px phones; the full
  // name is the tooltip, which screen readers also announce.
  static const List<
      ({
        IconData icon,
        IconData selectedIcon,
        String label,
        String tooltip
      })> _items = [
    (
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Home',
      tooltip: 'Home',
    ),
    (
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Appts',
      tooltip: 'Appointments',
    ),
    (
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'Patients',
      tooltip: 'Patients',
    ),
    (
      icon: Icons.medication_outlined,
      selectedIcon: Icons.medication,
      label: 'Meds',
      tooltip: 'Prescriptions',
    ),
    (
      icon: Icons.biotech_outlined,
      selectedIcon: Icons.biotech,
      label: 'Labs',
      tooltip: 'Lab orders',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final barTheme = NavigationBarTheme.of(context);
        final baseStyle =
            theme.textTheme.labelMedium ?? const TextStyle(fontSize: 12);

        // Shrink the labels only as far as needed to keep the longest on one
        // line at this width and text scale.
        final fontSize = fitNavigationLabelFontSize(
          labels: [for (final item in _items) item.label],
          baseStyle: baseStyle,
          slotWidth: constraints.maxWidth / _items.length - 4,
          textScaler: MediaQuery.textScalerOf(context).clamp(
            maxScaleFactor: kNavigationBarMaxLabelTextScale,
          ),
        );

        return NavigationBarTheme(
          data: barTheme.copyWith(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              // Overriding labelTextStyle replaces the Material 3 default, so
              // keep its colours when the app theme does not set any.
              final themed = barTheme.labelTextStyle?.resolve(states);
              final color = states.contains(WidgetState.disabled)
                  ? colors.onSurfaceVariant.withValues(alpha: 0.38)
                  : states.contains(WidgetState.selected)
                      ? colors.onSurface
                      : colors.onSurfaceVariant;
              return (themed ?? baseStyle.copyWith(color: color))
                  .copyWith(fontSize: fontSize);
            }),
          ),
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final item in _items)
                NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                  tooltip: item.tooltip,
                ),
            ],
          ),
        );
      },
    );
  }
}
