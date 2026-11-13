import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  final String message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(message),
    );
  }
}
