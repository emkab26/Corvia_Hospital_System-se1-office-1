import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/voice_input_button.dart';
import '../../widgets/input_device_button.dart';
import '../../services/windows_input_devices.dart';
import '../../services/voice_service.dart';

class ChatPageUser extends StatefulWidget {
  final int incidentId;

  const ChatPageUser({
    super.key,
    required this.incidentId,
  });

  @override
  State<ChatPageUser> createState() => _ChatPageUserState();
}

class _ChatPageUserState extends State<ChatPageUser> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  static const _messageMaxLength = 1000;

  final List<Map<String, dynamic>> messages = [];

  Timer? _refreshTimer;
  bool _loading = true;
  bool _sending = false;
  bool _refreshing = false;
  bool _disposed = false;
  String _microphoneId = '';

  bool get _canSendMessage => !_sending && _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleComposerChanged);
    _loadMessages();

    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadMessages(silent: true);
    });
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _controller.removeListener(_handleComposerChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_refreshing || _disposed) return;

    _refreshing = true;

    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    try {
      final rows = await supabase
          .from('incident_messages')
          .select('*')
          .eq('incident_id', widget.incidentId)
          .order('created_at', ascending: true);

      final loaded = <Map<String, dynamic>>[];

      for (final raw in rows) {
        final msg = Map<String, dynamic>.from(raw as Map);
        String senderName = 'Unknown';

        final senderType = msg['sender_type']?.toString() ?? '';
        final senderId = msg['sender_id'];

        if (senderType == 'dispatcher' && senderId != null) {
          try {
            final dispatch = await supabase
                .from('dispatch_profiles')
                .select('first_name, surname')
                .eq('id', senderId)
                .maybeSingle();

            final firstName = dispatch?['first_name']?.toString() ?? '';
            final surname = dispatch?['surname']?.toString() ?? '';
            final fullName = '$firstName $surname'.trim();

            senderName = fullName.isEmpty ? 'Dispatcher' : fullName;
          } catch (_) {
            senderName = 'Dispatcher';
          }
        } else {
          senderName = 'You';
        }

        loaded.add({
          ...msg,
          'sender_name': senderName,
          'sent': true,
          'failed': false,
          'local_only': false,
        });
      }

      if (_disposed || !mounted) return;

      setState(() {
        final localMessages =
            messages.where((m) => m['local_only'] == true).toList();

        messages
          ..clear()
          ..addAll(loaded)
          ..addAll(localMessages);

        final seen = <String>{};

        messages.removeWhere((m) {
          final id = m['id']?.toString() ??
              '${m['sender_id']}_${m['message']}_${m['created_at']}';

          if (seen.contains(id)) return true;

          seen.add(id);
          return false;
        });

        messages.sort((a, b) {
          final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);

          return aDate.compareTo(bDate);
        });

        _loading = false;
      });

      _scrollToBottom();
    } catch (e) {
      if (_disposed || !mounted) return;

      setState(() => _loading = false);

      if (!silent) {
        _showSnack('Could not load messages: $e', isError: true);
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();

    if (text.isEmpty || _sending) return;

    final currentUser = supabase.auth.currentUser;

    if (currentUser == null) {
      _showSnack('You are not signed in.', isError: true);
      return;
    }

    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();

    setState(() {
      _sending = true;
      messages.add({
        'id': tempId,
        'incident_id': widget.incidentId,
        'sender_id': currentUser.id,
        'sender_type': 'user',
        'message': text,
        'sender_name': 'You',
        'created_at': now,
        'sent': false,
        'failed': false,
        'local_only': true,
      });
    });

    _controller.clear();
    _scrollToBottom();

    try {
      final inserted = await supabase
          .from('incident_messages')
          .insert({
            'incident_id': widget.incidentId,
            'sender_id': currentUser.id,
            'message': text,
            'sender_type': 'user',
          })
          .select()
          .maybeSingle();

      if (_disposed || !mounted) return;

      setState(() {
        final index = messages.indexWhere((m) => m['id'] == tempId);

        if (index != -1) {
          messages[index] = {
            ...(inserted ?? messages[index]),
            'sender_name': 'You',
            'sent': true,
            'failed': false,
            'local_only': false,
          };
        }
      });

      await _loadMessages(silent: true);
    } catch (e) {
      if (_disposed || !mounted) return;

      setState(() {
        final index = messages.indexWhere((m) => m['id'] == tempId);

        if (index != -1) {
          messages[index]['sent'] = false;
          messages[index]['failed'] = true;
        }
      });

      _showSnack('Message failed: $e', isError: true);
    } finally {
      if (!_disposed && mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _scrollToBottom() {
    if (_disposed) return;

    Future.delayed(const Duration(milliseconds: 120), () {
      if (_disposed || !_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? CorviaColors.danger : null,
      ),
    );
  }

  Future<void> _manualRefresh() async {
    await _loadMessages();

    if (!mounted) return;

    _showSnack('Messages refreshed');
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final currentUserId = supabase.auth.currentUser?.id;

    final isMe = msg['sender_id']?.toString() == currentUserId &&
        msg['sender_type']?.toString() == 'user';

    final time =
        DateTime.tryParse(msg['created_at']?.toString() ?? '')?.toLocal();

    final senderName = msg['sender_name']?.toString() ?? 'Unknown';
    final message = msg['message']?.toString() ?? '';
    final failed = msg['failed'] == true;
    final sent = msg['sent'] == true;

    final bubbleColor = isMe
        ? CorviaColors.success.withValues(alpha: 0.95)
        : CorviaColors.accent.withValues(alpha: 0.95);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: failed
              ? CorviaColors.danger.withValues(alpha: 0.92)
              : bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: isMe ? const Radius.circular(14) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(14),
          ),
          boxShadow: [
            BoxShadow(
              color: context.cCardShadow,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              senderName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (time != null)
                  Text(
                    DateFormat('HH:mm').format(time),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Icon(
                    failed
                        ? Icons.error_outline
                        : sent
                            ? Icons.done_all
                            : Icons.schedule,
                    color: Colors.white70,
                    size: 13,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(date.year, date.month, date.day);

    String dateString;
    if (msgDate == today) {
      dateString = 'Today';
    } else if (msgDate == yesterday) {
      dateString = 'Yesterday';
    } else {
      dateString = DateFormat('MMMM d, yyyy').format(date);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: CorviaColors.textMuted.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        dateString,
        style: TextStyle(
          color: CorviaColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: context.cAccentReadable,
            ),
            const SizedBox(height: 14),
            Text(
              'No messages yet',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Send a message to dispatch for this emergency incident.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _messageDecoration() {
    return InputDecoration(
      hintText: 'Type your message...',
      hintStyle: TextStyle(color: context.cTextMuted),
      counterText: '',
      filled: true,
      fillColor: context.cBgSecondary,
      suffixIcon: VoiceInputButton(
          controller: _controller, microphoneId: _microphoneId),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: CorviaColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: CorviaColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: CorviaColors.accent,
          width: 1.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Chat with Dispatch'),
        backgroundColor: CorviaColors.success,
        foregroundColor: Colors.white,
        actions: [
          InputDeviceButton(
            label: 'microphone',
            selectedId: _microphoneId,
            loadDevices: WindowsInputDevices.speechMicrophones,
            onSelected: (id) async {
              await VoiceService.instance.stopListening();
              await WindowsInputDevices.selectSpeechMicrophone(id);
              if (mounted) setState(() => _microphoneId = id);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _manualRefresh,
            tooltip: 'Refresh messages',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: CorviaColors.accent,
                    ),
                  )
                : messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          bool showDateSeparator = false;
                          DateTime? currDate;
                          if (msg['created_at'] != null) {
                            currDate =
                                DateTime.tryParse(msg['created_at'].toString())
                                    ?.toLocal();
                          }

                          if (index == 0) {
                            showDateSeparator = true;
                          } else {
                            final prevMsg = messages[index - 1];
                            final prevDate = DateTime.tryParse(
                                    prevMsg['created_at']?.toString() ?? '')
                                ?.toLocal();
                            if (currDate != null && prevDate != null) {
                              if (currDate.year != prevDate.year ||
                                  currDate.month != prevDate.month ||
                                  currDate.day != prevDate.day) {
                                showDateSeparator = true;
                              }
                            }
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showDateSeparator && currDate != null)
                                _buildDateSeparator(currDate),
                              _buildMessage(msg),
                            ],
                          );
                        },
                      ),
          ),
          Divider(height: 1, color: CorviaColors.divider),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: context.cBgPrimary,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _controller,
                          maxLength: _messageMaxLength,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          cursorColor: CorviaColors.accent,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (_canSendMessage) {
                              _sendMessage();
                            }
                          },
                          decoration: _messageDecoration(),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_controller.text.length} / $_messageMaxLength',
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: _sending
                        ? CorviaColors.textMuted
                        : _canSendMessage
                            ? CorviaColors.success
                            : CorviaColors.divider,
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: _canSendMessage ? _sendMessage : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
