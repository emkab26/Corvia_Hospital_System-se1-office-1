import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorMessagingService {
  DoctorMessagingService({
    SupabaseClient? client,
  }) : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const int messageMaxLength = 1000;

  // ============================================================
  // SESSION
  // ============================================================

  User _requireUser() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AuthException(
        'You are not authenticated.',
      );
    }

    return user;
  }

  // ============================================================
  // PATIENT -> OPEN DOCTOR CONVERSATION
  // ============================================================

  Future<String> openPatientConversation({
    required String doctorId,
  }) async {
    _requireUser();

    final cleanDoctorId = doctorId.trim();

    if (cleanDoctorId.isEmpty) {
      throw ArgumentError(
        'Doctor ID cannot be empty.',
      );
    }

    try {
      final response = await _supabase.rpc(
        'corvia_open_patient_doctor_conversation',
        params: {
          'p_doctor_id': cleanDoctorId,
        },
      );

      final conversationId =
          response?.toString().trim() ?? '';

      if (conversationId.isEmpty) {
        throw StateError(
          'Corvia did not return a conversation ID.',
        );
      }

      debugPrint(
        'DoctorMessagingService: opened conversation '
        '$conversationId',
      );

      return conversationId;
    } catch (error) {
      debugPrint(
        'DoctorMessagingService.openPatientConversation failed: '
        '$error',
      );

      rethrow;
    }
  }

  // ============================================================
  // REALTIME MESSAGE STREAM
  // ============================================================

  Stream<List<Map<String, dynamic>>> watchMessages(
    String conversationId,
  ) {
    _requireUser();

    final cleanConversationId =
        conversationId.trim();

    if (cleanConversationId.isEmpty) {
      throw ArgumentError(
        'Conversation ID cannot be empty.',
      );
    }

    return _supabase
        .from('doctor_messages')
        .stream(
          primaryKey: [
            'id',
          ],
        )
        .eq(
          'conversation_id',
          cleanConversationId,
        )
        .order(
          'created_at',
          ascending: true,
        )
        .map(
          (rows) {
            return rows
                .map(
                  (row) =>
                      Map<String, dynamic>.from(
                    row,
                  ),
                )
                .toList();
          },
        );
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<String> sendMessage({
    required String chatId,
    required String content,
  }) async {
    _requireUser();

    final cleanChatId = chatId.trim();
    final cleanContent = content.trim();

    if (cleanChatId.isEmpty) {
      throw ArgumentError(
        'Conversation ID cannot be empty.',
      );
    }

    if (cleanContent.isEmpty) {
      throw ArgumentError(
        'Message cannot be empty.',
      );
    }

    if (cleanContent.length > messageMaxLength) {
      throw ArgumentError(
        'Message cannot exceed '
        '$messageMaxLength characters.',
      );
    }

    try {
      final response = await _supabase.rpc(
        'corvia_send_doctor_message',
        params: {
          'p_conversation_id': cleanChatId,
          'p_content': cleanContent,
        },
      );

      final messageId =
          response?.toString().trim() ?? '';

      if (messageId.isEmpty) {
        throw StateError(
          'Corvia did not return a message ID.',
        );
      }

      return messageId;
    } catch (error) {
      debugPrint(
        'DoctorMessagingService.sendMessage failed: '
        '$error',
      );

      rethrow;
    }
  }

  // ============================================================
  // MARK READ
  // ============================================================

  Future<void> markRead(
    String conversationId,
  ) async {
    _requireUser();

    final cleanConversationId =
        conversationId.trim();

    if (cleanConversationId.isEmpty) {
      return;
    }

    try {
      await _supabase.rpc(
        'corvia_mark_doctor_conversation_read',
        params: {
          'p_conversation_id':
              cleanConversationId,
        },
      );
    } catch (error) {
      debugPrint(
        'DoctorMessagingService.markRead failed: '
        '$error',
      );

      rethrow;
    }
  }

  // ============================================================
  // READ RECEIPTS
  //
  // doctor_conversations keeps each side's last-read time. A sent
  // message counts as read once the other side's time is at or after
  // its created_at. Returns null when unknown or not permitted.
  // ============================================================

  Future<DateTime?> counterpartLastReadAt(
    String conversationId, {
    required bool viewerIsPatient,
  }) async {
    final cleanConversationId =
        conversationId.trim();

    if (cleanConversationId.isEmpty) {
      return null;
    }

    final column = viewerIsPatient
        ? 'doctor_last_read_at'
        : 'patient_last_read_at';

    try {
      final row = await _supabase
          .from('doctor_conversations')
          .select(column)
          .eq('id', cleanConversationId)
          .maybeSingle();

      return DateTime.tryParse(
        row?[column]?.toString() ?? '',
      );
    } catch (error) {
      debugPrint(
        'DoctorMessagingService.counterpartLastReadAt failed: '
        '$error',
      );

      return null;
    }
  }

  // ============================================================
  // LOAD CURRENT CONVERSATION ONCE
  // ============================================================

  Future<List<Map<String, dynamic>>> loadMessages(
    String conversationId,
  ) async {
    _requireUser();

    final cleanConversationId =
        conversationId.trim();

    if (cleanConversationId.isEmpty) {
      return [];
    }

    final response = await _supabase
        .from('doctor_messages')
        .select()
        .eq(
          'conversation_id',
          cleanConversationId,
        )
        .order(
          'created_at',
          ascending: true,
        );

    return response
        .map(
          (row) =>
              Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  // ============================================================
  // DOCTOR -> CONVERSATION LIST
  //
  // We prepare this now so doctor-side messaging can use the
  // exact same backend later.
  // ============================================================

  Future<List<Map<String, dynamic>>>
      loadDoctorConversations() async {
    _requireUser();

    final response = await _supabase.rpc(
      'corvia_doctor_my_conversations',
    );

    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map(
          (row) =>
              Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }
}