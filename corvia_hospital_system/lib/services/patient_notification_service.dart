import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class PatientNotificationService {
  PatientNotificationService({
    SupabaseClient? supabase,
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String tableName = 'patient_notifications';

  static const String notificationSelect = '''
    id,
    recipient_profile_id,
    patient_id,
    hospital_id,
    event_type,
    title,
    body,
    deep_link,
    entity_type,
    entity_id,
    deduplication_key,
    data,
    is_read,
    read_at,
    expires_at,
    created_at
  ''';

  // ===========================================================================
  // AUTH HELPERS
  // ===========================================================================

  Future<String> _requireProfileId() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be signed in to view notifications.',
      );
    }

    return user.id;
  }

  // ===========================================================================
  // VALUE HELPERS
  // ===========================================================================

  List<Map<String, dynamic>> _rows(
    dynamic value,
  ) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(row),
        )
        .toList();
  }

  bool _boolean(
    dynamic value,
  ) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase();

    return text == 'true' || text == '1' || text == 'yes';
  }

  int _integer(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  bool _rpcBoolean(
    dynamic response,
  ) {
    if (response is bool) {
      return response;
    }

    if (response is num) {
      return response != 0;
    }

    if (response is String) {
      final value = response.trim().toLowerCase();

      return value == 'true' || value == '1';
    }

    if (response is List && response.isNotEmpty) {
      return _rpcBoolean(response.first);
    }

    if (response is Map) {
      final map = Map<String, dynamic>.from(response);

      return _boolean(
        map['success'] ?? map['result'] ?? map['updated'],
      );
    }

    return false;
  }

  int _rpcInteger(
    dynamic response,
  ) {
    if (response is int) {
      return response;
    }

    if (response is num) {
      return response.toInt();
    }

    if (response is String) {
      return int.tryParse(response) ?? 0;
    }

    if (response is List && response.isNotEmpty) {
      return _rpcInteger(response.first);
    }

    if (response is Map) {
      final map = Map<String, dynamic>.from(response);

      return _integer(
        map['count'] ?? map['updated_count'] ?? map['result'],
      );
    }

    return 0;
  }

  // ===========================================================================
  // LOAD NOTIFICATIONS
  // ===========================================================================

  Future<List<PatientNotificationRecord>> loadNotifications({
    int limit = 100,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final profileId = await _requireProfileId();

    if (limit <= 0) {
      return [];
    }

    final safeOffset = offset < 0 ? 0 : offset;

    final finalIndex = safeOffset + limit - 1;

    dynamic query = _supabase.from(tableName).select(notificationSelect).eq(
          'recipient_profile_id',
          profileId,
        );

    if (unreadOnly) {
      query = query.eq(
        'is_read',
        false,
      );
    }

    final response = await query
        .order(
          'created_at',
          ascending: false,
        )
        .range(
          safeOffset,
          finalIndex,
        );

    return _rows(response)
        .map(
          PatientNotificationRecord.fromMap,
        )
        .where(
          (notification) => !notification.isExpired,
        )
        .toList();
  }

  Future<List<PatientNotificationRecord>> loadUnreadNotifications({
    int limit = 100,
    int offset = 0,
  }) {
    return loadNotifications(
      limit: limit,
      offset: offset,
      unreadOnly: true,
    );
  }

  Future<List<PatientNotificationRecord>> loadTransferNotifications({
    int limit = 100,
    int offset = 0,
  }) async {
    final notifications = await loadNotifications(
      limit: limit,
      offset: offset,
    );

    return notifications
        .where(
          (notification) => notification.isInterhospitalTransfer,
        )
        .toList();
  }

  // ===========================================================================
  // REALTIME STREAMS
  // ===========================================================================

  Stream<List<PatientNotificationRecord>> watchNotifications({
    bool unreadOnly = false,
  }) {
    return Stream.fromFuture(_requireProfileId()).asyncExpand(
      (profileId) {
        return _supabase
            .from(tableName)
            .stream(
              primaryKey: const ['id'],
            )
            .eq(
              'recipient_profile_id',
              profileId,
            )
            .order(
              'created_at',
              ascending: false,
            )
            .map(
              (rows) {
                final notifications = rows
                    .map(
                      PatientNotificationRecord.fromMap,
                    )
                    .where(
                      (notification) => !notification.isExpired,
                    )
                    .where(
                      (notification) => !unreadOnly || !notification.isRead,
                    )
                    .toList();

                notifications.sort(
                  (
                    first,
                    second,
                  ) {
                    final firstDate = first.createdAt ??
                        DateTime.fromMillisecondsSinceEpoch(
                          0,
                        );

                    final secondDate = second.createdAt ??
                        DateTime.fromMillisecondsSinceEpoch(
                          0,
                        );

                    return secondDate.compareTo(
                      firstDate,
                    );
                  },
                );

                return notifications;
              },
            );
      },
    );
  }

  Stream<List<PatientNotificationRecord>> watchUnreadNotifications() {
    return watchNotifications(
      unreadOnly: true,
    );
  }

  Stream<List<PatientNotificationRecord>> watchTransferNotifications() {
    return watchNotifications().map(
      (notifications) {
        return notifications
            .where(
              (notification) => notification.isInterhospitalTransfer,
            )
            .toList();
      },
    );
  }

  Stream<int> watchUnreadCount() {
    return watchNotifications().map(
      (notifications) {
        return notifications
            .where(
              (notification) => !notification.isRead,
            )
            .length;
      },
    ).distinct();
  }

  Stream<PatientNotificationState> watchNotificationState() {
    return watchNotifications().map(
      (notifications) {
        final unreadCount = notifications
            .where(
              (notification) => !notification.isRead,
            )
            .length;

        final transferNotifications = notifications
            .where(
              (notification) => notification.isInterhospitalTransfer,
            )
            .toList();

        return PatientNotificationState(
          notifications: notifications,
          transferNotifications: transferNotifications,
          unreadCount: unreadCount,
        );
      },
    );
  }

  // ===========================================================================
  // UNREAD COUNT
  // ===========================================================================

  Future<int> getUnreadCount() async {
    await _requireProfileId();

    final response = await _supabase.rpc(
      'corvia_mh_patient_notification_unread_count',
    );

    return _rpcInteger(response);
  }

  // ===========================================================================
  // MARK AS READ
  // ===========================================================================

  Future<bool> markAsRead(
    String notificationId,
  ) async {
    await _requireProfileId();

    if (notificationId.trim().isEmpty) {
      throw ArgumentError(
        'Notification ID is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_mark_patient_notification_read',
      params: {
        'p_notification_id': notificationId.trim(),
      },
    );

    return _rpcBoolean(response);
  }

  Future<int> markAllAsRead() async {
    await _requireProfileId();

    final response = await _supabase.rpc(
      'corvia_mh_mark_all_patient_notifications_read',
    );

    return _rpcInteger(response);
  }

  Future<bool> openNotification(
    PatientNotificationRecord notification,
  ) async {
    if (notification.isRead) {
      return true;
    }

    return markAsRead(
      notification.notificationId,
    );
  }

  // ===========================================================================
  // SINGLE NOTIFICATION
  // ===========================================================================

  Future<PatientNotificationRecord?> getNotificationById(
    String notificationId,
  ) async {
    final profileId = await _requireProfileId();

    if (notificationId.trim().isEmpty) {
      return null;
    }

    final response = await _supabase
        .from(tableName)
        .select(notificationSelect)
        .eq(
          'id',
          notificationId.trim(),
        )
        .eq(
          'recipient_profile_id',
          profileId,
        )
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return PatientNotificationRecord.fromMap(
      Map<String, dynamic>.from(response),
    );
  }
}

// =============================================================================
// PATIENT NOTIFICATION RECORD
// =============================================================================

class PatientNotificationRecord {
  const PatientNotificationRecord({
    required this.notificationId,
    required this.recipientProfileId,
    required this.patientId,
    required this.hospitalId,
    required this.eventType,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.entityType,
    required this.entityId,
    required this.deduplicationKey,
    required this.data,
    required this.isRead,
    required this.readAt,
    required this.expiresAt,
    required this.createdAt,
  });

  final String notificationId;
  final String recipientProfileId;
  final String patientId;

  final String? hospitalId;

  final String eventType;
  final String title;
  final String body;

  final String? deepLink;

  final String? entityType;
  final String? entityId;

  final String deduplicationKey;

  final Map<String, dynamic> data;

  final bool isRead;

  final DateTime? readAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory PatientNotificationRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    Map<String, dynamic> readData(
      dynamic value,
    ) {
      if (value is Map<String, dynamic>) {
        return value;
      }

      if (value is Map) {
        return Map<String, dynamic>.from(
          value,
        );
      }

      if (value is String && value.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(value);

          if (decoded is Map) {
            return Map<String, dynamic>.from(
              decoded,
            );
          }
        } catch (_) {
          return {};
        }
      }

      return {};
    }

    bool readBoolean(
      dynamic value,
    ) {
      if (value is bool) {
        return value;
      }

      if (value is num) {
        return value != 0;
      }

      final text = value?.toString().trim().toLowerCase();

      return text == 'true' || text == '1' || text == 'yes';
    }

    DateTime? readDate(
      dynamic value,
    ) {
      if (value == null) {
        return null;
      }

      return DateTime.tryParse(
        value.toString(),
      )?.toLocal();
    }

    return PatientNotificationRecord(
      notificationId: map['id']?.toString() ?? '',
      recipientProfileId: map['recipient_profile_id']?.toString() ?? '',
      patientId: map['patient_id']?.toString() ?? '',
      hospitalId: map['hospital_id']?.toString(),
      eventType: map['event_type']?.toString() ?? 'general',
      title: map['title']?.toString() ?? 'Notification',
      body: map['body']?.toString() ?? '',
      deepLink: map['deep_link']?.toString(),
      entityType: map['entity_type']?.toString(),
      entityId: map['entity_id']?.toString(),
      deduplicationKey: map['deduplication_key']?.toString() ?? '',
      data: readData(
        map['data'],
      ),
      isRead: readBoolean(
        map['is_read'],
      ),
      readAt: readDate(
        map['read_at'],
      ),
      expiresAt: readDate(
        map['expires_at'],
      ),
      createdAt: readDate(
        map['created_at'],
      ),
    );
  }

  bool get isExpired {
    final expiry = expiresAt;

    if (expiry == null) {
      return false;
    }

    return expiry.isBefore(
      DateTime.now(),
    );
  }

  bool get isUnread {
    return !isRead;
  }

  bool get isInterhospitalTransfer {
    return eventType.startsWith(
          'interhospital_transfer',
        ) ||
        entityType == 'interhospital_transfer' ||
        data.containsKey('transfer_id');
  }

  bool get isTransferRequested {
    return eventType == 'interhospital_transfer_requested';
  }

  bool get isTransferAccepted {
    return eventType == 'interhospital_transfer_accepted';
  }

  bool get isTransferReady {
    return eventType == 'interhospital_transfer_ready';
  }

  bool get isTransferInTransit {
    return eventType == 'interhospital_transfer_in_transit';
  }

  bool get isTransferReceived {
    return eventType == 'interhospital_transfer_received';
  }

  bool get isTransferCompleted {
    return eventType == 'interhospital_transfer_completed';
  }

  bool get isTransferRejected {
    return eventType == 'interhospital_transfer_rejected';
  }

  bool get isTransferCancelled {
    return eventType == 'interhospital_transfer_cancelled';
  }

  String? get transferId {
    final dataTransferId = data['transfer_id']?.toString().trim();

    if (dataTransferId != null && dataTransferId.isNotEmpty) {
      return dataTransferId;
    }

    if (entityType == 'interhospital_transfer' &&
        entityId != null &&
        entityId!.trim().isNotEmpty) {
      return entityId;
    }

    final link = deepLink?.trim();

    if (link == null || link.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(link);

    if (uri == null || uri.pathSegments.isEmpty) {
      return null;
    }

    return uri.pathSegments.last;
  }

  String? get transferNumber {
    final value = data['transfer_number']?.toString().trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String? get transferStatus {
    final value = data['status']?.toString().trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String? get transferPriority {
    final value = data['priority']?.toString().trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String? get sourceHospitalId {
    final value = data['source_hospital_id']?.toString().trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String? get destinationHospitalId {
    final value = data['destination_hospital_id']?.toString().trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String get resolvedDeepLink {
    final link = deepLink?.trim();

    if (link != null && link.isNotEmpty) {
      return link;
    }

    final resolvedTransferId = transferId;

    if (resolvedTransferId != null) {
      return '/patient/interhospital-transfers/'
          '$resolvedTransferId';
    }

    return '/patient/notifications';
  }

  String get displayEventType {
    final words = eventType.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));

    return words.map((word) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  String get displayAge {
    final date = createdAt;

    if (date == null) {
      return '';
    }

    final difference = DateTime.now().difference(date);

    if (difference.isNegative) {
      return 'Just now';
    }

    if (difference.inMinutes < 1) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }

    final year = date.year.toString();

    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}

// =============================================================================
// NOTIFICATION STATE
// =============================================================================

class PatientNotificationState {
  const PatientNotificationState({
    required this.notifications,
    required this.transferNotifications,
    required this.unreadCount,
  });

  final List<PatientNotificationRecord> notifications;

  final List<PatientNotificationRecord> transferNotifications;

  final int unreadCount;

  bool get hasNotifications {
    return notifications.isNotEmpty;
  }

  bool get hasUnreadNotifications {
    return unreadCount > 0;
  }

  PatientNotificationRecord? get latestNotification {
    if (notifications.isEmpty) {
      return null;
    }

    return notifications.first;
  }

  PatientNotificationRecord? get latestTransferNotification {
    if (transferNotifications.isEmpty) {
      return null;
    }

    return transferNotifications.first;
  }
}
