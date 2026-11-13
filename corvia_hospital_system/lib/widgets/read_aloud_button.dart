import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';

/// Speaker icon button that reads [text] aloud via TTS. Renders nothing when
/// the user has read-back disabled in Settings.
///
/// Multiple buttons on the same screen behave independently - only the one
/// whose text is currently being spoken flips to the "stop" state.
class ReadAloudButton extends StatelessWidget {
  final String text;
  final double iconSize;
  final String tooltipStart;
  final String tooltipStop;

  const ReadAloudButton({
    super.key,
    required this.text,
    this.iconSize = 22,
    this.tooltipStart = 'Read aloud',
    this.tooltipStop = 'Stop reading',
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SettingsService.instance,
        VoiceService.instance.currentSpeakingText,
      ]),
      builder: (context, _) {
        if (!SettingsService.instance.readBackEnabled) {
          return const SizedBox.shrink();
        }
        final isMe = VoiceService.instance.currentSpeakingText.value == text;
        return IconButton(
          tooltip: isMe ? tooltipStop : tooltipStart,
          iconSize: iconSize,
          icon: Icon(
            isMe ? Icons.stop_circle : Icons.volume_up,
            color: isMe ? Colors.redAccent : CorviaColors.accentLight,
          ),
          onPressed: () async {
            if (isMe) {
              await VoiceService.instance.stopSpeaking();
            } else {
              await VoiceService.instance.speak(text);
            }
          },
        );
      },
    );
  }
}
