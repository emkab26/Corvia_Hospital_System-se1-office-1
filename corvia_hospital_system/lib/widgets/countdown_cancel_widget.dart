import 'dart:async';
import 'package:flutter/material.dart';

class CountdownCancelWidget extends StatefulWidget {
  const CountdownCancelWidget({
    super.key,
    required this.seconds,
    required this.label,
    required this.onComplete,
    required this.onCancel,
    this.ringColor,
    this.urgentColor,
    this.cancelLabel = 'Cancel',
  });

  final int seconds;
  final String label;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final Color? ringColor;
  final Color? urgentColor;
  final String cancelLabel;

  @override
  State<CountdownCancelWidget> createState() => _CountdownCancelWidgetState();
}

class _CountdownCancelWidgetState extends State<CountdownCancelWidget> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.seconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        widget.onComplete();
      }
    });
  }

  void _handleCancel() {
    _timer?.cancel();
    widget.onCancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _secondsLeft / widget.seconds;
    final isUrgent = _secondsLeft <= 2;
    final ringColor = isUrgent
        ? (widget.urgentColor ?? Colors.orangeAccent)
        : (widget.ringColor ?? Colors.redAccent);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                key: const Key('countdown_ring'),
                value: progress,
                strokeWidth: 7,
                backgroundColor: Colors.grey.shade300,
                color: ringColor,
              ),
            ),
            Text(
              key: const Key('countdown_seconds'),
              '$_secondsLeft',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          key: const Key('countdown_label'),
          '${widget.label} $_secondsLeft second${_secondsLeft == 1 ? '' : 's'}...',
          style: const TextStyle(fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('countdown_cancel_button'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _handleCancel,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(widget.cancelLabel,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
