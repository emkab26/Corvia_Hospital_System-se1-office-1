import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/doctor_directory.dart';
import '../../services/doctor_favourites_service.dart';
import '../../services/doctor_messaging_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doctor_availability_avatar.dart';
import '../../widgets/message_receipt.dart';
import '../../widgets/status_view.dart';

/// Patient-side chat. Lists doctors (sorted by distance when known) and
/// opens a realtime chat thread with the chosen doctor. Auth + role
/// routing are handled upstream by AuthGate.
class ChatWithDoctorPage extends StatelessWidget {
  const ChatWithDoctorPage({
    super.key,
    this.doctor,
    this.messagingService,
  });

  final DoctorEntry? doctor;
  final DoctorMessagingService? messagingService;

  @override
  Widget build(BuildContext context) => _DoctorListPage(
        doctor: doctor,
        messagingService: messagingService,
      );
}

enum _ChatFailureAction {
  loadDoctors,
  openConversation,
  loadMessages,
  sendMessage,
}

String _friendlyChatError(
  Object error, {
  required _ChatFailureAction action,
}) {
  final text = error.toString().toLowerCase();

  if (error is AuthException ||
      text.contains('jwt') ||
      text.contains('unauthorized') ||
      text.contains('not authenticated')) {
    return 'Your session has expired. Please sign in again to chat with a doctor.';
  }

  if (error is PostgrestException) {
    final code = error.code?.toLowerCase() ?? '';
    final message = error.message.toLowerCase();

    if (code == 'pgrst202' ||
        code == '42883' ||
        message.contains('could not find the function')) {
      return 'Doctor messaging still needs its Supabase setup script.';
    }

    if (code == '42501' ||
        message.contains('permission denied') ||
        message.contains('row-level security')) {
      return 'You do not have permission to open this doctor chat yet.';
    }

    if (message.contains('relation') || message.contains('does not exist')) {
      return 'Doctor chat is not fully set up on the server yet.';
    }
  }

  if (text.contains('socket') ||
      text.contains('failed host lookup') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('timeout')) {
    return 'We could not reach Corvia chat. Check your connection and try again.';
  }

  switch (action) {
    case _ChatFailureAction.loadDoctors:
      return "We couldn't load the doctor directory. Please try again.";
    case _ChatFailureAction.openConversation:
      return "We couldn't open this conversation. Please try again.";
    case _ChatFailureAction.loadMessages:
      return "We couldn't load this conversation right now. Please try again.";
    case _ChatFailureAction.sendMessage:
      return "We couldn't send your message. Please try again.";
  }
}

class _DoctorListPage extends StatefulWidget {
  const _DoctorListPage({
    this.doctor,
    this.messagingService,
  });

  final DoctorEntry? doctor;
  final DoctorMessagingService? messagingService;

  @override
  State<_DoctorListPage> createState() => _DoctorListPageState();
}

class _DoctorListPageState extends State<_DoctorListPage> {
  Future<List<DoctorEntry>>? _future;
  bool _hasUserLocation = false;
  Set<String> _favoriteDoctorIds = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<List<DoctorEntry>> _load() async {
    try {
      _favoriteDoctorIds = await DoctorFavouritesService.fetchFavouriteIds();
    } catch (e) {
      debugPrint('ChatWithDoctor: failed to load favourites: $e');
    }
    _hasUserLocation = await DoctorDirectory.userLocationAvailable();
    final doctors = await DoctorDirectory.load(requireAvailable: true);
    return DoctorFavouritesService.favouritesFirst(
      doctors,
      _favoriteDoctorIds,
      (doctor) => doctor.doctorId,
    );
  }

  Future<void> _toggleFavorite(String doctorId) async {
    await HapticFeedback.mediumImpact();

    final wasFavourite = _favoriteDoctorIds.contains(doctorId);
    setState(() {
      _favoriteDoctorIds = Set.of(_favoriteDoctorIds);
      wasFavourite
          ? _favoriteDoctorIds.remove(doctorId)
          : _favoriteDoctorIds.add(doctorId);
    });

    try {
      await DoctorFavouritesService.toggleFavourite(
        doctorId,
        isFavourite: !wasFavourite,
      );
    } catch (e) {
      debugPrint('ChatWithDoctor: failed to save favourite: $e');
      if (!mounted) return;
      setState(() {
        _favoriteDoctorIds = Set.of(_favoriteDoctorIds);
        wasFavourite
            ? _favoriteDoctorIds.add(doctorId)
            : _favoriteDoctorIds.remove(doctorId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update favourites.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // If a doctor was passed, go directly to chat thread
    if (widget.doctor != null) {
      return _ChatThreadPage(
        doctor: widget.doctor!,
        messagingService: widget.messagingService,
      );
    }

    // Otherwise, show the doctor list
    return Scaffold(
      appBar: AppBar(title: const Text('Chat with a Doctor')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<DoctorEntry>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return StatusView.loading(message: 'Loading doctors...');
            }
            if (snap.hasError) {
              return StatusView.error(
                friendlyMessage: _friendlyChatError(
                  snap.error!,
                  action: _ChatFailureAction.loadDoctors,
                ),
                error: snap.error,
                stackTrace: snap.stackTrace,
                onRetry: _refresh,
              );
            }
            final doctors = snap.data ?? const [];
            if (doctors.isEmpty) {
              return StatusView.empty(
                icon: Icons.medical_services_outlined,
                title: 'No doctors are online',
                subtitle:
                    'Available doctors will show here once they are on call.',
                onRetry: _refresh,
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_hasUserLocation)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.my_location,
                            size: 14, color: CorviaColors.accentLight),
                        const SizedBox(width: 6),
                        Text('Sorted by distance from you',
                            style: TextStyle(
                                color: CorviaColors.textSecondary,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                for (int i = 0; i < doctors.length; i++) ...[
                  _DoctorTile(
                    doctor: doctors[i],
                    isFavourite:
                        _favoriteDoctorIds.contains(doctors[i].doctorId),
                    onToggleFavourite: () =>
                        _toggleFavorite(doctors[i].doctorId),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ChatThreadPage(
                          doctor: doctors[i],
                          messagingService: widget.messagingService,
                        ),
                      ),
                    ),
                  ),
                  if (i != doctors.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({
    required this.doctor,
    required this.isFavourite,
    required this.onToggleFavourite,
    required this.onTap,
  });
  final DoctorEntry doctor;
  final bool isFavourite;
  final VoidCallback onToggleFavourite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = [
      if (doctor.specialization.isNotEmpty) doctor.specialization,
      if (doctor.location.isNotEmpty) doctor.location,
    ].join(' • ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: DoctorAvailabilityAvatar(doctor: doctor),
        title: Text(doctor.displayName,
            style: TextStyle(
                color: CorviaColors.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary.isNotEmpty)
              Text(summary,
                  style: TextStyle(color: CorviaColors.textSecondary)),
            if (doctor.distanceLabel.isNotEmpty)
              Text(doctor.distanceLabel,
                  style:
                      TextStyle(color: CorviaColors.accentLight, fontSize: 12)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: isFavourite
                  ? 'Remove from favourites'
                  : 'Add to favourites (shown first)',
              icon: Icon(
                isFavourite ? Icons.favorite : Icons.favorite_border,
                color: isFavourite ? CorviaColors.danger : context.cTextMuted,
              ),
              onPressed: onToggleFavourite,
            ),
            Icon(Icons.chevron_right, color: context.cAccentReadable),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ChatThreadPage extends StatefulWidget {
  const _ChatThreadPage({
    required this.doctor,
    this.messagingService,
  });

  final DoctorEntry doctor;
  final DoctorMessagingService? messagingService;

  @override
  State<_ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<_ChatThreadPage> {
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();

  late final DoctorMessagingService _messagingService;

  String? _chatId;
  String? _bootstrapError;
  Stream<List<Map<String, dynamic>>>? _stream;
  bool _sending = false;
  bool _markingRead = false;
  DateTime? _doctorReadAt;
  bool _refreshingReceipts = false;
  Timer? _receiptTimer;

  bool get _canSendMessage =>
      !_sending && _chatId != null && _msgCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _messagingService = widget.messagingService ?? DoctorMessagingService();
    _msgCtrl.addListener(_handleComposerChanged);
    _bootstrap();
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _receiptTimer?.cancel();
    _msgCtrl.removeListener(_handleComposerChanged);
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final patientId = SupabaseService.currentUserId;
    if (patientId == null) {
      setState(() => _bootstrapError = 'You are not signed in.');
      return;
    }

    try {
      final chatId = await _messagingService.openPatientConversation(
        doctorId: widget.doctor.doctorId,
      );

      if (!mounted) return;
      setState(() {
        _chatId = chatId;
        _stream = _messagingService.watchMessages(chatId);
      });

      // The doctor's read time changes without a new message, so poll it.
      _receiptTimer?.cancel();
      _receiptTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(_refreshReceipts()),
      );
      unawaited(_refreshReceipts());

      await _messagingService.markRead(chatId);
    } catch (error, stackTrace) {
      debugPrint('Chat bootstrap failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _bootstrapError = _friendlyChatError(
          error,
          action: _ChatFailureAction.openConversation,
        );
      });
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _chatId == null || _sending) return;
    final patientId = SupabaseService.currentUserId;
    if (patientId == null) {
      _showSnack(
        'Your session has expired. Please sign in again to send messages.',
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await _messagingService.sendMessage(
        chatId: _chatId!,
        content: text,
      );
      _msgCtrl.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (error, stackTrace) {
      debugPrint('Chat send failed: $error\n$stackTrace');
      _showSnack(
        _friendlyChatError(
          error,
          action: _ChatFailureAction.sendMessage,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refreshReceipts() async {
    final chatId = _chatId;
    if (chatId == null || _refreshingReceipts) return;

    _refreshingReceipts = true;
    try {
      final readAt = await _messagingService.counterpartLastReadAt(
        chatId,
        viewerIsPatient: true,
      );
      if (mounted && readAt != _doctorReadAt) {
        setState(() => _doctorReadAt = readAt);
      }
    } finally {
      _refreshingReceipts = false;
    }
  }

  Future<void> _markRead() async {
    final chatId = _chatId;
    if (chatId == null || _markingRead) return;

    _markingRead = true;
    try {
      await _messagingService.markRead(chatId);
    } catch (error, stackTrace) {
      debugPrint('Patient chat mark-read failed: $error\n$stackTrace');
    } finally {
      _markingRead = false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(title: Text(widget.doctor.displayName)),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_bootstrapError == null)
            SafeArea(
              top: false,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  border: Border(top: BorderSide(color: context.cDivider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _msgCtrl,
                            maxLength: DoctorMessagingService.messageMaxLength,
                            style: TextStyle(color: context.cTextPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Type a message',
                              counterText: '',
                            ),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) {
                              if (_canSendMessage) {
                                _send();
                              }
                            },
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_msgCtrl.text.length} / '
                            '${DoctorMessagingService.messageMaxLength}',
                            style: TextStyle(
                              color: context.cTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _sending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CorviaColors.accent,
                              ),
                            )
                          : Icon(
                              Icons.send,
                              color: _canSendMessage
                                  ? CorviaColors.accent
                                  : context.cTextMuted,
                            ),
                      onPressed: _canSendMessage ? _send : null,
                      tooltip: 'Send',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_bootstrapError != null) {
      return StatusView.error(
        friendlyMessage: _bootstrapError!,
        onRetry: () {
          setState(() => _bootstrapError = null);
          _bootstrap();
        },
      );
    }
    if (_stream == null) {
      return StatusView.loading(message: 'Opening conversation...');
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return StatusView.error(
            friendlyMessage: _friendlyChatError(
              snap.error!,
              action: _ChatFailureAction.loadMessages,
            ),
            error: snap.error,
            onRetry: _bootstrap,
          );
        }
        final messages = snap.data ?? const [];
        if (messages.isEmpty) {
          return StatusView.empty(
            icon: Icons.chat_bubble_outline,
            title: 'No messages yet',
            subtitle: 'Say hello to ${widget.doctor.displayName}.',
          );
        }

        unawaited(_markRead());
        unawaited(_refreshReceipts());

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(12),
          itemCount: messages.length,
          itemBuilder: (_, i) => _MessageBubble(
            message: messages[i],
            counterpartReadAt: _doctorReadAt,
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.counterpartReadAt});
  final Map<String, dynamic> message;
  final DateTime? counterpartReadAt;

  @override
  Widget build(BuildContext context) {
    final isFromMe = message['sender_id'] == SupabaseService.currentUserId;
    final created = DateTime.tryParse(message['created_at']?.toString() ?? '');
    final timeLabel =
        created == null ? '' : DateFormat.Hm().format(created.toLocal());
    final bubbleColor = isFromMe ? CorviaColors.accent : context.cBgSecondary;
    final textColor = isFromMe ? Colors.white : context.cTextPrimary;

    return Align(
      alignment: isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          border: isFromMe ? null : Border.all(color: context.cDivider),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isFromMe ? 14 : 2),
            bottomRight: Radius.circular(isFromMe ? 2 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message['content']?.toString() ?? '',
              style: TextStyle(color: textColor, fontSize: 15),
            ),
            if (timeLabel.isNotEmpty || isFromMe)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: MessageReceipt(
                  timeLabel: timeLabel,
                  sentAt: created,
                  counterpartReadAt: counterpartReadAt,
                  showReceipt: isFromMe,
                  color: isFromMe
                      ? Colors.white.withValues(alpha: 0.7)
                      : context.cTextMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
