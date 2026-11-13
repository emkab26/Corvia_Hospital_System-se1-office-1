import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../pages/patient/emergency_phone_page.dart';
import '../theme/app_theme.dart';
import '../services/validation_service.dart';
import 'register.dart';
import '../widgets/corvia_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _emailController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _isSigningIn = false;
  bool _googleLoginStarted = false;

  @override
  void initState() {
    super.initState();

    /*
     * Cancel any active autofill context that may have been
     * created by Chrome or by a previous login form.
     */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TextInput.finishAutofillContext(
        shouldSave: false,
      );
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  void _selectAllText({
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }

    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void _clearEmail() {
    if (_isSigningIn) {
      return;
    }

    setState(() {
      _emailController.clear();
    });

    _emailFocusNode.requestFocus();
  }

  void _clearPassword() {
    if (_isSigningIn) {
      return;
    }

    setState(() {
      _passwordController.clear();
    });

    _passwordFocusNode.requestFocus();
  }

  Future<void> _signInWithEmail() async {
    if (_isSigningIn) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final emailError =
        ValidationService.validateEmail(email);

    if (emailError != null) {
      _showMessage(emailError);
      return;
    }

    final passwordError =
        ValidationService.validatePassword(password);

    if (passwordError != null) {
      _showMessage(passwordError);

      /*
       * IMPORTANT:
       *
       * Do not continue to Supabase login when
       * local password validation already failed.
       */
      return;
    }

    FocusScope.of(context).unfocus();

    TextInput.finishAutofillContext(
      shouldSave: false,
    );

    setState(() {
      _isSigningIn = true;
      _googleLoginStarted = false;
    });

    var shouldSelectPasswordAfterFailure = false;

    try {
      /*
       * Login only authenticates the account.
       *
       * AuthGate listens for the Supabase session and
       * automatically routes the user according to the
       * Corvia account role.
       *
       * Do not manually push another AuthGate here.
       */
      final response =
          await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null ||
          response.session == null) {
        throw const AuthException(
          'Login did not return an active session.',
        );
      }

      if (!mounted) {
        return;
      }

      _showMessage(
        'Login successful.',
      );
    } on AuthException catch (error) {
      shouldSelectPasswordAfterFailure = true;

      if (!mounted) {
        return;
      }

      _showMessage(
        _friendlyAuthError(
          error.message,
        ),
      );
    } catch (error, stackTrace) {
      shouldSelectPasswordAfterFailure = true;

      debugPrint(
        'Login error: $error\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Could not sign in. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });

        if (shouldSelectPasswordAfterFailure) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) {
              if (!mounted) {
                return;
              }

              _selectAllText(
                controller:
                    _passwordController,
                focusNode:
                    _passwordFocusNode,
              );
            },
          );
        }
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isSigningIn) {
      return;
    }

    FocusScope.of(context).unfocus();

    TextInput.finishAutofillContext(
      shouldSave: false,
    );

    setState(() {
      _isSigningIn = true;
      _googleLoginStarted = true;
    });

    try {
      final started =
          await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Env.oauthRedirectUrl,
      );

      if (!mounted) {
        return;
      }

      if (!started) {
        _showMessage(
          'Google sign-in could not be started.',
        );
        return;
      }

      _showMessage(
        'Complete the Google sign-in in your browser.',
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _friendlyAuthError(
          error.message,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Google login error: $error\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Google sign-in failed. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
          _googleLoginStarted = false;
        });
      }
    }
  }

  String _friendlyAuthError(
    String message,
  ) {
    final lowerMessage =
        message.toLowerCase();

    if (lowerMessage.contains(
          'invalid login credentials',
        ) ||
        lowerMessage.contains(
          'invalid credentials',
        )) {
      return 'Incorrect email address or password.';
    }

    if (lowerMessage.contains(
      'email not confirmed',
    )) {
      return 'Confirm your email address before signing in.';
    }

    if (lowerMessage.contains(
          'too many requests',
        ) ||
        lowerMessage.contains(
          'rate limit',
        )) {
      return 'Too many login attempts. '
          'Wait a moment and try again.';
    }

    if (lowerMessage.contains(
          'network',
        ) ||
        lowerMessage.contains(
          'failed to fetch',
        ) ||
        lowerMessage.contains(
          'socket',
        )) {
      return 'Could not connect to Corvia. '
          'Check your internet connection.';
    }

    return message;
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
        ),
      );
  }

  void _openRegisterPage() {
    if (_isSigningIn) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return const RegisterPage();
        },
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color:
            colorScheme.onSurfaceVariant,
      ),
      prefixIcon: Icon(
        icon,
        color:
            colorScheme.primary,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor:
          colorScheme.surface,
      enabledBorder:
          OutlineInputBorder(
        borderSide: BorderSide(
          color:
              colorScheme.outline,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderSide: BorderSide(
          color:
              colorScheme.primary,
          width: 2,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
      disabledBorder:
          OutlineInputBorder(
        borderSide: BorderSide(
          color:
              colorScheme.outline.withValues(
            alpha: 0.45,
          ),
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
      errorBorder:
          OutlineInputBorder(
        borderSide: BorderSide(
          color:
              colorScheme.error,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
      focusedErrorBorder:
          OutlineInputBorder(
        borderSide: BorderSide(
          color:
              colorScheme.error,
          width: 2,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
    );
  }

  Widget _buildEmailField(
    ColorScheme colorScheme,
  ) {
    return CallbackShortcuts(
      bindings:
          <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
        ): () {
          _selectAllText(
            controller:
                _emailController,
            focusNode:
                _emailFocusNode,
          );
        },
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          meta: true,
        ): () {
          _selectAllText(
            controller:
                _emailController,
            focusNode:
                _emailFocusNode,
          );
        },
      },
      child: TextField(
        key:
            const Key('emailField'),
        controller:
            _emailController,
        focusNode:
            _emailFocusNode,
        enabled:
            !_isSigningIn,
        readOnly:
            false,
        enableInteractiveSelection:
            true,
        keyboardType:
            TextInputType.emailAddress,
        textInputAction:
            TextInputAction.next,

        /*
         * Null disables Flutter autofill
         * for this field on web.
         */
        autofillHints:
            null,
        autocorrect:
            false,
        enableSuggestions:
            false,
        inputFormatters: [
          FilteringTextInputFormatter.deny(
            RegExp(r'\s'),
          ),
        ],
        style: TextStyle(
          color:
              colorScheme.onSurface,
          fontSize:
              16,
          fontWeight:
              FontWeight.w500,
        ),
        cursorColor:
            colorScheme.primary,
        decoration:
            _inputDecoration(
          label:
              'Email Address',
          icon:
              Icons.email_outlined,
          suffixIcon:
              IconButton(
            tooltip:
                'Clear email',
            onPressed:
                _isSigningIn
                    ? null
                    : _clearEmail,
            icon: Icon(
              Icons.clear_rounded,
              color:
                  colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        onTap: () {
          if (_emailController
                  .selection.start <
              0) {
            _emailController.selection =
                TextSelection.collapsed(
              offset:
                  _emailController.text.length,
            );
          }
        },
        onSubmitted: (_) {
          _passwordFocusNode
              .requestFocus();
        },
      ),
    );
  }

  Widget _buildPasswordField(
    ColorScheme colorScheme,
  ) {
    return CallbackShortcuts(
      bindings:
          <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
        ): () {
          _selectAllText(
            controller:
                _passwordController,
            focusNode:
                _passwordFocusNode,
          );
        },
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          meta: true,
        ): () {
          _selectAllText(
            controller:
                _passwordController,
            focusNode:
                _passwordFocusNode,
          );
        },
      },
      child: TextField(
        key:
            const Key('passwordField'),
        controller:
            _passwordController,
        focusNode:
            _passwordFocusNode,
        enabled:
            !_isSigningIn,
        readOnly:
            false,
        enableInteractiveSelection:
            true,
        obscureText:
            _obscurePassword,
        keyboardType:
            TextInputType.visiblePassword,
        textInputAction:
            TextInputAction.done,

        /*
         * Null disables Flutter autofill
         * for this field on web.
         */
        autofillHints:
            null,
        autocorrect:
            false,
        enableSuggestions:
            false,
        style: TextStyle(
          color:
              colorScheme.onSurface,
          fontSize:
              16,
          fontWeight:
              FontWeight.w500,
        ),
        cursorColor:
            colorScheme.primary,
        decoration:
            _inputDecoration(
          label:
              'Password',
          icon:
              Icons.lock_outline,
          suffixIcon:
              SizedBox(
            width:
                96,
            child:
                Row(
              mainAxisAlignment:
                  MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip:
                      'Clear password',
                  onPressed:
                      _isSigningIn
                          ? null
                          : _clearPassword,
                  icon: Icon(
                    Icons.clear_rounded,
                    color:
                        colorScheme.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  tooltip:
                      _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                  onPressed:
                      _isSigningIn
                          ? null
                          : () {
                              setState(
                                () {
                                  _obscurePassword =
                                      !_obscurePassword;
                                },
                              );

                              WidgetsBinding
                                  .instance
                                  .addPostFrameCallback(
                                (_) {
                                  if (!mounted) {
                                    return;
                                  }

                                  _passwordFocusNode
                                      .requestFocus();

                                  _passwordController
                                          .selection =
                                      TextSelection
                                          .collapsed(
                                    offset:
                                        _passwordController
                                            .text
                                            .length,
                                  );
                                },
                              );
                            },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color:
                        CorviaColors.accentLight,
                  ),
                ),
              ],
            ),
          ),
        ),
        onTap: () {
          if (_passwordController
                  .selection.start <
              0) {
            _passwordController.selection =
                TextSelection.collapsed(
              offset:
                  _passwordController.text.length,
            );
          }
        },
        onSubmitted: (_) {
          _signInWithEmail();
        },
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final year =
        DateTime.now().year;

    final colorScheme =
        Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor:
          context.cBgPrimary,
      appBar:
          AppBar(
        automaticallyImplyLeading:
            false,
        title:
            const Text(
          'Welcome',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const EmergencyPhonePage(),
            )),
            icon: const Icon(Icons.emergency),
            label: const Text('Emergency help'),
          ),
        ],
      ),
      body:
          SafeArea(
        child:
            Center(
          child:
              SingleChildScrollView(
            padding:
                const EdgeInsets.all(
              20,
            ),
            child:
                ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth:
                    620,
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(
                    height:
                        30,
                  ),
                  const Center(
                    child: CorviaLogo(
                      size: 88,
                    ),
                  ),
                  const SizedBox(
                    height:
                        16,
                  ),
                  Text(
                    'Welcome Back to Corvia!',
                    textAlign:
                        TextAlign.center,
                    style:
                        TextStyle(
                      fontSize:
                          26,
                      fontWeight:
                          FontWeight.bold,
                      color:
                          CorviaColors.accent,
                    ),
                  ),
                  const SizedBox(
                    height:
                        10,
                  ),
                  Text(
                    'Sign in to continue to your '
                    'medical dashboard.',
                    textAlign:
                        TextAlign.center,
                    style:
                        TextStyle(
                      color:
                          context.cTextSecondary,
                      fontSize:
                          15,
                    ),
                  ),
                  const SizedBox(
                    height:
                        36,
                  ),
                  _buildEmailField(
                    colorScheme,
                  ),
                  const SizedBox(
                    height:
                        16,
                  ),
                  _buildPasswordField(
                    colorScheme,
                  ),
                  const SizedBox(
                    height:
                        25,
                  ),
                  if (_isSigningIn)
                    Column(
                      children: [
                        CircularProgressIndicator(
                          color:
                              CorviaColors.accent,
                        ),
                        const SizedBox(
                          height:
                              12,
                        ),
                        Text(
                          _googleLoginStarted
                              ? 'Waiting for Google sign-in...'
                              : 'Signing in...',
                          style:
                              TextStyle(
                            color:
                                context.cTextSecondary,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          ElevatedButton(
                        key:
                            const Key(
                          'loginButton',
                        ),
                        onPressed:
                            _signInWithEmail,
                        child:
                            const Padding(
                          padding:
                              EdgeInsets.symmetric(
                            vertical:
                                4,
                          ),
                          child:
                              Text(
                            'Login',
                            style:
                                TextStyle(
                              fontSize:
                                  18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(
                      height:
                          12,
                    ),
                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            _signInWithGoogle,
                        icon:
                            Image.asset(
                          'assets/google.jpeg',
                          height:
                              24,
                          width:
                              24,
                          errorBuilder:
                              (
                            context,
                            error,
                            stackTrace,
                          ) {
                            return const Icon(
                              Icons.login,
                              size:
                                  24,
                            );
                          },
                        ),
                        label:
                            const Text(
                          'Login with Google',
                          style:
                              TextStyle(
                            fontSize:
                                16,
                          ),
                        ),
                        style:
                            ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.white,
                          foregroundColor:
                              Colors.black87,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(
                    height:
                        16,
                  ),
                  TextButton(
                    onPressed:
                        _isSigningIn
                            ? null
                            : _openRegisterPage,
                    child:
                        Text(
                      "Don't have an account? Register",
                      style:
                          TextStyle(
                        color:
                            CorviaColors.accentLight,
                        fontSize:
                            16,
                      ),
                    ),
                  ),
                  const SizedBox(
                    height:
                        40,
                  ),
                  Text(
                    '© Corvia. All Rights Reserved $year',
                    textAlign:
                        TextAlign.center,
                    style:
                        TextStyle(
                      color:
                          context.cTextSecondary,
                      fontSize:
                          14,
                      fontWeight:
                          FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}