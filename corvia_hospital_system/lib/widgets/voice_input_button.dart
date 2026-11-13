import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';

/// Microphone icon button that appends dictated speech to a [TextField]'s
/// [TextEditingController]. Renders nothing when the user has voice input
/// disabled in Settings.
///
/// Drop into the `suffix` (or anywhere) of an InputDecoration / Row:
/// ```dart
/// TextField(
///   controller: ctrl,
///   decoration: InputDecoration(
///     suffixIcon: VoiceInputButton(controller: ctrl),
///   ),
/// )
/// ```
class VoiceInputButton extends StatefulWidget {
  final TextEditingController controller;
  final String microphoneId;

  /// Optional callback fired with the final recognised text (after the user
  /// pauses speaking). Use this to auto-submit a search field, for example.
  final void Function(String finalText)? onFinalResult;

  /// Tooltip override.
  final String tooltipStart;
  final String tooltipStop;

  const VoiceInputButton({
    super.key,
    required this.controller,
    this.microphoneId = '',
    this.onFinalResult,
    this.tooltipStart = 'Dictate',
    this.tooltipStop = 'Stop dictation',
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  /// Text already in the field when listening started - recognised text is
  /// appended to this so dictation doesn't wipe what the user already typed.
  String _baseText = '';
  bool _activeForThisButton = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Settings - to hide the button when voice input is off.
      // Listening state - to flip the icon while dictating.
      listenable: Listenable.merge([
        SettingsService.instance,
        VoiceService.instance.isListening,
      ]),
      builder: (context, _) {
        if (!SettingsService.instance.voiceInputEnabled) {
          return const SizedBox.shrink();
        }
        final isListening =
            VoiceService.instance.isListening.value && _activeForThisButton;
        return IconButton(
          tooltip: isListening ? widget.tooltipStop : widget.tooltipStart,
          icon: Icon(
            isListening ? Icons.stop_circle : Icons.mic,
            color: isListening ? Colors.redAccent : CorviaColors.accentLight,
          ),
          onPressed: _toggle,
        );
      },
    );
  }

  Future<void> _toggle() async {
    final service = VoiceService.instance;
    if (service.isListening.value && _activeForThisButton) {
      await service.stopListening();
      setState(() => _activeForThisButton = false);
      return;
    }

    _baseText = widget.controller.text;
    final ok = await service.startListening(
      microphoneId: widget.microphoneId,
      onResult: (text, isFinal) {
        if (!mounted) return;
        final separator =
            (_baseText.isEmpty || _baseText.endsWith(' ')) ? '' : ' ';
        widget.controller.text = '$_baseText$separator$text';
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
        if (isFinal) {
          setState(() => _activeForThisButton = false);
          widget.onFinalResult?.call(widget.controller.text);
        }
      },
    );

    if (!mounted) return;
    if (ok) {
      setState(() => _activeForThisButton = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Microphone access required for voice input. Enable it in device settings.')),
      );
    }
  }
}
