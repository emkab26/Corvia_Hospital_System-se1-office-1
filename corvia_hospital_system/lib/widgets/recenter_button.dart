import 'package:flutter/material.dart';

class RecenterButton extends StatelessWidget {
  final VoidCallback onPressed;

  const RecenterButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: 'Recenter map',
      child: const Icon(Icons.my_location),
    );
  }
}
