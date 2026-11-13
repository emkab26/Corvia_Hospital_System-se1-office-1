import 'dart:async';

/// Owns the cancellable pre-call delay. It never owns a submitted server call.
class CallCountdown {
  CallCountdown({required this.onChanged, required this.onElapsed});
  final void Function() onChanged;
  final Future<void> Function() onElapsed;
  Timer? _timer;
  bool _disposed = false;
  int remaining = 3;
  bool get running => _timer?.isActive == true;

  void start() {
    if (_disposed || running) return;
    remaining = 3;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) return;
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
        onChanged();
        unawaited(onElapsed());
      } else {
        onChanged();
      }
    });
    onChanged();
  }

  void cancel() {
    _timer?.cancel();
    remaining = 3;
    if (!_disposed) onChanged();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
