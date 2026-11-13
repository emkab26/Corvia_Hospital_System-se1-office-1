import 'package:collection/collection.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum NarratorPriority {
  low,
  normal,
  high,
  critical,
}

class NarrationTask {
  final String text;
  final NarratorPriority priority;
  final DateTime timestamp;

  NarrationTask({
    required this.text,
    required this.priority,
  }) : timestamp = DateTime.now();
}

class NarratorService {
  static final FlutterTts _tts = FlutterTts();

  static bool _enabled = false;
  static bool _isSpeaking = false;
  static bool _hasInitializedListeners = false;

  static String? _lastSpokenText;
  static DateTime? _lastSpokenTime;

  static final PriorityQueue<NarrationTask> _queue =
      PriorityQueue<NarrationTask>(
    (a, b) {
      final priorityComparison = b.priority.index.compareTo(a.priority.index);

      if (priorityComparison != 0) {
        return priorityComparison;
      }

      return a.timestamp.compareTo(b.timestamp);
    },
  );

  static bool get enabled => _enabled;

  static void _initListeners() {
    if (_hasInitializedListeners) {
      return;
    }

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _processQueue();
    });

    _tts.setErrorHandler((message) {
      _isSpeaking = false;
      _processQueue();
    });

    _hasInitializedListeners = true;
  }

  static void setEnabled(bool value) {
    _enabled = value;

    if (!_enabled) {
      stopAll();
      return;
    }

    _initListeners();
  }

  static Future<void> speak(
    String text, {
    NarratorPriority priority = NarratorPriority.normal,
  }) async {
    _initListeners();

    final cleanedText = text.trim();

    if (!_enabled || cleanedText.isEmpty) {
      return;
    }

    if (priority != NarratorPriority.critical &&
        cleanedText == _lastSpokenText) {
      final now = DateTime.now();

      if (_lastSpokenTime != null &&
          now.difference(_lastSpokenTime!).inSeconds < 4) {
        return;
      }
    }

    final task = NarrationTask(
      text: cleanedText,
      priority: priority,
    );

    if (priority == NarratorPriority.critical) {
      _queue.clear();
      _lastSpokenText = cleanedText;
      _lastSpokenTime = DateTime.now();
      _isSpeaking = true;

      await _tts.stop();
      await _tts.speak(cleanedText);
      return;
    }

    _queue.add(task);

    if (!_isSpeaking) {
      await _processQueue();
    }
  }

  static Future<void> _processQueue() async {
    if (_queue.isEmpty || !_enabled) {
      _isSpeaking = false;
      return;
    }

    _isSpeaking = true;

    final nextTask = _queue.removeFirst();

    _lastSpokenText = nextTask.text;
    _lastSpokenTime = DateTime.now();

    await _tts.speak(nextTask.text);
  }

  static Future<void> stopAll() async {
    _queue.clear();
    _isSpeaking = false;
    _lastSpokenText = null;
    _lastSpokenTime = null;

    await _tts.stop();
  }
}
