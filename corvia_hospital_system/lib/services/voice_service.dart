import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../widgets/input_device_button.dart';
import 'windows_input_devices.dart';

/// Central singleton that wraps `speech_to_text` (voice input) and
/// `flutter_tts` (read-back). Both APIs are lazy-initialised on first use.
///
/// Only one STT listening session and one TTS playback can be active at a
/// time. The two `ValueNotifier`s let UI widgets react to state changes
/// (e.g. flip a mic icon between "tap to speak" and "stop").
class VoiceService {
  VoiceService._();
  static final instance = VoiceService._();

  // STT
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _sttInitialized = false;

  /// True while the mic is actively transcribing.
  final ValueNotifier<bool> isListening = ValueNotifier<bool>(false);

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _ttsInitialized = false;

  /// The text currently being read aloud, or null when idle. UI buttons can
  /// listen to this to flip their icon while their own text is playing.
  final ValueNotifier<String?> currentSpeakingText =
      ValueNotifier<String?>(null);

  // Permission

  /// Ensure microphone permission is granted, requesting it if needed.
  Future<bool> ensureMicPermission() async {
    // Windows desktop capture is governed by Windows privacy settings.
    if (isWindowsDesktop) return true;
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  // STT public API

  Future<bool> _ensureSttReady() async {
    if (_sttInitialized && _stt.isAvailable) return true;
    try {
      _sttInitialized = await _stt.initialize(
        onError: (_) => isListening.value = false,
        onStatus: (status) {
          if (status == stt.SpeechToText.doneStatus ||
              status == stt.SpeechToText.notListeningStatus) {
            isListening.value = false;
          }
        },
      );
    } catch (_) {
      _sttInitialized = false;
    }
    return _sttInitialized;
  }

  /// Start a listening session. Each partial result is delivered via
  /// [onResult] together with whether it's the final result.
  ///
  /// Returns false if mic permission was denied or STT isn't available.
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResult,
    String localeId = 'en_US',
    String microphoneId = '',
  }) async {
    if (isListening.value) return true; // already running

    final hasMic = await ensureMicPermission();
    if (!hasMic) return false;

    final ready = await _ensureSttReady();
    if (!ready) return false;

    if (isWindowsDesktop) {
      try {
        await WindowsInputDevices.selectSpeechMicrophone(microphoneId);
      } catch (_) {
        return false;
      }
    }

    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 3),
        localeId: localeId,
      ),
    );
    isListening.value = true;
    return true;
  }

  Future<void> stopListening() async {
    if (!isListening.value) return;
    await _stt.stop();
    isListening.value = false;
  }

  // TTS public API

  Future<bool> _ensureTtsReady() async {
    if (_ttsInitialized) return true;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() => currentSpeakingText.value = null);
      _tts.setCancelHandler(() => currentSpeakingText.value = null);
      _tts.setErrorHandler((_) => currentSpeakingText.value = null);
      _ttsInitialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Read [text] aloud. Stops any current speech first.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    final ready = await _ensureTtsReady();
    if (!ready) return;
    await _tts.stop();
    currentSpeakingText.value = text;
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    if (!_ttsInitialized) return;
    await _tts.stop();
    currentSpeakingText.value = null;
  }

  /// Clean up - call from app-level dispose if you ever do one.
  Future<void> dispose() async {
    await _stt.stop();
    await _tts.stop();
  }
}
