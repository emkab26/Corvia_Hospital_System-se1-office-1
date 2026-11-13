import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import 'settings_service.dart';

enum AuthResult {
  success,
  failed,
  unavailable,
}

class BiometricService {
  BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    if (kIsWeb) {
      return false;
    }

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();

      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasUsableBiometrics() async {
    if (kIsWeb) {
      return false;
    }

    if (!await isAvailable()) {
      return false;
    }

    final types = await availableTypes();

    return types.isNotEmpty;
  }

  static Future<List<BiometricType>> availableTypes() async {
    if (kIsWeb) {
      return [];
    }

    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  static Future<AuthResult> authenticate({
    String reason = 'Confirm your identity to continue.',
  }) async {
    if (kIsWeb) {
      return AuthResult.unavailable;
    }

    try {
      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      return authenticated ? AuthResult.success : AuthResult.failed;
    } on LocalAuthException catch (error) {
      switch (error.code) {
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          return AuthResult.unavailable;

        default:
          return AuthResult.failed;
      }
    } catch (_) {
      return AuthResult.failed;
    }
  }

  static Future<bool> openBiometricSettings() async {
    if (kIsWeb) {
      return false;
    }

    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }

  static Future<void> offerSetupIfNeeded(BuildContext context) async {
    if (kIsWeb) {
      return;
    }

    final settings = SettingsService.instance;
    final types = await availableTypes();

    final hasFace = types.contains(BiometricType.face) ||
        types.contains(BiometricType.strong);

    final hasFingerprint = types.contains(BiometricType.fingerprint) ||
        types.contains(BiometricType.strong);

    final String featureName;
    final IconData featureIcon;
    final VoidCallback enable;

    if (hasFace && !settings.faceIdLogin) {
      featureName = 'Face ID';
      featureIcon = Icons.face;
      enable = () => settings.faceIdLogin = true;
    } else if (hasFingerprint && !settings.fingerprintLogin) {
      featureName = 'Fingerprint';
      featureIcon = Icons.fingerprint;
      enable = () => settings.fingerprintLogin = true;
    } else {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final wantsSetup = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(featureIcon, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Use $featureName?'),
              ),
            ],
          ),
          content: Text(
            'Sign in to Corvia securely with $featureName - '
            'the same way you unlock your banking app.\n\n'
            'You can change this anytime in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );

    if (wantsSetup != true || !context.mounted) {
      return;
    }

    final result = await authenticate(
      reason: 'Authenticate once to enable $featureName login.',
    );

    if (!context.mounted) {
      return;
    }

    if (result == AuthResult.success) {
      enable();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$featureName login enabled.'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You can enable biometric login later in Settings.',
        ),
      ),
    );
  }
}
