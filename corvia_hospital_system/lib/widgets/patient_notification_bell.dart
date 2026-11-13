import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/patient/patient_notifications_page.dart';
import '../services/patient_notification_service.dart';
import '../theme/app_theme.dart';

class PatientNotificationBell extends StatefulWidget {
  const PatientNotificationBell({
    super.key,
  });

  @override
  State<PatientNotificationBell> createState() =>
      _PatientNotificationBellState();
}

class _PatientNotificationBellState extends State<PatientNotificationBell> {
  final PatientNotificationService _service = PatientNotificationService();

  late final Stream<List<PatientNotificationRecord>> _notificationsStream;
  StreamSubscription<List<PatientNotificationRecord>>? _calledSubscription;

  final Set<String> _knownNotificationIds = <String>{};
  bool _receivedInitialNotifications = false;

  @override
  void initState() {
    super.initState();

    _notificationsStream = _createNotificationStream();
    _calledSubscription = _notificationsStream.listen(
      _handleNotifications,
      onError: (Object error) {
        debugPrint('Patient called notification could not update: $error');
      },
    );
  }

  Stream<List<PatientNotificationRecord>> _createNotificationStream() {
    try {
      return _service.watchNotifications().asBroadcastStream();
    } catch (error) {
      debugPrint(
        'Patient notification bell could not start: $error',
      );

      return Stream<List<PatientNotificationRecord>>.value(
        const <PatientNotificationRecord>[],
      ).asBroadcastStream();
    }
  }

  void _handleNotifications(List<PatientNotificationRecord> notifications) {
    if (!_receivedInitialNotifications) {
      _knownNotificationIds.addAll(
        notifications.map((notification) => notification.notificationId),
      );
      _receivedInitialNotifications = true;
      return;
    }

    final newlyCalled = notifications.where(
      (notification) =>
          notification.eventType == 'reception_queue_called' &&
          notification.isUnread &&
          !_knownNotificationIds.contains(notification.notificationId),
    );

    _knownNotificationIds.addAll(
      notifications.map((notification) => notification.notificationId),
    );

    if (newlyCalled.isEmpty || !mounted) {
      return;
    }

    final notification = newlyCalled.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          content: Text(
            '${notification.title}: ${notification.body}',
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: _openNotifications,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _calledSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openNotifications() async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          return const PatientNotificationsPage();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PatientNotificationRecord>>(
      stream: _notificationsStream,
      initialData: const <PatientNotificationRecord>[],
      builder: (context, snapshot) {
        final unreadCount =
            (snapshot.data ?? const <PatientNotificationRecord>[])
                .where((notification) => notification.isUnread)
                .length;

        return Semantics(
          button: true,
          label: unreadCount > 0
              ? 'Notifications, $unreadCount unread'
              : 'Notifications, no unread notifications',
          child: IconButton(
            tooltip: unreadCount > 0
                ? '$unreadCount unread notifications'
                : 'Notifications',
            onPressed: _openNotifications,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_rounded,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: -7,
                    right: -9,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: CorviaColors.danger,
                        borderRadius: BorderRadius.circular(
                          999,
                        ),
                        border: Border.all(
                          color: context.cBgSecondary,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
