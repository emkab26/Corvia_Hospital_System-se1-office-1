import '../../widgets/corvia_scanner.dart';
import '../../widgets/input_device_button.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';

const double _kMinTouchTarget = 48.0;

class DoctorQrScannerPage extends StatefulWidget {
  const DoctorQrScannerPage({super.key});

  @override
  State<DoctorQrScannerPage> createState() => _DoctorQrScannerPageState();
}

class _DoctorQrScannerPageState extends State<DoctorQrScannerPage> {
  final CorviaScannerController _scannerController = CorviaScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _hasScanned = false;
  bool _torchOn = false;
  bool _checkingCamera = true;
  bool _cameraAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkCameraAvailability();
  }

  Future<void> _checkCameraAvailability() async {
    if (isWindowsDesktop) {
      setState(() {
        _checkingCamera = false;
        _cameraAvailable = true;
      });
      return; // The Windows scanner shows device and permission recovery controls.
    }
    try {
      final lenses = await _scannerController.getSupportedLenses();
      if (!mounted) return;
      setState(() {
        _checkingCamera = false;
        _cameraAvailable = lenses.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingCamera = false;
        _cameraAvailable = false;
      });
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    final isValid = rawValue.startsWith('Patient ID:');

    setState(() {
      _hasScanned = true;
    });

    await _scannerController.stop();
    if (!mounted) return;

    if (!isValid) {
      await _showBottomSheet<void>(
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cancel_rounded, color: Colors.red, size: 46),
                  const SizedBox(height: 12),
                  Text(
                    'Invalid QR Code',
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This QR code is not a valid Patient ID.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.cTextSecondary),
                  ),
                  const SizedBox(height: 18),
                  // Touch target fix: explicit minimumSize ensures the
                  // button is at least 48dp tall regardless of label length.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: OutlinedButton.styleFrom(
                        minimumSize:
                            const Size(double.infinity, _kMinTouchTarget),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _restartScanner();
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      await _restartScanner();
      return;
    }

    await _showBottomSheet<void>(
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.green, size: 46),
                const SizedBox(height: 12),
                Text(
                  'Patient QR Scanned Successfully',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Corvia scanned this QR code successfully.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.cTextSecondary, fontSize: 14),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.cBgPrimary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    rawValue,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    // Touch target fix: minimumSize height set to 48dp on
                    // both buttons in this row.
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Scan Again'),
                        style: OutlinedButton.styleFrom(
                          minimumSize:
                              const Size(double.infinity, _kMinTouchTarget),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await _restartScanner();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize:
                              const Size(double.infinity, _kMinTouchTarget),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DoctorScannedQrResultPage(
                                qrValue: rawValue,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (mounted && _hasScanned) {
      await _restartScanner();
    }
  }

  Future<T?> _showBottomSheet<T>({
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: context.cBgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: builder,
    );
  }

  Future<void> _restartScanner() async {
    if (!mounted) return;

    setState(() {
      _hasScanned = false;
    });

    try {
      await _scannerController.start();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not restart QR scanner. Please reopen scanner.'),
        ),
      );
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _scannerController.toggleTorch();

      if (!mounted) return;

      setState(() {
        _torchOn = !_torchOn;
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Torch is not available on this device.'),
        ),
      );
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _scannerController.switchCamera();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not switch camera.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CorviaColors.primaryDark,
      appBar: AppBar(
        title: Text(
          'Scan Patient QR',
          style: TextStyle(color: context.cTextPrimary),
        ),
        backgroundColor: context.cBgSecondary,
        iconTheme: IconThemeData(color: context.cTextPrimary),
        actions: [
          // Touch target fix: explicit constraints + padding guarantee a
          // full 48x48dp tappable area even though the icon itself is 24dp.
          if (!isWindowsDesktop)
            IconButton(
              tooltip: _torchOn ? 'Turn torch off' : 'Turn torch on',
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              iconSize: 24,
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(
                minWidth: _kMinTouchTarget,
                minHeight: _kMinTouchTarget,
              ),
              onPressed: _toggleTorch,
            ),
          if (!isWindowsDesktop)
            IconButton(
              tooltip: 'Switch camera',
              icon: const Icon(Icons.cameraswitch),
              iconSize: 24,
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(
                minWidth: _kMinTouchTarget,
                minHeight: _kMinTouchTarget,
              ),
              onPressed: _switchCamera,
            ),

          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_checkingCamera) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking camera...'),
          ],
        ),
      );
    }

    if (!_cameraAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_outlined,
                  size: 72, color: context.cTextMuted),
              const SizedBox(height: 20),
              Text(
                'No Camera Available',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A camera is required to scan patient QR codes. '
                'Please use a device with a camera.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: _checkCameraAvailability,
                icon: const Icon(Icons.refresh),
                label: const Text('Check Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.cAccentReadable,
                  side: BorderSide(color: context.cDivider),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        CorviaScanner(
          controller: _scannerController,
          fit: BoxFit.cover,
          onDetect: _handleDetect,
          onDetectError: (error, stackTrace) {
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(friendlyErrorMessage(
                  error,
                  whatFailed: "The scanner couldn't start.",
                )),
              ),
            );
          },
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: _ScannerOverlay(
              borderColor: CorviaColors.accentLight,
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 28,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white,
                  size: 28,
                ),
                SizedBox(height: 8),
                Text(
                  'Position the patient QR code inside the frame',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'The scan will happen automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({
    required this.borderColor,
  });

  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final scanSize = width < height ? width * 0.72 : height * 0.62;

        return Stack(
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.55),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: scanSize,
                      height: scanSize,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: SizedBox(
                width: scanSize,
                height: scanSize,
                child: CustomPaint(
                  painter: _ScannerFramePainter(
                    color: borderColor,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScannerFramePainter extends CustomPainter {
  const _ScannerFramePainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 42.0;
    const radius = 22.0;

    final path = Path();

    path.moveTo(0, radius + cornerLength);
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.lineTo(radius + cornerLength, 0);

    path.moveTo(size.width - radius - cornerLength, 0);
    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);
    path.lineTo(size.width, radius + cornerLength);

    path.moveTo(size.width, size.height - radius - cornerLength);
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - radius,
      size.height,
    );
    path.lineTo(size.width - radius - cornerLength, size.height);

    path.moveTo(radius + cornerLength, size.height);
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.lineTo(0, size.height - radius - cornerLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerFramePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class DoctorScannedQrResultPage extends StatelessWidget {
  const DoctorScannedQrResultPage({
    super.key,
    required this.qrValue,
  });

  final String qrValue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Scanned Patient QR'),
        backgroundColor: context.cBgSecondary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: CorviaColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.qr_code_2,
                      color: CorviaColors.accentLight,
                      size: 42,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'QR scan successful',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This page is ready for the next step: loading the patient record from Supabase using the scanned QR value.',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Scanned value:',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.cBgPrimary,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: CorviaColors.divider),
                      ),
                      child: SelectableText(
                        qrValue,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Another Patient'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CorviaColors.accentLight,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, _kMinTouchTarget),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DoctorQrScannerPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
