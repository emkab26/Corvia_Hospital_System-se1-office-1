import 'package:flutter/material.dart';

import '../../services/corvia_ai_router_service.dart';
import '../../theme/app_theme.dart';
import 'dart:async';

typedef AiNurseAsk = Future<CorviaAiReply> Function({
  required String question,
  required List<CorviaChatMessage> history,
});

class AiNursePage extends StatefulWidget {
  const AiNursePage({
    super.key,
    this.ask,
  });

  final AiNurseAsk? ask;

  @override
  State<AiNursePage> createState() => _AiNursePageState();
}

class _AiNursePageState extends State<AiNursePage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const _messageMaxLength = 1000;

  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      role: 'assistant',
      text:
          'Hi, I am Corvia AI nurse. I can use your Corvia profile, allergies, medication, appointments, emergency profile, symptoms, and lab info to guide you. I cannot replace a doctor.',
      engine: 'Ready',
      usedCache: false,
      usedOllama: false,
      usedFallback: false,
    ),
  ];

  bool _loading = false;
  String _engineStatus = 'Hybrid AI ready';

  bool get _canSendMessage =>
      !_loading && _messageController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_handleComposerChanged);
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(
        _ChatMessage(
          role: 'user',
          text: text,
          engine: 'You',
          usedCache: false,
          usedOllama: false,
          usedFallback: false,
        ),
      );
      _loading = true;
      _engineStatus = 'Loading Corvia data...';
    });

    _messageController.clear();
    _scrollToBottom();

    final history = _messages
        .map(
          (m) => CorviaChatMessage(
            role: m.role,
            content: m.text,
          ),
        )
        .toList();

    final ask = widget.ask ?? CorviaAiRouterService.ask;
    try {
      final reply = await ask(
        question: text,
        history: history,
      ).timeout(
        Duration(seconds: 20),
      );

      if (!mounted) return;

      setState(() {
        _messages.add(
          _ChatMessage(
            role: 'assistant',
            text: reply.text,
            engine: reply.engine,
            usedCache: reply.usedCache,
            usedOllama: reply.usedOllama,
            usedFallback: reply.usedFallback,
          ),
        );
        _engineStatus = reply.engine;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _messages.add(
          const _ChatMessage(
            role: 'assistant',
            text:
                'Sorry, I could not complete your request. Please check your connection and try again.',
            engine: 'AI service unavailable',
            usedCache: false,
            usedOllama: false,
            usedFallback: true,
          ),
        );
        _engineStatus = 'AI service unavailable';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _quickAsk(String text) {
    if (_loading) return;

    _messageController.text = text;
    _sendMessage();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _statusCard() {
    final isOffline = _engineStatus.toLowerCase().contains('offline');
    final isOllama = _engineStatus.toLowerCase().contains('ollama');

    final icon = isOllama
        ? Icons.psychology
        : isOffline
            ? Icons.cloud_off
            : Icons.cloud_done;

    final color = isOllama
        ? CorviaColors.accentLight
        : isOffline
            ? CorviaColors.warning
            : CorviaColors.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _engineStatus,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickChips() {
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        children: [
          _QuickChip(
            label: 'Summary',
            onTap: () => _quickAsk('Summarize my patient profile'),
          ),
          _QuickChip(
            label: 'Emergency',
            onTap: () => _quickAsk('Show my emergency profile'),
          ),
          _QuickChip(
            label: 'Medication',
            onTap: () => _quickAsk('What medication do I have?'),
          ),
          _QuickChip(
            label: 'Appointments',
            onTap: () => _quickAsk('Do I have upcoming appointments?'),
          ),
          _QuickChip(
            label: 'Headache',
            onTap: () => _quickAsk('I have a headache'),
          ),
          _QuickChip(
            label: 'Lab',
            onTap: () => _quickAsk('Explain my lab result'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.removeListener(_handleComposerChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('AI nurse'),
      ),
      body: Column(
        children: [
          _statusCard(),
          _quickChips(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_loading && index == _messages.length) {
                  return const _TypingBubble();
                }

                return _MessageBubble(message: _messages[index]);
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                border: Border(
                  top: BorderSide(color: CorviaColors.divider),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _messageController,
                          maxLength: _messageMaxLength,
                          style: TextStyle(color: context.cTextPrimary),
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: 'Ask the AI nurse...',
                            hintStyle: TextStyle(color: context.cTextSecondary),
                            counterText: '',
                            filled: true,
                            fillColor: context.cBgPrimary,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: CorviaColors.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: CorviaColors.divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: CorviaColors.accentLight),
                            ),
                          ),
                          onSubmitted: (_) {
                            if (_canSendMessage) {
                              _sendMessage();
                            }
                          },
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_messageController.text.length} / $_messageMaxLength',
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: _loading || _canSendMessage
                        ? CorviaColors.accentLight
                        : CorviaColors.divider,
                    onPressed: _canSendMessage ? _sendMessage : null,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
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

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label),
        onPressed: onTap,
        backgroundColor: context.cBgSecondary,
        labelStyle: TextStyle(color: context.cTextPrimary),
        side: BorderSide(color: CorviaColors.divider),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';

    final borderColor = message.usedOllama
        ? CorviaColors.accentLight
        : message.usedCache
            ? CorviaColors.warning
            : CorviaColors.divider;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          color: isUser ? CorviaColors.accentLight : context.cBgSecondary,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser ? null : Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : context.cTextPrimary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            if (!isUser) ...[
              const SizedBox(height: 8),
              Text(
                message.engine,
                style: TextStyle(
                  color: message.usedOllama
                      ? CorviaColors.accentLight
                      : message.usedCache
                          ? CorviaColors.warning
                          : context.cTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CorviaColors.divider),
        ),
        child: Text(
          'AI nurse is checking your Corvia data...',
          style: TextStyle(
            color: context.cTextSecondary,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    required this.engine,
    required this.usedCache,
    required this.usedOllama,
    required this.usedFallback,
  });

  final String role;
  final String text;
  final String engine;
  final bool usedCache;
  final bool usedOllama;
  final bool usedFallback;
}
