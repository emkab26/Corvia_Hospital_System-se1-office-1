import 'package:flutter/material.dart';

/// Time label plus a receipt tick for a message the viewer sent.
///
/// One tick means the server stored the message (it only appears once the
/// row exists). Two ticks mean the other person has opened the conversation
/// since it was sent. Device delivery is not tracked, so it is never claimed.
class MessageReceipt extends StatelessWidget {
  const MessageReceipt({
    super.key,
    required this.timeLabel,
    required this.color,
    this.sentAt,
    this.counterpartReadAt,
    this.showReceipt = true,
    this.fontSize = 11,
  });

  final String timeLabel;
  final Color color;
  final DateTime? sentAt;
  final DateTime? counterpartReadAt;
  final bool showReceipt;
  final double fontSize;

  bool get isRead =>
      sentAt != null &&
      counterpartReadAt != null &&
      !counterpartReadAt!.isBefore(sentAt!);

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: color, fontSize: fontSize);

    if (!showReceipt) {
      return Text(timeLabel, style: style);
    }

    final read = isRead;

    return Semantics(
      label: '$timeLabel, ${read ? 'read' : 'sent'}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (timeLabel.isNotEmpty) Text(timeLabel, style: style),
            const SizedBox(width: 4),
            Tooltip(
              message: read ? 'Read' : 'Sent',
              child: Icon(
                read ? Icons.done_all_rounded : Icons.done_rounded,
                size: fontSize + 4,
                color: read ? Colors.lightBlueAccent.shade100 : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
