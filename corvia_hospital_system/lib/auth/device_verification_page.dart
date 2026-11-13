import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../services/biometric_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Mandatory identity check shown once per device install.
///
/// Three paths:
/// • Web browser → skip local_auth and continue.
/// • Biometrics enrolled → OS prompt, auto-enables quick-unlock on success.
/// • No biometrics → password or OAuth verification fallback.
class DeviceVerificationPage extends StatefulWidget {
  final VoidCallback? onVerified;

  const DeviceVerificationPage({
    super.key,
    this.onVerified,
  });

  @override
  State<DeviceVerificationPage> createState() => _DeviceVerificationPageState();
}

class _DeviceVerificationPageState extends State<DeviceVerificationPage> {
  bool _checking = true;
  bool _scanning = false;
  bool _unavailable = false;
  bool _verifyingPassword = false;
  bool _verifyingGoogle = false;

  String? _errorMessage;
  String? _passwordError;
  String? _oauthError;

  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  StreamSubscription<AuthState>? _oauthSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verify();
    });
  }

  @override
  void dispose() {
    _oauthSub?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    // local_auth does not work on Chrome/web.
    // Allow browser testing to continue without biometric verification.
    if (kIsWeb) {
      SettingsService.instance.deviceVerified = true;

      if (!mounted) {
        return;
      }

      _finish();
      return;
    }

    if (_scanning) {
      return;
    }

    setState(() {
      _checking = true;
      _scanning = false;
      _unavailable = false;
      _errorMessage = null;
    });

    bool usable;

    try {
      usable = await BiometricService.hasUsableBiometrics();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _checking = false;
        _unavailable = true;
        _errorMessage =
            'Biometric verification is not available on this device.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    if (!usable) {
      setState(() {
        _checking = false;
        _unavailable = true;
      });
      return;
    }

    setState(() {
      _checking = false;
      _scanning = true;
    });

    List<BiometricType> types = [];

    try {
      types = await BiometricService.availableTypes();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _scanning = false;
        _unavailable = true;
      });
      return;
    }

    final hasFace = types.contains(BiometricType.face);
    final hasFingerprint = types.contains(BiometricType.fingerprint) ||
        types.contains(BiometricType.strong);

    final reason = hasFace
        ? 'Verify your identity with Face ID to use Corvia on this device.'
        : hasFingerprint
            ? 'Verify your identity with your fingerprint to use Corvia on this device.'
            : 'Verify your identity to use Corvia on this device.';

    final result = await BiometricService.authenticate(reason: reason);

    if (!mounted) {
      return;
    }

    switch (result) {
      case AuthResult.success:
        if (hasFace) {
          SettingsService.instance.faceIdLogin = true;
        } else if (hasFingerprint) {
          SettingsService.instance.fingerprintLogin = true;
        }

        await BiometricService.offerSetupIfNeeded(context);

        if (!mounted) {
          return;
        }

        SettingsService.instance.deviceVerified = true;
        _finish();
        return;

      case AuthResult.unavailable:
        setState(() {
          _scanning = false;
          _unavailable = true;
        });
        return;

      case AuthResult.failed:
        setState(() {
          _scanning = false;
          _errorMessage = 'Verification failed. Tap to try again.';
        });
        return;
    }
  }

  bool get _isOAuthAccount {
    final provider = Supabase
        .instance.client.auth.currentUser?.appMetadata['provider'] as String?;

    return provider != null && provider != 'email';
  }

  String get _providerName {
    final provider = Supabase
        .instance.client.auth.currentUser?.appMetadata['provider'] as String?;

    if (provider == null || provider.isEmpty) {
      return 'social';
    }

    return provider[0].toUpperCase() + provider.substring(1);
  }

  Future<void> _verifyPassword() async {
    final email = Supabase.instance.client.auth.currentUser?.email;

    if (email == null) {
      setState(() {
        _passwordError =
            'Password verification is not available for this account type. '
            'Please set up biometrics to continue.';
      });
      return;
    }

    final password = _passwordController.text.trim();

    if (password.isEmpty) {
      setState(() {
        _passwordError = 'Please enter your password.';
      });
      return;
    }

    setState(() {
      _verifyingPassword = true;
      _passwordError = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) {
        return;
      }

      await BiometricService.offerSetupIfNeeded(context);

      if (!mounted) {
        return;
      }

      SettingsService.instance.deviceVerified = true;
      _finish();
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _verifyingPassword = false;
        _passwordError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _verifyingPassword = false;
        _passwordError = 'Verification failed. Please try again.';
      });
    }
  }

  Future<void> _verifyWithGoogle() async {
    final auth = Supabase.instance.client.auth;
    final originalUserId = auth.currentUser?.id;
    final originalToken = auth.currentSession?.accessToken;

    if (originalUserId == null) {
      return;
    }

    setState(() {
      _verifyingGoogle = true;
      _oauthError = null;
    });

    _oauthSub?.cancel();

    _oauthSub = auth.onAuthStateChange.listen((data) async {
      if (data.event != AuthChangeEvent.signedIn) {
        return;
      }

      if (data.session?.accessToken == originalToken) {
        return;
      }

      final returnedId = data.session?.user.id;

      _oauthSub?.cancel();
      _oauthSub = null;

      if (!mounted) {
        return;
      }

      if (returnedId != originalUserId) {
        setState(() {
          _verifyingGoogle = false;
          _oauthError =
              'That is a different $_providerName account. Please sign in '
              'with the same account you used to register with Corvia.';
        });
        return;
      }

      await BiometricService.offerSetupIfNeeded(context);

      if (!mounted) {
        return;
      }

      SettingsService.instance.deviceVerified = true;
      _finish();
    });

    try {
      await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Env.oauthRedirectUrl,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      _oauthSub?.cancel();
      _oauthSub = null;

      setState(() {
        _verifyingGoogle = false;
        _oauthError = 'Could not open Google sign-in. Please try again.';
      });
    }
  }

  void _cancelGoogleVerification() {
    _oauthSub?.cancel();
    _oauthSub = null;

    if (!mounted) {
      return;
    }

    setState(() {
      _verifyingGoogle = false;
      _oauthError = null;
    });
  }

  Future<void> _openSettings() async {
    final launched = await BiometricService.openBiometricSettings();

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open your device Settings and search for '
            '"Face ID" or "Fingerprint" to set up biometrics.',
          ),
        ),
      );
    }
  }

  void _finish() {
    if (widget.onVerified != null) {
      widget.onVerified!();
      return;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      body: PopScope(
        canPop: false,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              child: _unavailable ? _buildUnavailableUI() : _buildBiometricUI(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricUI() {
    final busy = _checking || _scanning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.verified_user,
          color: CorviaColors.accent,
          size: 72,
        ),
        const SizedBox(height: 16),
        Text(
          'Verify Your Identity',
          style: TextStyle(
            color: CorviaColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'This looks like a new device. Please confirm your identity '
          'before continuing - just like signing in to your banking app '
          'for the first time on a new phone.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: CorviaColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 56),
        GestureDetector(
          onTap: busy ? null : _verify,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busy
                  ? CorviaColors.accent.withValues(alpha: 0.3)
                  : CorviaColors.accent.withValues(alpha: 0.15),
              border: Border.all(
                color: CorviaColors.accent,
                width: 2,
              ),
            ),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: CircularProgressIndicator(
                      color: CorviaColors.accent,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    Icons.face,
                    color: CorviaColors.accent,
                    size: 52,
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _checking
              ? 'Checking biometrics…'
              : _scanning
                  ? 'Scanning…'
                  : 'Tap to verify',
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
          onPressed: _signOut,
          child: Text(
            'Sign out and use a different account',
            style: TextStyle(
              color: CorviaColors.accentLight,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnavailableUI() {
    final isOAuth = _isOAuthAccount;
    final fallbackLabel =
        isOAuth ? 're-verify with $_providerName' : 'verify with your password';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.lock_outline,
          color: CorviaColors.accent,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          'Verify Your Identity',
          style: TextStyle(
            color: CorviaColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'No biometrics are set up on this device. To continue, '
          'set up Face ID or fingerprint - or $fallbackLabel.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: CorviaColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.face,
                    color: CorviaColors.accent,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Set Up Face ID / Fingerprint',
                      style: TextStyle(
                        color: CorviaColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Open your device Settings, enrol your biometrics, '
                'then return here and tap Try Again.',
                style: TextStyle(
                  color: CorviaColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(
                        Icons.settings_outlined,
                        size: 18,
                      ),
                      label: const Text('Open Settings'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CorviaColors.accent,
                        side: BorderSide(
                          color: CorviaColors.accent.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _verify,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try Again'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CorviaColors.accent,
                        side: BorderSide(
                          color: CorviaColors.accent.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Divider(color: CorviaColors.divider),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(
                  color: CorviaColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Divider(color: CorviaColors.divider),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (isOAuth) _buildGoogleVerifyCard() else _buildPasswordCard(),
        const SizedBox(height: 32),
        TextButton(
          onPressed: _signOut,
          child: Text(
            'Sign out and use a different account',
            style: TextStyle(
              color: CorviaColors.accentLight,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock,
                color: CorviaColors.accent,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verify with Password',
                  style: TextStyle(
                    color: CorviaColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: TextStyle(color: CorviaColors.textPrimary),
            onSubmitted: (_) {
              if (!_verifyingPassword) {
                _verifyPassword();
              }
            },
            decoration: InputDecoration(
              hintText: 'Your Corvia password',
              hintStyle: TextStyle(
                color: CorviaColors.textMuted,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: CorviaColors.textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),
          if (_passwordError != null) ...[
            const SizedBox(height: 8),
            Text(
              _passwordError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _verifyingPassword ? null : _verifyPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: CorviaColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _verifyingPassword
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text('Verify Identity'),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleVerifyCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_circle,
                color: CorviaColors.accent,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verify with $_providerName',
                  style: TextStyle(
                    color: CorviaColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your account uses $_providerName sign-in. Re-verify with '
            'the same account to confirm your identity on this device.',
            style: TextStyle(
              color: CorviaColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (_oauthError != null) ...[
            const SizedBox(height: 8),
            Text(
              _oauthError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_verifyingGoogle)
            Row(
              children: [
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: CorviaColors.accent,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Waiting for $_providerName…',
                    style: TextStyle(
                      color: CorviaColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _cancelGoogleVerification,
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: CorviaColors.accentLight,
                    ),
                  ),
                ),
              ],
            )
          else
            ElevatedButton.icon(
              onPressed: _verifyWithGoogle,
              icon: Image.asset(
                'assets/google.jpeg',
                height: 18,
                width: 18,
              ),
              label: Text('Re-verify with $_providerName'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CorviaColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CorviaColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: child,
    );
  }
}
