import 'package:flutter/material.dart';

/// A Fleet deep link returns to the root authentication and role gate.
/// Authorised hospital staff can then open Fleet from their dashboard.
class FleetEntryRedirect extends StatefulWidget {
  const FleetEntryRedirect({super.key});

  @override
  State<FleetEntryRedirect> createState() => _FleetEntryRedirectState();
}

class _FleetEntryRedirectState extends State<FleetEntryRedirect> {
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
