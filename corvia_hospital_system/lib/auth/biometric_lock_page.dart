import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/biometric_service.dart';
import '../theme/app_theme.dart';
import '../widgets/corvia_logo.dart';

class BiometricLockPage extends StatefulWidget {
  final VoidCallback onUnlocked;

  const BiometricLockPage({
    super.key,
    required this.onUnlocked,
  });

  @override
  State<BiometricLockPage> createState() => _BiometricLockPageState();
}

class _BiometricLockPageState extends State<BiometricLockPage> {
  bool _authenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  Future<void> _authenticate() async {
    // Chrome/web cannot use local_auth.
    // Browser testing unlocks the session immediately.
    if (kIsWeb) {
      if (!mounted) {
        return;
      }

      widget.onUnlocked();
      return;
    }

    if (_authenticating) {
      return;
    }

    setState(() {
      _authenticating = true;
      _errorMessage = null;
    });

    final types = await BiometricService.availableTypes();

    final hasFace = types.contains(BiometricType.face) ||
        types.contains(BiometricType.strong);

    final hasFingerprint = types.contains(BiometricType.fingerprint) ||
        types.contains(BiometricType.strong);

    String reason;

    if (hasFace && hasFingerprint) {
      reason = 'Use your face or fingerprint to unlock Corvia.';
    } else if (hasFace) {
      reason = 'Use Face ID to unlock Corvia.';
    } else if (hasFingerprint) {
      reason = 'Use your fingerprint to unlock Corvia.';
    } else {
      reason = 'Verify your identity to unlock Corvia.';
    }

    final result = await BiometricService.authenticate(
      reason: reason,
    );

    if (!mounted) {
      return;
    }

    if (result == AuthResult.success) {
      widget.onUnlocked();
      return;
    }

    setState(() {
      _authenticating = false;
      _errorMessage = result == AuthResult.unavailable
          ? 'Biometric authentication is unavailable on this device.'
          : 'Authentication failed. Please try again.';
    });
  }

  Future<void> _signOutAndUsePassword() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CorviaLogo(size: 88),
                const SizedBox(height: 16),
                Text(
                  'Corvia',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your session is locked',
                  style: TextStyle(
                    color: CorviaColors.textSecondary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 64),
                GestureDetector(
                  onTap: _authenticating ? null : _authenticate,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _authenticating
                          ? CorviaColors.accent.withValues(alpha: 0.3)
                          : CorviaColors.accent.withValues(alpha: 0.15),
                      border: Border.all(
                        color: CorviaColors.accent,
                        width: 2,
                      ),
                    ),
                    child: _authenticating
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              color: CorviaColors.accent,
                              strokeWidth: 3,
                            ),
                          )
                        : Icon(
                            Icons.fingerprint,
                            color: CorviaColors.accent,
                            size: 48,
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _authenticating
                      ? 'Waiting for biometric…'
                      : 'Tap to authenticate',
                  style: TextStyle(
                    color: CorviaColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 48),
                TextButton(
                  onPressed: _signOutAndUsePassword,
                  child: Text(
                    'Use password instead',
                    style: TextStyle(
                      color: CorviaColors.accentLight,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
