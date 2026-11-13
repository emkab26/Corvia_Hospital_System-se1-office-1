import '../../widgets/corvia_scanner.dart';
import '../../widgets/input_device_button.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/reception_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/text_controller_scope.dart';

class ReceptionQrCheckInPage extends StatefulWidget {
  const ReceptionQrCheckInPage({super.key});

  @override
  State<ReceptionQrCheckInPage> createState() => _ReceptionQrCheckInPageState();
}

class _ReceptionQrCheckInPageState extends State<ReceptionQrCheckInPage> {
  final ReceptionService _service = ReceptionService();

  final CorviaScannerController _controller = CorviaScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _busy = false;
  bool _hasScanned = false;

  String? _error;
  ReceptionQrPreview? _preview;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _hasScanned || capture.barcodes.isEmpty) {
      return;
    }

    final raw = capture.barcodes.first.rawValue;

    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    await _processQr(raw);
  }

  Future<void> _processQr(String raw) async {
    if (_busy || _hasScanned) {
      return;
    }

    setState(() {
      _busy = true;
      _hasScanned = true;
      _error = null;
      _preview = null;
    });

    try {
      await _controller.stop();

      final parsed = _parseQr(raw);

      if (parsed.patientId == null || parsed.appointmentId == null) {
        throw Exception('This is not a valid Corvia appointment QR code.');
      }

      final preview = await _service.loadQrPreview(
        patientId: parsed.patientId!,
        appointmentId: parsed.appointmentId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preview = preview;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = _cleanError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openManualQrEntry() async {
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          builder: (controller) {
            return AlertDialog(
              title: const Text('Enter QR Code'),
              content: TextField(
                controller: controller,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'CORVIA_CHECKIN|patient_id=...|appointment_id=...',
                  alignLabelWithHint: true,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(controller.text.trim());
                  },
                  child: const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    if (entered == null || entered.isEmpty) {
      return;
    }

    await _processQr(entered);
  }

  Future<void> _confirmCheckIn() async {
    final preview = _preview;

    if (preview == null ||
        !preview.hasAppointment ||
        preview.appointmentId.isEmpty) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await _service.confirmQrCheckIn(
        patientId: preview.patientId,
        appointmentId: preview.appointmentId,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient checked in successfully.'),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (error) {
      _showMessage(_cleanError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _scanAgain() {
    setState(() {
      _hasScanned = false;
      _error = null;
      _preview = null;
    });

    _controller.start();
  }

  _ParsedQr _parseQr(String raw) {
    final text = raw.trim();

    return _ParsedQr(
      patientId: _findUuidValue(text, 'patient_id') ??
          _findUuidValue(text, 'patientId'),
      appointmentId: _findUuidValue(text, 'appointment_id') ??
          _findUuidValue(text, 'appointmentId'),
    );
  }

  String? _findUuidValue(String text, String key) {
    final equalsPattern = RegExp(
      '$key=([0-9a-fA-F-]{36})',
      caseSensitive: false,
    );

    final colonPattern = RegExp(
      '$key:([0-9a-fA-F-]{36})',
      caseSensitive: false,
    );

    final equalsMatch = equalsPattern.firstMatch(text);

    if (equalsMatch != null) {
      return equalsMatch.group(1);
    }

    final colonMatch = colonPattern.firstMatch(text);

    return colonMatch?.group(1);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll('PostgrestException(message: ', '')
        .replaceAll(')', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('QR Check-In'),
        actions: [
          IconButton(
            tooltip: 'Enter QR manually',
            onPressed: _busy ? null : _openManualQrEntry,
            icon: const Icon(Icons.keyboard_rounded),
          ),
          if (!isWindowsDesktop)
            IconButton(
              tooltip: 'Flash',
              onPressed: _controller.toggleTorch,
              icon: const Icon(Icons.flash_on_rounded),
            ),
          if (!isWindowsDesktop)
            IconButton(
              tooltip: 'Switch camera',
              onPressed: _controller.switchCamera,
              icon: const Icon(Icons.cameraswitch_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                CorviaScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_busy)
                  Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
          _bottomPanel(),
        ],
      ),
    );
  }

  Widget _bottomPanel() {
    if (_preview != null) {
      return _previewPanel(_preview!);
    }

    if (_error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: context.cBgSecondary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Colors.red.shade400,
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _scanAgain,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan Again'),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: context.cBgSecondary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Scan a patient appointment QR code to check them in.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _openManualQrEntry,
            icon: const Icon(Icons.keyboard_rounded),
            label: const Text('Enter QR code manually'),
          ),
        ],
      ),
    );
  }

  Widget _previewPanel(ReceptionQrPreview preview) {
    final appointmentTime = preview.appointmentTime == null
        ? 'No appointment time'
        : DateFormat('EEE, d MMM • HH:mm').format(
            preview.appointmentTime!,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: context.cBgSecondary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Colors.green,
            size: 38,
          ),
          const SizedBox(height: 8),
          Text(
            preview.patientName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            preview.patientNumber,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${preview.departmentName} • ${preview.doctorName}\n'
            '$appointmentTime\n'
            '${preview.reason}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _scanAgain,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Scan Again'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _confirmCheckIn,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Check In'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParsedQr {
  const _ParsedQr({
    required this.patientId,
    required this.appointmentId,
  });

  final String? patientId;
  final String? appointmentId;
}
