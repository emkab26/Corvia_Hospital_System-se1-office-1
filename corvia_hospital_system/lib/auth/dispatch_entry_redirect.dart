import 'package:flutter/material.dart';

/// A dispatch deep link returns through the one root authentication gate.
/// It never instantiates a second auth flow or a role-selected dashboard.
class DispatchEntryRedirect extends StatefulWidget {
  const DispatchEntryRedirect({super.key});
  @override
  State<DispatchEntryRedirect> createState() => _DispatchEntryRedirectState();
}

class _DispatchEntryRedirectState extends State<DispatchEntryRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Opening your workspace...')),
      );
}
