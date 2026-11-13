import 'package:flutter/material.dart';

import 'corvia_forms_navigator.dart';

class CorviaFormsButton extends StatelessWidget {
  const CorviaFormsButton({
    super.key,
    this.label = 'Hospital Forms',
    this.icon = Icons.description_outlined,
    this.compact = false,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool compact;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final callback = onPressed ??
        () {
          CorviaFormsNavigator.openCurrentUserForms(
            context,
          );
        };

    if (compact) {
      return IconButton(
        tooltip: label,
        onPressed: callback,
        icon: Icon(icon),
      );
    }

    return FilledButton.icon(
      onPressed: callback,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class CorviaFormsCard extends StatelessWidget {
  const CorviaFormsCard({
    super.key,
    this.title = 'Hospital Forms',
    this.subtitle =
        'Complete, review and sign your digital hospital documents.',
    this.icon = Icons.description_outlined,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ??
            () {
              CorviaFormsNavigator.openCurrentUserForms(
                context,
              );
            },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
