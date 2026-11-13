import '../../widgets/corvia_scanner.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/walk_in_qr_service.dart';
import '../../theme/app_theme.dart';
import 'patient_walk_in_check_in_page.dart';

class ScanCodePage extends StatefulWidget {
  const ScanCodePage({super.key});

  @override
  State<ScanCodePage> createState() => _ScanCodePageState();
}

class _ScanCodePageState extends State<ScanCodePage> {
  final CorviaScannerController _controller = CorviaScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final WalkInQrService _service = WalkInQrService();

  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;

    setState(() => _processing = true);
    await _controller.stop();

    try {
      final destination = await _service.validatePayload(raw);
      if (!mounted) return;

      final joined = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PatientWalkInCheckInPage(destination: destination),
        ),
      );

      if (!mounted) return;
      if (joined == true) {
        Navigator.of(context).pop(true);
        return;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    }

    if (!mounted) return;
    setState(() => _processing = false);
    await _controller.start();
  }

  String _friendlyError(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('valid corvia')) {
      return 'This is not a Corvia reception walk-in QR code.';
    }
    if (value.contains('inactive') || value.contains('invalid')) {
      return 'This reception QR is no longer active. Ask Reception for the current code.';
    }
    if (value.contains('patient profile')) {
      return 'Your account is not linked to an active patient profile.';
    }
    return 'The reception QR could not be verified. Check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(title: const Text('Walk-in Check-in')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CorviaScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: CorviaColors.accentLight,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              color: context.cBgSecondary.withValues(alpha: 0.94),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_processing)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: CircularProgressIndicator(),
                    )
                  else
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      color: CorviaColors.accentLight,
                      size: 34,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    _processing
                        ? 'Verifying reception...'
                        : 'Scan the walk-in QR displayed at Reception.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'This check-in is for patients who do not have an appointment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
