import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import '../services/qr_image_decoder.dart';
import '../services/windows_input_devices.dart';
import 'input_device_button.dart';

/// Keeps the mobile scanner lifecycle while providing Windows camera capture.
class CorviaScannerController extends ChangeNotifier {
  CorviaScannerController({
    DetectionSpeed detectionSpeed = DetectionSpeed.normal,
    List<BarcodeFormat> formats = const [],
  }) : mobile = isWindowsDesktop
            ? null
            : MobileScannerController(
                detectionSpeed: detectionSpeed, formats: formats);

  final MobileScannerController? mobile;
  bool running = true;
  String cameraId = '';

  Future<List<Object>> getSupportedLenses() async {
    if (isWindowsDesktop) return await WindowsInputDevices.cameras();
    return (await mobile!.getSupportedLenses()).toList();
  }

  Future<void> start() async {
    if (mobile != null) await mobile!.start();
    running = true;
    notifyListeners();
  }

  Future<void> stop() async {
    running = false;
    notifyListeners();
    if (mobile != null) await mobile!.stop();
  }

  Future<void> toggleTorch() async => mobile?.toggleTorch();
  Future<void> switchCamera() async => mobile?.switchCamera();

  @override
  void dispose() {
    mobile?.dispose();
    super.dispose();
  }
}

class CorviaScanner extends StatelessWidget {
  const CorviaScanner(
      {super.key,
      required this.controller,
      required this.onDetect,
      this.fit = BoxFit.cover,
      this.onDetectError,
      this.errorBuilder});
  final CorviaScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final BoxFit fit;
  final void Function(Object, StackTrace)? onDetectError;
  final Widget Function(BuildContext, MobileScannerException)? errorBuilder;

  @override
  Widget build(BuildContext context) => isWindowsDesktop
      ? _WindowsScanner(controller: controller, onDetect: onDetect)
      : MobileScanner(
          controller: controller.mobile!,
          onDetect: onDetect,
          fit: fit,
          onDetectError: onDetectError ?? _ignoreDetectionError,
          errorBuilder: errorBuilder ??
              (context, error) => ScannerErrorView(
                    error: error,
                    onRetry: controller.start,
                  ));

  static void _ignoreDetectionError(Object error, StackTrace stack) {}
}

/// Default camera error for [CorviaScanner].
///
/// mobile_scanner's built-in error widget prints the raw platform message
/// (for example "NotAllowedError: Permission dismissed") at full width, which
/// spills outside the scan frame the pages draw on top of the camera.
class ScannerErrorView extends StatelessWidget {
  const ScannerErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  /// Matches the 240 px scan frame drawn by the scanner pages, less padding.
  static const double maxTextWidth = 200;

  final MobileScannerException error;
  final Future<void> Function() onRetry;

  String get message => switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'Camera access is blocked. Allow camera access in your browser or '
              'device settings, then try again.',
        MobileScannerErrorCode.unsupported =>
          'This device has no camera the scanner can use.',
        _ => 'The camera could not start. Try again.',
      };

  @override
  Widget build(BuildContext context) {
    final canRetry = error.errorCode != MobileScannerErrorCode.unsupported;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxTextWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (canRetry) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowsScanner extends StatefulWidget {
  const _WindowsScanner({required this.controller, required this.onDetect});
  final CorviaScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  @override
  State<_WindowsScanner> createState() => _WindowsScannerState();
}

class _WindowsScannerState extends State<_WindowsScanner>
    with WidgetsBindingObserver {
  final _renderer = RTCVideoRenderer();
  MediaStream? _stream;
  Future<void> _queue = Future.value();
  Timer? _timer;
  bool _active = true;
  bool _disposed = false;
  bool _ready = false;
  int _generation = 0;
  String? _error;
  // captureFrame uses a fixed plugin temp filename. Serialize capture + cleanup
  // across scanner instances to avoid leaving patient QR images on disk.
  static Future<void> _captureQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_schedule);
    _queue = _renderer.initialize();
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _generation++;
    _queue = _queue.then((_) => _restart()).catchError((Object error) {
      if (mounted) {
        setState(() => _error =
            'Camera unavailable. Select another camera or check Windows camera permissions.');
      }
    });
  }

  Future<void> _release() async {
    _timer?.cancel();
    _timer = null;
    await _captureQueue;
    final old = _stream;
    _stream = null;
    _renderer.srcObject = null;
    if (old != null) {
      for (final track in old.getTracks()) {
        await track.stop();
      }
      await old.dispose();
    }
  }

  Future<void> _restart() async {
    await _release();
    if (_disposed || !_active || !widget.controller.running) return;
    if (mounted) {
      setState(() {
        _ready = false;
        _error = null;
      });
    }
    final id = widget.controller.cameraId;
    if (id.isNotEmpty &&
        !(await WindowsInputDevices.cameras()).any((d) => d.id == id)) {
      throw StateError('Selected camera disconnected');
    }
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        if (id.isNotEmpty) 'deviceId': id,
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '15'
        }
      },
    });
    _stream = stream;
    if (_disposed || !_active || !widget.controller.running) {
      await _release();
      return;
    }
    _renderer.srcObject = stream;
    if (mounted) setState(() => _ready = true);
    _timer = Timer(const Duration(milliseconds: 800), _scan);
  }

  Future<void> _scan() async {
    final stream = _stream;
    final generation = _generation;
    if (_disposed || !_active || !widget.controller.running || stream == null) {
      return;
    }
    String? code;
    try {
      final capture = _captureQueue.then((_) async {
        if (_disposed || _stream != stream) return;
        final temp =
            File('${(await getTemporaryDirectory()).path}/captureFrame.png');
        try {
          final bytes = await stream.getVideoTracks().first.captureFrame();
          code = await compute(decodeQrImage, bytes.asUint8List());
        } finally {
          if (await temp.exists()) await temp.delete();
        }
      });
      _captureQueue = capture.catchError((Object _) {});
      await capture;
      if (!_disposed &&
          _active &&
          widget.controller.running &&
          generation == _generation &&
          _stream == stream &&
          code != null) {
        widget.onDetect(BarcodeCapture(
            barcodes: [Barcode(rawValue: code, format: BarcodeFormat.qrCode)]));
      }
    } catch (_) {
      if (mounted && _stream == stream) {
        setState(() =>
            _error = 'Could not read the camera. Select a camera to retry.');
      }
      return;
    }
    if (!_disposed &&
        generation == _generation &&
        _stream == stream &&
        widget.controller.running) {
      _timer = Timer(const Duration(milliseconds: 600), _scan);
    }
  }

  Future<void> _select(String id) async {
    _generation++;
    final previous = widget.controller.cameraId;
    widget.controller.cameraId = id;
    final next = _queue.then((_) => _restart());
    _queue = next.catchError((Object _) {});
    try {
      await next;
    } catch (_) {
      widget.controller.cameraId = previous;
      _schedule();
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    widget.controller.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    _queue.then((_) async {
      await _captureQueue;
      await _release();
      await _renderer.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        if (_ready)
          RTCVideoView(_renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
        if (!_ready && _error == null && widget.controller.running)
          const Center(child: CircularProgressIndicator()),
        if (_error != null)
          Center(
              child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(_error!, textAlign: TextAlign.center))),
        Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: InputDeviceButton(
                  label: 'camera',
                  icon: Icons.video_settings,
                  selectedId: widget.controller.cameraId,
                  loadDevices: WindowsInputDevices.cameras,
                  onSelected: _select),
            )),
      ]);
}
