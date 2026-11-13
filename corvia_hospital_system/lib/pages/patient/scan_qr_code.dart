import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';

import '../../services/qr_scanner_service.dart';
import '../../widgets/input_device_button.dart';
import '../../theme/app_theme.dart';

enum _CameraPermissionState { unknown, granted, denied }

class ScanQrCodePage extends StatefulWidget {
  // ignore: non_constant_identifier_names
  const ScanQrCodePage({super.key, QrScannerService? scannerService})
      : _scannerService = scannerService;

  final QrScannerService? _scannerService;

  @override
  State<ScanQrCodePage> createState() => _ScanQrCodePageState();
}

class _ScanQrCodePageState extends State<ScanQrCodePage> {
  late final QrScannerService _service;
  bool _hasScanned = false;
  String? _lastCode;
  _CameraPermissionState _permissionState = _CameraPermissionState.unknown;
  bool _scannerStarted = false;
  bool _checkingCamera = true;
  bool _cameraAvailable = false;

  final QrRouteResolver _manualResolver = const QrRouteResolver();

  void _handleManualCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    final result = _manualResolver.resolve(trimmed);
    if (result != null) {
      _onResult(result);
    } else {
      _onUnknown(trimmed);
    }
  }

  Future<void> _showManualEntryDialog() async {
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.cBgSecondary,
        title: Text(
          'Enter Code Manually',
          style: TextStyle(color: context.cTextPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: context.cTextPrimary),
          decoration: const InputDecoration(
            hintText: 'Enter the patient check-in code',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (code != null && code.trim().isNotEmpty) {
      _handleManualCode(code);
    }
  }

  @override
  void initState() {
    super.initState();
    _service = widget._scannerService ?? MobileScannerService();
    _checkCameraAvailability();
  }

  Future<void> _checkCameraAvailability() async {
    final available = isWindowsDesktop || await _service.hasCamera();
    if (!mounted) return;
    setState(() {
      _checkingCamera = false;
      _cameraAvailable = available;
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _onResult(QrScanResult result) {
    if (_hasScanned) return;
    setState(() {
      _hasScanned = true;
      _lastCode = result.raw;
    });
    _navigate(result);
  }

  void _onUnknown(String raw) {
    if (_hasScanned) return;
    setState(() {
      _hasScanned = true;
      _lastCode = raw;
    });
    _showBottomSheet(raw);
  }

  void _onPermissionSet(bool granted) {
    if (!mounted) return;
    setState(() {
      _permissionState = granted
          ? _CameraPermissionState.granted
          : _CameraPermissionState.denied;
    });
  }

  void _startScanning() {
    setState(() {
      _scannerStarted = true;
    });
  }

  void _navigate(QrScanResult result) {
    Navigator.pushNamed(
      context,
      result.route,
      arguments: result.params.isNotEmpty ? result.params : null,
    );
  }

  void _showBottomSheet(String code) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cBgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, size: 52, color: CorviaColors.accentLight),
            const SizedBox(height: 12),
            Text(
              'QR Code Scanned',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary, fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _hasScanned = false;
                  _lastCode = null;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Again'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPrePermissionState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 64, color: CorviaColors.accentLight),
            const SizedBox(height: 16),
            Text(
              'Camera Access Needed',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Corvia needs access to your camera to scan QR codes for patient check-in. '
              'Tap below to allow camera access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary, fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _startScanning,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Enable Camera'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeniedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_photography, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              'Camera Access Denied',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Camera access was denied. To scan QR codes, please enable camera '
              'permission for Corvia in your device settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary, fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => AppSettings.openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _showManualEntryDialog,
              icon: const Icon(Icons.keyboard),
              label: const Text('Enter code manually'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerBody() {
    return Column(
      children: [
        Expanded(
          child: _service.buildScanner(
            onResult: _onResult,
            onUnknown: _onUnknown,
            onPermissionSet: _onPermissionSet,
          ),
        ),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: context.cBgSecondary,
            child: Column(
              children: [
                Text(
                  _lastCode == null
                      ? 'Point your camera at a Corvia QR code.'
                      : 'Last scanned: $_lastCode',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.cTextSecondary),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _showManualEntryDialog,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Enter code manually'),
                ),
              ],
            )),
      ],
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
            Text('Checking camera availability...'),
          ],
        ),
      );
    }
    if (!_cameraAvailable) {
      return _buildNoCameraState();
    }
    if (!_scannerStarted) {
      return _buildPrePermissionState();
    }
    if (_permissionState == _CameraPermissionState.denied) {
      return _buildDeniedState();
    }
    return _buildScannerBody();
  }

  Widget _buildNoCameraState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined,
                size: 72, color: context.cTextSecondary),
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
              'A camera is required to scan QR codes. '
              'Please use a device with a camera to access this feature.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _checkCameraAvailability,
              icon: const Icon(Icons.refresh),
              label: const Text('Check Again'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: !isWindowsDesktop &&
                _cameraAvailable &&
                _scannerStarted &&
                _permissionState != _CameraPermissionState.denied
            ? [
                IconButton(
                  tooltip: 'Flash',
                  icon: const Icon(Icons.flash_on),
                  onPressed: _service.toggleTorch,
                ),
                IconButton(
                  tooltip: 'Switch camera',
                  icon: const Icon(Icons.cameraswitch),
                  onPressed: _service.switchCamera,
                ),
              ]
            : null,
      ),
      body: _buildBody(),
    );
  }
}
