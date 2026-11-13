import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/blood_bank_service.dart';
import '../../widgets/corvia_scanner.dart';

class BloodBankScanPanel extends StatefulWidget {
  const BloodBankScanPanel(
      {super.key,
      required this.service,
      required this.hospitalId,
      required this.onFound,
      required this.onDenied,
      required this.onBack});
  final BloodBankService service;
  final String hospitalId;
  final ValueChanged<String> onFound, onDenied;
  final VoidCallback onBack;
  @override
  State<BloodBankScanPanel> createState() => _BloodBankScanPanelState();
}

class _BloodBankScanPanelState extends State<BloodBankScanPanel> {
  final _text = TextEditingController();
  CorviaScannerController? _camera;
  BloodBankCommand? _pending;
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _camera?.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _lookup(String value) async {
    if (_busy) return;
    if (value.trim().isEmpty || value.length > 500) {
      setState(() => _message = 'Enter a unit number or Corvia unit QR value.');
      return;
    }
    _pending ??=
        BloodBankCommand(widget.hospitalId, 'scan', {'raw_scan': value});
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.service.lookupScan(_pending!);
      if (!mounted) return;
      _pending = null;
      if (result['status'] == 'matched') {
        widget.onFound(result['unit_number'] as String);
        return;
      }
      setState(() => _message =
          'No matching unit in this hospital. Supplier formats must match a registered unit number exactly.');
    } catch (e) {
      if (!mounted) return;
      if (BloodBankService.accessDenied(e)) {
        widget.onDenied(BloodBankService.message(e));
        return;
      }
      if (BloodBankService.definitelyRejected(e)) _pending = null;
      setState(() => _message = BloodBankService.message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Text('Find blood unit', style: Theme.of(context).textTheme.titleLarge),
        const Text(
            'Scan a Corvia unit QR or enter the exact unit number. Lookup requires the backend and does not receive or issue stock.'),
        const SizedBox(height: 12),
        if (_camera == null)
          OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Open camera'),
              onPressed: _busy || _pending != null
                  ? null
                  : () => setState(() => _camera = CorviaScannerController(
                      detectionSpeed: DetectionSpeed.noDuplicates)))
        else
          SizedBox(
              height: 250,
              child: CorviaScanner(
                  controller: _camera!,
                  errorBuilder: (_, __) => const Center(
                      child: Text(
                          'Camera unavailable. Check permission or enter the unit number below.')),
                  onDetect: (capture) {
                    if (_busy || _pending != null) return;
                    final raw = capture.barcodes.firstOrNull?.rawValue;
                    if (raw == null) return;
                    final camera = _camera!;
                    setState(() => _camera = null);
                    camera.dispose();
                    _text.text = raw;
                    _lookup(raw);
                  })),
        TextField(
            controller: _text,
            enabled: !_busy && _pending == null,
            maxLength: 500,
            decoration:
                const InputDecoration(labelText: 'Unit number / scanned value'),
            onSubmitted: _lookup),
        if (_message != null) Text(_message!),
        if (_pending != null)
          const Text(
              'Retry keeps the same scan reference. No stock movement is performed.'),
        Wrap(spacing: 12, children: [
          FilledButton(
              onPressed: _busy ? null : () => _lookup(_text.text),
              child: Text(_busy
                  ? 'Looking up…'
                  : _pending == null
                      ? 'Find unit'
                      : 'Retry lookup')),
          TextButton(
              onPressed: _busy ? null : widget.onBack,
              child: const Text('Back to stock')),
        ]),
      ]);
}
