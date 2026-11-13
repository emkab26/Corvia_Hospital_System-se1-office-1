import '../widgets/corvia_scanner.dart';
import 'package:flutter/widgets.dart';

abstract class QrPayload {
  static const String checkIn = 'CORVIA_CHECKIN';
  static const String doctor = 'CORVIA_DOCTOR';
  static const String emergency = 'CORVIA_EMERGENCY';
  static const String patient = 'CORVIA_PATIENT';
  static const String walkIn = 'CORVIA_WALKIN';

  /// Payload version, carried so a scanner can tell which parameter set it is
  /// looking at. Bump it when the parameters for a prefix change.
  static const String version = '1';

  /// Builds a payload in the one form [QrRouteResolver] can read.
  ///
  /// Generators must come through here rather than composing the string
  /// themselves. The emergency screen used to hand-roll a colon-separated value
  /// that the resolver never matched, so the app could not scan the emergency
  /// code it had just drawn, and nothing failed until someone scanned it.
  static String build(String prefix, Map<String, String> params) {
    final buffer = StringBuffer(prefix)..write('|v=$version');
    params.forEach((key, value) => buffer.write('|$key=$value'));
    return buffer.toString();
  }

  /// The emergency medical profile payload for [patientId].
  static String emergencyProfile(String patientId) =>
      build(emergency, {'patient_id': patientId});
}

class QrScanResult {
  const QrScanResult(
      {required this.raw, required this.route, this.params = const {}});

  final String raw;

  final String route;

  final Map<String, String> params;

  @override
  String toString() => 'QrScanResult(route: $route, params: $params)';
}

class QrRouteResolver {
  const QrRouteResolver();

  QrScanResult? resolve(String raw) {
    final parts = raw.split('|');
    if (parts.isEmpty) return null;

    final prefix = parts.first.trim();
    final params = <String, String>{};
    for (final part in parts.skip(1)) {
      final kv = part.split('=');
      if (kv.length == 2) params[kv[0].trim()] = kv[1].trim();
    }

    final route = _routeForPrefix(prefix);
    if (route == null) return null;

    return QrScanResult(raw: raw, route: route, params: params);
  }

  String? _routeForPrefix(String prefix) {
    switch (prefix) {
      case QrPayload.checkIn:
        return '/dashboard';
      case QrPayload.doctor:
        return '/patient-records';
      case QrPayload.emergency:
        return '/emergency';
      case QrPayload.patient:
        return '/profile';
      default:
        return null;
    }
  }
}

abstract class QrScannerService {
  Widget buildScanner({
    required void Function(QrScanResult result) onResult,
    required void Function(String raw) onUnknown,
    void Function(bool granted)? onPermissionSet,
  });

  void toggleTorch();

  void switchCamera();

  void dispose();

  /// Checks whether the device has at least one camera available for scanning.
  ///
  /// Returns `true` if at least one camera is available, `false` otherwise.
  Future<bool> hasCamera();
}

class MobileScannerService implements QrScannerService {
  MobileScannerService({QrRouteResolver? resolver})
      : _resolver = resolver ?? const QrRouteResolver(),
        _ctrl = CorviaScannerController();

  final QrRouteResolver _resolver;
  final CorviaScannerController _ctrl;

  @override
  Widget buildScanner({
    required void Function(QrScanResult result) onResult,
    required void Function(String raw) onUnknown,
    void Function(bool granted)? onPermissionSet,
  }) {
    return CorviaScanner(
      controller: _ctrl,
      onDetect: (capture) {
        final raw = capture.barcodes.first.rawValue;
        if (raw == null || raw.trim().isEmpty) return;

        final result = _resolver.resolve(raw);
        if (result != null) {
          onResult(result);
        } else {
          onUnknown(raw);
        }
      },
      errorBuilder: (context, error) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onPermissionSet?.call(false);
        });
        return const SizedBox.shrink();
      },
    );
  }

  @override
  void toggleTorch() => _ctrl.toggleTorch();

  @override
  void switchCamera() => _ctrl.switchCamera();

  @override
  void dispose() => _ctrl.dispose();

  @override
  Future<bool> hasCamera() async {
    try {
      final lenses = await _ctrl.getSupportedLenses();
      return lenses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
