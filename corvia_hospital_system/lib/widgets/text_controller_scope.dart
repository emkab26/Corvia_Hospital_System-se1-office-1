import 'package:flutter/material.dart';

/// Owns a [TextEditingController] for the lifetime of the widget subtree that
/// uses it.
///
/// Use this inside a `showDialog` builder instead of creating the controller
/// before `showDialog` and disposing it once the future completes. That future
/// completes on `pop`, while the dialog is still animating out and its
/// `TextField` still listens to the controller, so disposing there throws
/// `_dependents.isEmpty is not true`. Here the controller is disposed only when
/// the dialog's widgets are removed.
class TextControllerScope extends StatefulWidget {
  const TextControllerScope({
    super.key,
    this.initialText = '',
    required this.builder,
  });

  final String initialText;
  final Widget Function(TextEditingController controller) builder;

  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}
