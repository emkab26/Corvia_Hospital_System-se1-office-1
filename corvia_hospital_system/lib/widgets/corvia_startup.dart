import 'package:flutter/material.dart';
import 'emergency_phone_card.dart';

enum CorviaStartupStage {
  configuration('configuration'),
  backend('backend and session'),
  settings('settings'),
  wearables('wearables'),
  notifications('notifications');

  const CorviaStartupStage(this.label);
  final String label;
}

/// Phone fallback is rendered before network or optional services initialize.
class CorviaStartup extends StatefulWidget {
  const CorviaStartup(
      {super.key, this.initialize, this.initializeWithStage, required this.ready})
      : assert(initialize != null || initializeWithStage != null);
  final Future<void> Function()? initialize;
  final Future<void> Function(void Function(CorviaStartupStage) stage)?
      initializeWithStage;
  final Widget ready;
  @override
  State<CorviaStartup> createState() => _CorviaStartupState();
}

class _CorviaStartupState extends State<CorviaStartup> {
  bool _ready = false, _failed = false, _initializing = false;
  CorviaStartupStage _stage = CorviaStartupStage.configuration;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    _initializing = true;
    if (mounted) setState(() => _failed = false);
    try {
      final initialize = widget.initializeWithStage;
      await (initialize == null
              ? widget.initialize!()
              : initialize((stage) {
                  if (mounted) setState(() => _stage = stage);
                }))
          .timeout(const Duration(seconds: 30));
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _initializing = false;
    }
  }

  @override
  Widget build(BuildContext context) => _ready
      ? widget.ready
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
              appBar: AppBar(title: const Text('Corvia')),
              body: SafeArea(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const EmergencyPhoneCard(),
                            const SizedBox(height: 24),
                            if (!_failed) const LinearProgressIndicator(),
                            Text(_failed
                                ? 'Corvia could not finish starting during ${_stage.label}. Check the configuration or connection, then retry. Emergency calling remains available.'
                                : 'Starting Corvia: ${_stage.label}. Emergency calling is available now.'),
                            if (_failed)
                              FilledButton(
                                  onPressed: _initializing ? null : _initialize,
                                  child: const Text('Retry startup')),
                          ])))));
}
