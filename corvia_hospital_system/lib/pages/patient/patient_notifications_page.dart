import 'package:flutter/material.dart';

import '../../services/patient_notification_service.dart';
import '../../theme/app_theme.dart';
import 'patient_transfer_status_page.dart';

enum _NotificationFilter {
  all,
  unread,
  transfers,
}

class PatientNotificationsPage extends StatefulWidget {
  const PatientNotificationsPage({
    super.key,
  });

  @override
  State<PatientNotificationsPage> createState() =>
      _PatientNotificationsPageState();
}

class _PatientNotificationsPageState extends State<PatientNotificationsPage> {
  final PatientNotificationService _service = PatientNotificationService();

  late final Stream<PatientNotificationState> _stateStream;

  _NotificationFilter _filter = _NotificationFilter.all;

  bool _markingAllRead = false;
  String? _actionNotificationId;

  @override
  void initState() {
    super.initState();

    _stateStream = _service.watchNotificationState();
  }

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? CorviaColors.danger : CorviaColors.accentDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _markAllAsRead() async {
    if (_markingAllRead) {
      return;
    }

    setState(() {
      _markingAllRead = true;
    });

    try {
      final count = await _service.markAllAsRead();

      _showMessage(
        count == 1
            ? '1 notification marked as read.'
            : '$count notifications marked as read.',
      );
    } catch (error) {
      _showMessage(
        'Notifications could not be updated: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingAllRead = false;
        });
      }
    }
  }

  Future<void> _openNotification(
    PatientNotificationRecord notification,
  ) async {
    if (_actionNotificationId != null) {
      return;
    }

    setState(() {
      _actionNotificationId = notification.notificationId;
    });

    try {
      await _service.openNotification(notification);

      if (!mounted) {
        return;
      }

      final transferId = notification.transferId;

      if (notification.isInterhospitalTransfer &&
          transferId != null &&
          transferId.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) {
              return PatientTransferStatusPage(
                transferId: transferId,
              );
            },
          ),
        );
      }
    } catch (error) {
      _showMessage(
        'Notification could not open: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionNotificationId = null;
        });
      }
    }
  }

  List<PatientNotificationRecord> _filteredNotifications(
    PatientNotificationState state,
  ) {
    switch (_filter) {
      case _NotificationFilter.unread:
        return state.notifications
            .where(
              (notification) => notification.isUnread,
            )
            .toList();

      case _NotificationFilter.transfers:
        return state.transferNotifications;

      case _NotificationFilter.all:
        return state.notifications;
    }
  }

  IconData _notificationIcon(
    PatientNotificationRecord notification,
  ) {
    if (notification.isTransferRequested) {
      return Icons.send_rounded;
    }

    if (notification.isTransferAccepted) {
      return Icons.check_circle_rounded;
    }

    if (notification.isTransferReady) {
      return Icons.inventory_rounded;
    }

    if (notification.isTransferInTransit) {
      return Icons.local_shipping_rounded;
    }

    if (notification.isTransferReceived) {
      return Icons.login_rounded;
    }

    if (notification.isTransferCompleted) {
      return Icons.task_alt_rounded;
    }

    if (notification.isTransferRejected) {
      return Icons.cancel_rounded;
    }

    if (notification.isTransferCancelled) {
      return Icons.block_rounded;
    }

    return Icons.notifications_rounded;
  }

  Color _notificationColor(
    PatientNotificationRecord notification,
  ) {
    if (notification.isTransferCompleted ||
        notification.isTransferReceived ||
        notification.isTransferAccepted) {
      return CorviaColors.success;
    }

    if (notification.isTransferRejected || notification.isTransferCancelled) {
      return CorviaColors.danger;
    }

    if (notification.isTransferRequested || notification.isTransferReady) {
      return CorviaColors.warning;
    }

    return context.cAccentReadable;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        backgroundColor: context.cBgSecondary,
        foregroundColor: context.cTextPrimary,
        title: const Text('Notifications'),
        actions: [
          TextButton.icon(
            onPressed: _markingAllRead ? null : _markAllAsRead,
            icon: _markingAllRead
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.done_all_rounded,
                  ),
            label: const Text(
              'Mark all read',
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<PatientNotificationState>(
          stream: _stateStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState(
                snapshot.error.toString(),
              );
            }

            if (!snapshot.hasData) {
              return Center(
                child: CircularProgressIndicator(
                  color: context.cAccentReadable,
                ),
              );
            }

            final state = snapshot.data!;

            final notifications = _filteredNotifications(state);

            return Column(
              children: [
                _buildSummaryHeader(state),
                _buildFilters(state),
                Expanded(
                  child: notifications.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: notifications.length,
                          itemBuilder: (
                            context,
                            index,
                          ) {
                            return _notificationCard(
                              notifications[index],
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(
    PatientNotificationState state,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        18,
        16,
        18,
        14,
      ),
      color: context.cBgSecondary,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.cAccentReadable.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: context.cAccentReadable,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.unreadCount == 0
                      ? 'You are up to date'
                      : '${state.unreadCount} unread notifications',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${state.transferNotifications.length} hospital transfer updates',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (state.unreadCount > 0)
            Container(
              constraints: const BoxConstraints(
                minWidth: 32,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: CorviaColors.danger,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                state.unreadCount > 99 ? '99+' : state.unreadCount.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilters(
    PatientNotificationState state,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        border: Border(
          bottom: BorderSide(
            color: context.cDivider,
          ),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip(
            label: 'All (${state.notifications.length})',
            filter: _NotificationFilter.all,
          ),
          _filterChip(
            label: 'Unread (${state.unreadCount})',
            filter: _NotificationFilter.unread,
          ),
          _filterChip(
            label: 'Transfers (${state.transferNotifications.length})',
            filter: _NotificationFilter.transfers,
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required _NotificationFilter filter,
  }) {
    final selected = _filter == filter;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filter = filter;
        });
      },
    );
  }

  Widget _notificationCard(
    PatientNotificationRecord notification,
  ) {
    final color = _notificationColor(notification);

    final opening = _actionNotificationId == notification.notificationId;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: notification.isUnread
            ? color.withValues(alpha: 0.055)
            : context.cBgSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: notification.isUnread
              ? color.withValues(alpha: 0.28)
              : context.cDivider,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: opening
              ? null
              : () {
                  _openNotification(notification);
                },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _notificationIcon(notification),
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontWeight: notification.isUnread
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (notification.isUnread)
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        notification.body,
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            notification.displayAge,
                            style: TextStyle(
                              color: context.cTextSecondary,
                              fontSize: 10,
                            ),
                          ),
                          if (notification.isInterhospitalTransfer)
                            _smallBadge(
                              'Hospital Transfer',
                              color,
                            ),
                          if (notification.transferNumber != null)
                            _smallBadge(
                              notification.transferNumber!,
                              context.cAccentReadable,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                opening
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        color: context.cTextSecondary,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallBadge(
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String title;
    String message;

    switch (_filter) {
      case _NotificationFilter.unread:
        title = 'No unread notifications';
        message = 'You have read all your notifications.';
        break;

      case _NotificationFilter.transfers:
        title = 'No transfer updates';
        message = 'Hospital transfer updates will appear here.';
        break;

      case _NotificationFilter.all:
        title = 'No notifications';
        message = 'New hospital updates will appear here.';
        break;
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 480,
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              color: context.cAccentReadable,
              size: 46,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    String error,
  ) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 520,
        ),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: CorviaColors.danger.withValues(
            alpha: 0.07,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: CorviaColors.danger.withValues(
              alpha: 0.24,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: CorviaColors.danger,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              'Notifications could not load',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
