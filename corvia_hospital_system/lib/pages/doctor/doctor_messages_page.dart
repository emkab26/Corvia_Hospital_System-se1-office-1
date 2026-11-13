import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/doctor_messaging_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';
import '../../widgets/message_receipt.dart';

class DoctorMessagesPage extends StatefulWidget {
  const DoctorMessagesPage({
    super.key,
    required this.doctorId,
    required this.doctorAuthUserId,
    required this.doctorName,
    this.messagingService,
  });

  final String doctorId;
  final String doctorAuthUserId;
  final String doctorName;
  final DoctorMessagingService? messagingService;

  @override
  State<DoctorMessagesPage> createState() => _DoctorMessagesPageState();
}

class _DoctorMessagesPageState extends State<DoctorMessagesPage> {
  late final DoctorMessagingService _messagingService;

  Future<List<Map<String, dynamic>>>? _futureConversations;

  @override
  void initState() {
    super.initState();

    _messagingService =
        widget.messagingService ?? DoctorMessagingService();

    _refresh();
  }

  void _refresh() {
    if (!mounted) {
      return;
    }

    setState(() {
      _futureConversations =
          _messagingService.loadDoctorConversations();
    });
  }

  Future<void> _pullToRefresh() async {
    try {
      await _messagingService.loadDoctorConversations();
    } finally {
      if (mounted) {
        _refresh();
      }
    }
  }

  String _patientName(Map<String, dynamic> conversation) {
    final name =
        conversation['patient_name']?.toString().trim() ?? '';

    if (name.isNotEmpty) {
      return name;
    }

    return 'Patient';
  }

  String _patientEmail(Map<String, dynamic> conversation) {
    return conversation['patient_email']?.toString().trim() ?? '';
  }

  String _lastMessage(Map<String, dynamic> conversation) {
    final message =
        conversation['last_message']?.toString().trim() ?? '';

    if (message.isEmpty) {
      return 'No messages yet';
    }

    return message;
  }

  String _formatConversationTime(Map<String, dynamic> conversation) {
    final raw =
        conversation['last_message_at'] ??
        conversation['updated_at'];

    if (raw == null) {
      return '';
    }

    final parsed = DateTime.tryParse(
      raw.toString(),
    );

    if (parsed == null) {
      return '';
    }

    final local = parsed.toLocal();
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final messageDay = DateTime(
      local.year,
      local.month,
      local.day,
    );

    if (messageDay == today) {
      return DateFormat('HH:mm').format(local);
    }

    if (messageDay ==
        today.subtract(
          const Duration(days: 1),
        )) {
      return 'Yesterday';
    }

    if (local.year == now.year) {
      return DateFormat('dd MMM').format(local);
    }

    return DateFormat('dd/MM/yyyy').format(local);
  }

  void _openConversation(Map<String, dynamic> conversation) {
    final conversationId =
        conversation['conversation_id']?.toString().trim() ?? '';

    if (conversationId.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'This conversation could not be opened.',
            ),
          ),
        );

      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => _DoctorConversationPage(
              conversationId: conversationId,
              patientName: _patientName(conversation),
              messagingService: _messagingService,
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            _refresh();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Patient Messages',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _futureConversations,
          builder: (
            context,
            snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return StatusView.loading(
                message: 'Loading patient conversations...',
              );
            }

            if (snapshot.hasError) {
              return StatusView.error(
                friendlyMessage:
                    'Could not load patient messages. Please try again.',
                error: snapshot.error,
                stackTrace: snapshot.stackTrace,
                onRetry: _refresh,
              );
            }

            final conversations =
                snapshot.data ?? <Map<String, dynamic>>[];

            if (conversations.isEmpty) {
              return StatusView.empty(
                icon: Icons.forum_outlined,
                title: 'No patient conversations',
                subtitle:
                    'Patient chats will appear here when a patient sends you a message.',
                onRetry: _refresh,
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: conversations.length,
              separatorBuilder: (_, __) {
                return const SizedBox(
                  height: 10,
                );
              },
              itemBuilder: (
                context,
                index,
              ) {
                final conversation =
                    conversations[index];

                return _buildConversationCard(
                  conversation,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildConversationCard(
    Map<String, dynamic> conversation,
  ) {
    final patientName =
        _patientName(conversation);

    final patientEmail =
        _patientEmail(conversation);

    final lastMessage =
        _lastMessage(conversation);

    final timeLabel =
        _formatConversationTime(conversation);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(
          18,
        ),
        onTap: () {
          _openConversation(
            conversation,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(
            16,
          ),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(
              18,
            ),
            border: Border.all(
              color: context.cDivider,
            ),
            boxShadow: [
              BoxShadow(
                color: context.cCardShadow,
                blurRadius: 8,
                offset: const Offset(
                  0,
                  3,
                ),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: CorviaColors.accent.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(
                    16,
                  ),
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: CorviaColors.accent,
                  size: 28,
                ),
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            patientName,
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                        ),

                        if (timeLabel.isNotEmpty) ...[
                          const SizedBox(
                            width: 8,
                          ),
                          Text(
                            timeLabel,
                            style: TextStyle(
                              color:
                                  context.cTextMuted,
                              fontSize: 11,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (patientEmail.isNotEmpty) ...[
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        patientEmail,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              context.cTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(
                      height: 7,
                    ),

                    Text(
                      lastMessage,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            context.cTextSecondary,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              Icon(
                Icons.chevron_right_rounded,
                color: context.cAccentReadable,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorConversationPage extends StatefulWidget {
  const _DoctorConversationPage({
    required this.conversationId,
    required this.patientName,
    required this.messagingService,
  });

  final String conversationId;
  final String patientName;
  final DoctorMessagingService messagingService;

  @override
  State<_DoctorConversationPage> createState() =>
      _DoctorConversationPageState();
}

class _DoctorConversationPageState
    extends State<_DoctorConversationPage> {
  final TextEditingController _messageController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  Stream<List<Map<String, dynamic>>>? _messageStream;

  bool _sending = false;
  bool _markingRead = false;
  DateTime? _patientReadAt;
  bool _refreshingReceipts = false;
  Timer? _receiptTimer;

  bool get _canSend {
    return !_sending &&
        _messageController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();

    _messageController.addListener(
      _composerChanged,
    );

    _messageStream =
        widget.messagingService.watchMessages(
      widget.conversationId,
    );

    _markRead();

    // The patient's read time changes without a new message, so poll it.
    _receiptTimer = Timer.periodic(
      const Duration(
        seconds: 15,
      ),
      (_) => unawaited(
        _refreshReceipts(),
      ),
    );

    unawaited(
      _refreshReceipts(),
    );
  }

  Future<void> _refreshReceipts() async {
    if (_refreshingReceipts) {
      return;
    }

    _refreshingReceipts = true;

    try {
      final readAt =
          await widget.messagingService.counterpartLastReadAt(
        widget.conversationId,
        viewerIsPatient: false,
      );

      if (mounted &&
          readAt != _patientReadAt) {
        setState(() {
          _patientReadAt = readAt;
        });
      }
    } finally {
      _refreshingReceipts = false;
    }
  }

  @override
  void dispose() {
    _receiptTimer?.cancel();

    _messageController.removeListener(
      _composerChanged,
    );

    _messageController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  void _composerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _markRead() async {
    if (_markingRead) {
      return;
    }

    _markingRead = true;

    try {
      await widget.messagingService.markRead(
        widget.conversationId,
      );
    } catch (error) {
      debugPrint(
        'Doctor mark read failed: $error',
      );
    } finally {
      _markingRead = false;
    }
  }

  Future<void> _sendMessage() async {
    final message =
        _messageController.text.trim();

    if (message.isEmpty ||
        _sending) {
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await widget.messagingService.sendMessage(
        chatId: widget.conversationId,
        content: message,
      );

      _messageController.clear();

      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          _scrollToBottom();
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Message could not be sent: $error',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }

    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(
        milliseconds: 250,
      ),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              widget.patientName,
            ),
            Text(
              'Patient conversation',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMessages(),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    final stream = _messageStream;

    if (stream == null) {
      return StatusView.loading(
        message: 'Opening conversation...',
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (
        context,
        snapshot,
      ) {
        if (snapshot.hasError) {
          return StatusView.error(
            friendlyMessage:
                'Could not load this conversation.',
            error: snapshot.error,
          );
        }

        final messages =
            snapshot.data ??
            <Map<String, dynamic>>[];

        if (messages.isEmpty) {
          return StatusView.empty(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'No messages yet',
            subtitle:
                'Messages from ${widget.patientName} will appear here.',
          );
        }

        unawaited(
          _markRead(),
        );

        unawaited(
          _refreshReceipts(),
        );

        WidgetsBinding.instance.addPostFrameCallback(
          (_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                _scrollController
                    .position.maxScrollExtent,
              );
            }
          },
        );

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
          itemCount: messages.length,
          itemBuilder: (
            context,
            index,
          ) {
            return _DoctorMessageBubble(
              message: messages[index],
              counterpartReadAt: _patientReadAt,
            );
          },
        );
      },
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          12,
          10,
          12,
          10,
        ),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          border: Border(
            top: BorderSide(
              color: context.cDivider,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller:
                    _messageController,
                minLines: 1,
                maxLines: 5,
                maxLength:
                    DoctorMessagingService.messageMaxLength,
                style: TextStyle(
                  color:
                      context.cTextPrimary,
                ),
                textCapitalization:
                    TextCapitalization.sentences,
                textInputAction:
                    TextInputAction.send,
                onSubmitted: (_) {
                  if (_canSend) {
                    _sendMessage();
                  }
                },
                decoration: InputDecoration(
                  hintText:
                      'Message ${widget.patientName}',
                  counterText: '',
                  filled: true,
                  fillColor:
                      context.cBgPrimary,
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                    borderSide:
                        BorderSide(
                      color:
                          context.cDivider,
                    ),
                  ),
                  enabledBorder:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                    borderSide:
                        BorderSide(
                      color:
                          context.cDivider,
                    ),
                  ),
                  focusedBorder:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                    borderSide:
                        BorderSide(
                      color:
                          CorviaColors.accent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _canSend
                    ? CorviaColors.accent
                    : context.cDivider,
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
              ),
              child: IconButton(
                tooltip: 'Send',
                onPressed:
                    _canSend
                        ? _sendMessage
                        : null,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color:
                            Colors.white,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorMessageBubble extends StatelessWidget {
  const _DoctorMessageBubble({
    required this.message,
    this.counterpartReadAt,
  });

  final Map<String, dynamic> message;

  final DateTime? counterpartReadAt;

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        SupabaseService.currentUserId;

    final senderId =
        message['sender_id']
            ?.toString();

    final senderRole =
        message['sender_role']
            ?.toString();

    final isFromDoctor =
        senderId == currentUserId ||
        senderRole == 'doctor';

    final content =
        message['content']
            ?.toString() ??
        '';

    final createdAt =
        DateTime.tryParse(
      message['created_at']
              ?.toString() ??
          '',
    );

    final timeLabel =
        createdAt == null
            ? ''
            : DateFormat(
                'HH:mm',
              ).format(
                createdAt.toLocal(),
              );

    final bubbleColor =
        isFromDoctor
            ? CorviaColors.accent
            : context.cBgSecondary;

    final textColor =
        isFromDoctor
            ? Colors.white
            : context.cTextPrimary;

    return Align(
      alignment:
          isFromDoctor
              ? Alignment.centerRight
              : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(
          maxWidth:
              MediaQuery.of(
                    context,
                  ).size.width *
                  0.75,
        ),
        margin:
            const EdgeInsets.symmetric(
          vertical: 4,
        ),
        padding:
            const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration:
            BoxDecoration(
          color:
              bubbleColor,
          border:
              isFromDoctor
                  ? null
                  : Border.all(
                      color:
                          context.cDivider,
                    ),
          borderRadius:
              BorderRadius.only(
            topLeft:
                const Radius.circular(
              16,
            ),
            topRight:
                const Radius.circular(
              16,
            ),
            bottomLeft:
                Radius.circular(
              isFromDoctor
                  ? 16
                  : 3,
            ),
            bottomRight:
                Radius.circular(
              isFromDoctor
                  ? 3
                  : 16,
            ),
          ),
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          children: [
            Align(
              alignment:
                  Alignment.centerLeft,
              child:
                  Text(
                content,
                style:
                    TextStyle(
                  color:
                      textColor,
                  fontSize:
                      15,
                  height:
                      1.3,
                ),
              ),
            ),

            if (timeLabel.isNotEmpty) ...[
              const SizedBox(
                height:
                    4,
              ),
              MessageReceipt(
                timeLabel:
                    timeLabel,
                sentAt:
                    createdAt,
                counterpartReadAt:
                    counterpartReadAt,
                showReceipt:
                    isFromDoctor,
                fontSize:
                    10,
                color:
                    isFromDoctor
                        ? Colors.white.withValues(
                            alpha:
                                0.70,
                          )
                        : context
                            .cTextMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}