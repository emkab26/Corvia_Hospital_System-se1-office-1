import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/app_theme.dart';
import '../patient_pharmacy_status_page.dart';

class PatientNotificationsPage extends StatefulWidget {
  const PatientNotificationsPage({
    super.key,
  });

  @override
  State<PatientNotificationsPage> createState() =>
      _PatientNotificationsPageState();
}

class _PatientNotificationsPageState extends State<PatientNotificationsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _markingAllRead = false;

  String? _error;
  String? _openingNotificationId;

  String _selectedFilter = 'All';

  List<_PatientNotification> _notifications = [];

  static const List<String> _filters = [
    'All',
    'Unread',
    'Pharmacy',
    'Appointments',
    'Specialist',
    'Lab',
  ];

  @override
  void initState() {
    super.initState();

    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception(
          'No active Corvia session was found.',
        );
      }

      final response = await _supabase
          .from('user_notifications')
          .select()
          .eq('user_id', user.id)
          .order(
            'created_at',
            ascending: false,
          )
          .limit(150)
          .timeout(
            const Duration(seconds: 20),
          );

      final rows = response
              .whereType<Map>()
              .map(
                (row) => Map<String, dynamic>.from(row),
              )
              .toList();

      var notifications = rows
          .map(
            _PatientNotification.fromMap,
          )
          .toList();

      notifications = await _attachPharmacyDetails(
        notifications,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _notifications = notifications;
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'The server took too long to load notifications.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _cleanError(error);
      });
    }
  }

  Future<List<_PatientNotification>> _attachPharmacyDetails(
    List<_PatientNotification> notifications,
  ) async {
    final dispenseIds = notifications
        .where(
          (notification) {
            return notification.isPharmacy && notification.referenceId != null;
          },
        )
        .map(
          (notification) => notification.referenceId!,
        )
        .toSet()
        .toList();

    if (dispenseIds.isEmpty) {
      return notifications;
    }

    try {
      final response = await _supabase
          .from('prescription_dispenses')
          .select(
            'id, status, collection_reference, '
            'received_at, verified_at, preparing_at, '
            'ready_at, collected_at',
          )
          .inFilter(
            'id',
            dispenseIds,
          )
          .timeout(
            const Duration(seconds: 15),
          );

      final dispenseMap = <String, Map<String, dynamic>>{};

      for (final rawRow in response.whereType<Map>()) {
        final row = Map<String, dynamic>.from(rawRow);

        final id = row['id']?.toString().trim();

        if (id != null && id.isNotEmpty) {
          dispenseMap[id] = row;
        }
      }

      return notifications.map(
        (notification) {
          final referenceId = notification.referenceId;

          if (referenceId == null) {
            return notification;
          }

          final dispense = dispenseMap[referenceId];

          if (dispense == null) {
            return notification;
          }

          return notification.copyWith(
            collectionReference: _nullableText(
              dispense['collection_reference'],
            ),
            pharmacyStatus: _nullableText(
              dispense['status'],
            ),
          );
        },
      ).toList();
    } catch (error) {
      debugPrint(
        'Notification pharmacy detail lookup failed: $error',
      );

      return notifications;
    }
  }

  Future<void> _markOneRead(
    _PatientNotification notification,
  ) async {
    if (notification.isRead || notification.id.trim().isEmpty) {
      return;
    }

    try {
      await _supabase.from('user_notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq(
        'id',
        notification.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _notifications = _notifications.map(
          (item) {
            if (item.id == notification.id) {
              return item.copyWith(
                isRead: true,
              );
            }

            return item;
          },
        ).toList();
      });
    } catch (error) {
      _showMessage(
        'Could not mark notification as read. '
        '${_cleanError(error)}',
      );
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAllRead) {
      return;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      return;
    }

    setState(() {
      _markingAllRead = true;
    });

    try {
      await _supabase
          .from('user_notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq(
            'user_id',
            user.id,
          )
          .eq(
            'is_read',
            false,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _notifications = _notifications
            .map(
              (item) => item.copyWith(
                isRead: true,
              ),
            )
            .toList();
      });

      _showMessage(
        'All notifications marked as read.',
      );
    } catch (error) {
      _showMessage(
        'Could not mark all notifications as read. '
        '${_cleanError(error)}',
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
    _PatientNotification notification,
  ) async {
    if (_openingNotificationId != null) {
      return;
    }

    setState(() {
      _openingNotificationId = notification.id;
    });

    try {
      await _markOneRead(notification);

      if (!mounted) {
        return;
      }

      if (notification.isPharmacy) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PatientPharmacyStatusPage(),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingNotificationId = null;
        });
      }
    }
  }

  String _cleanError(Object error) {
    if (error is PostgrestException) {
      final details = error.details?.toString().trim() ?? '';

      if (details.isNotEmpty &&
          details.toLowerCase() != 'null' &&
          details != error.message) {
        return '${error.message} $details';
      }

      return error.message;
    }

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
  }

  static String? _nullableText(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Unknown date';
    }

    final local = value.toLocal();

    final day = local.day.toString().padLeft(2, '0');

    final month = local.month.toString().padLeft(2, '0');

    final hour = local.hour.toString().padLeft(2, '0');

    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/${local.year} • '
        '$hour:$minute';
  }

  Color _typeColor(String type) {
    final cleaned =
        type.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    switch (cleaned) {
      case 'pharmacy_received':
        return Colors.orange.shade800;

      case 'pharmacy_verified':
        return Colors.blue.shade700;

      case 'pharmacy_preparing':
        return Colors.deepPurple;

      case 'pharmacy_ready':
      case 'pharmacy_ready_for_collection':
        return Colors.green.shade700;

      case 'pharmacy_collected':
        return Colors.teal.shade700;

      case 'pharmacy_unable_to_dispense':
      case 'pharmacy_cancelled':
        return CorviaColors.danger;
    }

    if (cleaned.contains('pharmacy') ||
        cleaned.contains('dispense') ||
        cleaned.contains('pharmacist')) {
      return Colors.teal.shade700;
    }

    if (cleaned.contains('specialist')) {
      return Colors.deepPurpleAccent;
    }

    if (cleaned.contains('appointment')) {
      return Colors.green.shade700;
    }

    if (cleaned.contains('lab')) {
      return Colors.cyan.shade700;
    }

    if (cleaned.contains('prescription')) {
      return Colors.orange.shade800;
    }

    if (cleaned.contains('emergency') || cleaned.contains('urgent')) {
      return CorviaColors.danger;
    }

    return context.cAccentReadable;
  }

  IconData _typeIcon(String type) {
    final cleaned =
        type.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    switch (cleaned) {
      case 'pharmacy_received':
        return Icons.move_to_inbox_outlined;

      case 'pharmacy_verified':
        return Icons.verified_outlined;

      case 'pharmacy_preparing':
        return Icons.medication_outlined;

      case 'pharmacy_ready':
      case 'pharmacy_ready_for_collection':
        return Icons.inventory_2_outlined;

      case 'pharmacy_collected':
        return Icons.check_circle_outline;

      case 'pharmacy_unable_to_dispense':
      case 'pharmacy_cancelled':
        return Icons.warning_amber_rounded;
    }

    if (cleaned.contains('pharmacy') ||
        cleaned.contains('dispense') ||
        cleaned.contains('pharmacist')) {
      return Icons.local_pharmacy_outlined;
    }

    if (cleaned.contains('specialist')) {
      return Icons.health_and_safety_outlined;
    }

    if (cleaned.contains('appointment')) {
      return Icons.event_available_outlined;
    }

    if (cleaned.contains('lab')) {
      return Icons.biotech_outlined;
    }

    if (cleaned.contains('prescription')) {
      return Icons.medication_outlined;
    }

    if (cleaned.contains('emergency') || cleaned.contains('urgent')) {
      return Icons.emergency_outlined;
    }

    return Icons.notifications_outlined;
  }

  String _typeLabel(String type) {
    final cleaned =
        type.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    switch (cleaned) {
      case 'pharmacy_received':
        return 'Pharmacy Received';

      case 'pharmacy_verified':
        return 'Prescription Verified';

      case 'pharmacy_preparing':
        return 'Medication Preparing';

      case 'pharmacy_ready':
      case 'pharmacy_ready_for_collection':
        return 'Ready for Collection';

      case 'pharmacy_collected':
        return 'Medication Collected';

      case 'pharmacy_unable_to_dispense':
        return 'Unable to Dispense';

      case 'pharmacy_cancelled':
        return 'Pharmacy Cancelled';
    }

    if (cleaned.contains('specialist')) {
      return 'Specialist';
    }

    if (cleaned.contains('appointment')) {
      return 'Appointment';
    }

    if (cleaned.contains('lab')) {
      return 'Lab Result';
    }

    if (cleaned.contains('prescription')) {
      return 'Prescription';
    }

    return cleaned
        .split('_')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
      (word) {
        return '${word[0].toUpperCase()}'
            '${word.substring(1).toLowerCase()}';
      },
    ).join(' ');
  }

  List<_PatientNotification> get _visibleNotifications {
    return _notifications.where(
      (notification) {
        switch (_selectedFilter) {
          case 'Unread':
            return !notification.isRead;

          case 'Pharmacy':
            return notification.isPharmacy;

          case 'Appointments':
            return notification.type.toLowerCase().contains('appointment');

          case 'Specialist':
            return notification.type.toLowerCase().contains('specialist');

          case 'Lab':
            return notification.type.toLowerCase().contains('lab');

          case 'All':
          default:
            return true;
        }
      },
    ).toList();
  }

  int get _unreadCount {
    return _notifications.where(
      (notification) {
        return !notification.isRead;
      },
    ).length;
  }

  int get _pharmacyCount {
    return _notifications.where(
      (notification) {
        return notification.isPharmacy;
      },
    ).length;
  }

  int get _readyPharmacyCount {
    return _notifications.where(
      (notification) {
        return notification.isPharmacy &&
            notification.effectivePharmacyStatus == 'ready_for_collection';
      },
    ).length;
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _unreadCount;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: Text(
          unreadCount == 0 ? 'Notifications' : 'Notifications ($unreadCount)',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadNotifications,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Mark all as read',
            onPressed:
                unreadCount == 0 || _markingAllRead ? null : _markAllRead,
            icon: _markingAllRead
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.done_all_rounded,
                  ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_notifications.isEmpty) {
      return _buildEmptyState();
    }

    final visibleNotifications = _visibleNotifications;

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          28,
        ),
        children: [
          _buildSummary(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filters.map(
              (filter) {
                return ChoiceChip(
                  label: Text(filter),
                  selected: _selectedFilter == filter,
                  onSelected: (_) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                  },
                );
              },
            ).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            '$_selectedFilter Notifications '
            '(${visibleNotifications.length})',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (visibleNotifications.isEmpty)
            _buildFilteredEmptyState()
          else
            ...visibleNotifications.map(
              _buildNotificationCard,
            ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final items = [
      _NotificationSummaryItem(
        label: 'Unread',
        value: _unreadCount,
        icon: Icons.mark_email_unread_outlined,
        color: CorviaColors.warning,
      ),
      _NotificationSummaryItem(
        label: 'Pharmacy',
        value: _pharmacyCount,
        icon: Icons.local_pharmacy_outlined,
        color: Colors.teal.shade700,
      ),
      _NotificationSummaryItem(
        label: 'Ready',
        value: _readyPharmacyCount,
        icon: Icons.inventory_2_outlined,
        color: Colors.green.shade700,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final columns = constraints.maxWidth >= 720
            ? 3
            : constraints.maxWidth >= 440
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 105,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final item = items[index];

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: item.color.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      item.icon,
                      color: item.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.value}',
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNotificationCard(
    _PatientNotification notification,
  ) {
    final color = _typeColor(
      notification.type,
    );

    final opening = _openingNotificationId == notification.id;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Material(
        color: notification.isRead
            ? context.cBgSecondary
            : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: opening
              ? null
              : () {
                  _openNotification(notification);
                },
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: notification.isRead
                    ? context.cDivider
                    : color.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(
                    alpha: 0.16,
                  ),
                  child: opening
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        )
                      : Icon(
                          _typeIcon(
                            notification.type,
                          ),
                          color: color,
                        ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontSize: 15,
                                fontWeight: notification.isRead
                                    ? FontWeight.w700
                                    : FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _NotificationTypeBadge(
                            label: _typeLabel(
                              notification.type,
                            ),
                            color: color,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notification.message,
                        style: TextStyle(
                          color: context.cTextSecondary,
                          height: 1.35,
                        ),
                      ),
                      if (notification.isPharmacy &&
                          notification.collectionReference != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: color.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: color.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.qr_code_2,
                                size: 18,
                                color: color,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Collection reference: '
                                  '${notification.collectionReference}',
                                  style: TextStyle(
                                    color: context.cTextPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatDate(
                                notification.createdAt,
                              ),
                              style: TextStyle(
                                color: context.cTextMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (notification.isPharmacy)
                            Text(
                              'Open Pharmacy Status',
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!notification.isRead) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.cloud_off_outlined,
            color: CorviaColors.danger,
            size: 58,
          ),
          const SizedBox(height: 16),
          Text(
            'Notifications could not load',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loadNotifications,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text(
              'Try Again',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.notifications_none_rounded,
            color: context.cTextSecondary,
            size: 62,
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pharmacy updates, specialist requests, '
            'appointment changes, lab results and Corvia '
            'alerts will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            color: context.cTextSecondary,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            'No $_selectedFilter notifications',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No notifications match the selected filter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientNotification {
  const _PatientNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
    required this.referenceType,
    required this.referenceId,
    required this.collectionReference,
    required this.pharmacyStatus,
  });

  factory _PatientNotification.fromMap(
    Map<String, dynamic> map,
  ) {
    final titleText = map['title']?.toString().trim() ?? '';

    final bodyText = map['body']?.toString().trim() ?? '';

    final messageText = map['message']?.toString().trim() ?? '';

    final notificationType = map['notification_type']?.toString().trim() ?? '';

    final legacyType = map['type']?.toString().trim() ?? '';

    final referenceType = _firstAvailableText([
      map['reference_type'],
      map['related_table'],
    ]);

    final referenceId = _firstAvailableText([
      map['reference_id'],
      map['related_id'],
    ]);

    return _PatientNotification(
      id: map['id']?.toString() ?? '',
      title: titleText.isEmpty ? 'Corvia notification' : titleText,
      message: bodyText.isNotEmpty
          ? bodyText
          : messageText.isNotEmpty
              ? messageText
              : 'You have a new notification.',
      type: notificationType.isNotEmpty
          ? notificationType
          : legacyType.isNotEmpty
              ? legacyType
              : 'general',
      isRead: map['is_read'] == true,
      createdAt: DateTime.tryParse(
        map['created_at']?.toString() ?? '',
      ),
      referenceType: referenceType,
      referenceId: referenceId,
      collectionReference: null,
      pharmacyStatus: null,
    );
  }

  final String id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime? createdAt;

  final String? referenceType;
  final String? referenceId;
  final String? collectionReference;
  final String? pharmacyStatus;

  bool get isPharmacy {
    final combined = [
      type,
      referenceType ?? '',
    ].join(' ').toLowerCase();

    return combined.contains('pharmacy') ||
        combined.contains('pharmacist') ||
        combined.contains('dispense') ||
        combined.contains(
          'prescription_dispenses',
        );
  }

  String get effectivePharmacyStatus {
    final stored = pharmacyStatus?.trim().toLowerCase();

    if (stored != null && stored.isNotEmpty) {
      return stored;
    }

    final cleaned =
        type.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    if (cleaned.contains(
      'ready_for_collection',
    )) {
      return 'ready_for_collection';
    }

    if (cleaned.contains('collected')) {
      return 'collected';
    }

    if (cleaned.contains('preparing')) {
      return 'preparing';
    }

    if (cleaned.contains('verified')) {
      return 'verified';
    }

    if (cleaned.contains(
      'unable_to_dispense',
    )) {
      return 'unable_to_dispense';
    }

    if (cleaned.contains('cancelled')) {
      return 'cancelled';
    }

    if (cleaned.contains('received')) {
      return 'received';
    }

    return '';
  }

  _PatientNotification copyWith({
    bool? isRead,
    String? collectionReference,
    String? pharmacyStatus,
  }) {
    return _PatientNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      referenceType: referenceType,
      referenceId: referenceId,
      collectionReference: collectionReference ?? this.collectionReference,
      pharmacyStatus: pharmacyStatus ?? this.pharmacyStatus,
    );
  }

  static String? _firstAvailableText(
    List<dynamic> values,
  ) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return null;
  }
}

class _NotificationSummaryItem {
  const _NotificationSummaryItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _NotificationTypeBadge extends StatelessWidget {
  const _NotificationTypeBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 145,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(
            alpha: 0.22,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
