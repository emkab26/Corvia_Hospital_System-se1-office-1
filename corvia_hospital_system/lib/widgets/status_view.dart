import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable loading / empty / error states for any list or feed.
///
/// Use the named constructors to keep visual treatment consistent across
/// every page. Raw exception strings are *never* shown to the user - when a
/// real error is supplied via [StatusView.error], the user sees a friendly
/// message and the underlying detail is only logged to the console in
/// debug builds.
class StatusView extends StatelessWidget {
  const StatusView._({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    this.action,
    this.actionLabel,
    this.spinner = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback? action;
  final String? actionLabel;
  final bool spinner;

  /// Loading state - shows a spinner and a short message.
  factory StatusView.loading({String message = 'Loading...', Key? key}) {
    return StatusView._(
      key: key,
      icon: Icons.hourglass_empty,
      title: message,
      subtitle: '',
      tint: CorviaColors.accent,
      spinner: true,
    );
  }

  /// Empty state - there is nothing to show, but everything is fine.
  factory StatusView.empty({
    required String title,
    String subtitle = '',
    IconData icon = Icons.inbox_outlined,
    VoidCallback? onRetry,
    String retryLabel = 'Refresh',
    Key? key,
  }) {
    return StatusView._(
      key: key,
      icon: icon,
      title: title,
      subtitle: subtitle,
      tint: CorviaColors.accentLight,
      action: onRetry,
      actionLabel: onRetry == null ? null : retryLabel,
    );
  }

  /// Error state - something failed while loading. The [error] argument is
  /// only logged to the console; the user sees [friendlyMessage].
  factory StatusView.error({
    required String friendlyMessage,
    Object? error,
    StackTrace? stackTrace,
    VoidCallback? onRetry,
    Key? key,
  }) {
    if (kDebugMode) {
      // ignore: avoid_print
      debugPrint('[StatusView.error] $friendlyMessage\n$error\n$stackTrace');
    }
    return StatusView._(
      key: key,
      icon: Icons.cloud_off,
      title: friendlyMessage,
      subtitle: 'Pull to refresh, or try again in a moment.',
      tint: CorviaColors.warning,
      action: onRetry,
      actionLabel: onRetry == null ? null : 'Try again',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Screen readers announce the icon + text block as a single message.
    final semanticsMessage = subtitle.isEmpty ? title : '$title. $subtitle';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The decorative icon and the visible text are collapsed into one
            // labelled node; loading uses a live region so state changes are
            // announced. The action button below keeps its own semantics.
            Semantics(
              container: true,
              liveRegion: spinner,
              label: semanticsMessage,
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (spinner)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child:
                          CircularProgressIndicator(color: CorviaColors.accent),
                    )
                  else
                    Icon(icon, size: 56, color: tint),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CorviaColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: CorviaColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: action,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact variant used inline (e.g. inside a card) where a full-screen
/// message would be too much.
class InlineStatus extends StatelessWidget {
  const InlineStatus({
    super.key,
    required this.icon,
    required this.message,
    this.tint,
  });

  final IconData icon;
  final String message;
  // Null falls back to a theme-aware secondary text colour at build time.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? CorviaColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: color, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
