import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mycorvia/pages/shared/policy_page.dart';
import 'package:mycorvia/pages/shared/terms_and_conditions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';
import '../config/env.dart';
import '../services/validation_service.dart';
import '../theme/app_theme.dart';
import '../widgets/corvia_logo.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
  });

  @override
  State<RegisterPage> createState() {
    return _RegisterPageState();
  }
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _surnameController =
      TextEditingController();

  final TextEditingController _emailController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  final TextEditingController _idController =
      TextEditingController();

  final TextEditingController _addressController =
      TextEditingController();

  final TextEditingController _phoneController =
      TextEditingController();

  final TextEditingController _confirmPasswordController =
      TextEditingController();

  DateTime? _dob;

  File? _selectedImage;

  bool _loading = false;

  final GlobalKey<FormState> _formKey =
      GlobalKey<FormState>();

  final SupabaseClient supabase =
      Supabase.instance.client;

  bool? termsAndConditionsChecked = false;
  bool termsAndConditionsRead = false;

  bool? policyChecked = false;
  bool policyRead = false;

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _idController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  // ============================================================
  // PROFILE IMAGE
  // ============================================================

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
    );

    if (result == null ||
        result.files.single.path == null ||
        !mounted) {
      return;
    }

    setState(() {
      _selectedImage = File(
        result.files.single.path!,
      );
    });
  }

  Future<String?> _uploadProfilePicture(
    String userId,
  ) async {
    if (_selectedImage == null) {
      return null;
    }

    try {
      final fileExt =
          _selectedImage!.path.split('.').last;

      final filePath =
          'profiles/$userId.$fileExt';

      await supabase.storage
          .from(
            'profile_pictures',
          )
          .upload(
            filePath,
            _selectedImage!,
            fileOptions: const FileOptions(
              upsert: true,
            ),
          );

      return supabase.storage
          .from(
            'profile_pictures',
          )
          .getPublicUrl(
            filePath,
          );
    } catch (error) {
      debugPrint(
        'Profile picture upload failed: $error',
      );

      return null;
    }
  }

  // ============================================================
  // TERMS / POLICY
  // ============================================================

  void termsAndConditions() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            const TermsAndConditionsPage(),
      ),
    );

    setState(() {
      termsAndConditionsRead = true;
    });
  }

  void policy() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            const PolicyPage(),
      ),
    );

    setState(() {
      policyRead = true;
    });
  }

  // ============================================================
  // REGISTER
  // ============================================================

  Future<void> _registerUser() async {
    if (_loading) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      _snack(
        'Please fix the errors above.',
      );

      return;
    }

    final idNumber =
        _idController.text.trim();

    final email =
        _emailController.text.trim();

    final password =
        _passwordController.text;

    final firstName =
        _nameController.text.trim();

    final surname =
        _surnameController.text.trim();

    final address =
        _addressController.text.trim();

    final phone =
        _phoneController.text.trim();

    final dobIso = _dob == null
        ? null
        : DateFormat(
            'yyyy-MM-dd',
          ).format(
            _dob!,
          );

    setState(() {
      _loading = true;
    });

    try {
      // ========================================================
      // CREATE SUPABASE AUTH ACCOUNT
      // ========================================================

      final signUpResponse =
          await supabase.auth.signUp(
        email: email,
        password: password,

        /*
         * AndroidManifest + .env must both use:
         *
         * mycorvia://login-callback
         */
        emailRedirectTo:
            Env.oauthRedirectUrl,

        /*
         * Patient information is temporarily stored
         * in Auth user metadata.
         *
         * After email verification AuthGate will use
         * this to finish the Corvia patient setup.
         *
         * NEVER trust this metadata for privileged
         * hospital/staff authorization.
         */
        data: {
          'corvia_registration_type':
              'patient_self_registration',
          'registration_schema_version':
              1,
          'first_name':
              firstName,
          'surname':
              surname,
          'id_number':
              idNumber,
          'address':
              address,
          'phone':
              phone,
          'date_of_birth':
              dobIso,
        },
      );

      final createdUser =
          signUpResponse.user;

      if (createdUser == null) {
        _snack(
          'Registration failed.',
        );

        return;
      }

      // ========================================================
      // EMAIL CONFIRMATION FLOW
      // ========================================================
      //
      // IMPORTANT FIX:
      //
      // If email verification is enabled Supabase returns:
      //
      // user    != null
      // session == null
      //
      // Previously Corvia simply returned here.
      //
      // That left RegisterPage sitting ABOVE AuthGate.
      //
      // When the verification link later created a session,
      // AuthGate correctly changed to Biometrics / Dashboard,
      // but RegisterPage covered it.
      //
      // We now return to the root AuthGate immediately.
      // ========================================================

      if (signUpResponse.session == null) {
        if (!mounted) {
          return;
        }

        _snack(
          'Account created. Please check your email and verify your account.',
        );

        /*
         * Return to the ROOT AuthGate.
         *
         * Because there is no session yet AuthGate will
         * currently display LoginPage.
         *
         * Once the verification email opens:
         *
         * Supabase session
         *      ↓
         * AuthGate
         *      ↓
         * Device Verification
         *      ↓
         * Biometrics
         *      ↓
         * Patient Dashboard
         *
         * We DO NOT push Dashboard manually.
         */
        await routeAfterLogin(
          context,
        );

        return;
      }

      // ========================================================
      // IMMEDIATE SESSION / AUTOCONFIRM FLOW
      // ========================================================

      final loggedInUser =
          signUpResponse.session!.user;

      final imageUrl =
          await _uploadProfilePicture(
        loggedInUser.id,
      );

      // ========================================================
      // PROFILE
      // ========================================================

      final profileResponse =
          await supabase
              .from(
                'profiles',
              )
              .upsert(
                {
                  'user_id':
                      loggedInUser.id,
                  'id_number':
                      idNumber,
                  'first_name':
                      firstName,
                  'surname':
                      surname,
                  'email':
                      email,
                  'address':
                      address,
                  'phone_number':
                      phone,
                  'phone':
                      phone,
                  'date_of_birth':
                      dobIso,
                  'avatar_url':
                      imageUrl,
                  'profile_picture_url':
                      imageUrl,
                },
                onConflict:
                    'user_id',
              )
              .select(
                'user_id',
              )
              .single();

      final profileUserId =
          profileResponse['user_id']
              ?.toString()
              .trim();

      if (profileUserId == null ||
          profileUserId !=
              loggedInUser.id) {
        _snack(
          'Profile creation failed.',
        );

        return;
      }

      // ========================================================
      // PATIENT
      // ========================================================

      await supabase
          .from(
            'patients',
          )
          .upsert(
            {
              /*
               * IMPORTANT:
               *
               * Corvia convention:
               *
               * patients.profile_id
               * =
               * auth.uid()
               * =
               * profiles.user_id
               */
              'profile_id':
                  loggedInUser.id,

              'created_by':
                  loggedInUser.id,

              'date_of_birth':
                  dobIso,

              'emergency_contact_phone':
                  phone,

              'is_active':
                  true,
            },
            onConflict:
                'profile_id',
          );

      // ========================================================
      // INITIAL EMERGENCY PROFILE
      // ========================================================

      await _createInitialEmergencyProfile(
        profileId:
            loggedInUser.id,
        userId:
            loggedInUser.id,
        firstName:
            firstName,
        surname:
            surname,
        phone:
            phone,
      );

      if (!mounted) {
        return;
      }

      _snack(
        'Registration successful.',
      );

      /*
       * Again:
       *
       * Do NOT push Dashboard directly.
       *
       * Root AuthGate decides whether this user needs:
       *
       * Device verification
       * Biometrics
       * Role choice
       * Patient dashboard
       */
      await routeAfterLogin(
        context,
      );
    } on AuthException catch (error) {
      final message =
          error.message.toLowerCase();

      if (message.contains(
            'rate limit',
          ) ||
          message.contains(
            'too many requests',
          ) ||
          message.contains(
            'email rate',
          )) {
        _snack(
          'Too many verification emails were requested. '
          'Please wait before trying again.',
        );

        return;
      }

      if (message.contains(
            'already registered',
          ) ||
          message.contains(
            'already exists',
          )) {
        _snack(
          'An account already exists for this email. '
          'Try signing in instead.',
        );

        return;
      }

      _snack(
        error.message,
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'Registration DB error: $error',
      );

      _snack(
        'Something went wrong while saving your details. '
        'Please try again.',
      );
    } catch (error) {
      debugPrint(
        'Registration unexpected error: $error',
      );

      _snack(
        'An unexpected error occurred. '
        'Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // EMERGENCY PROFILE
  // ============================================================

  Future<void> _createInitialEmergencyProfile({
    required String profileId,
    required String userId,
    required String firstName,
    required String surname,
    required String phone,
  }) async {
    try {
      final patientRow =
          await supabase
              .from(
                'patients',
              )
              .select(
                'id',
              )
              .eq(
                'profile_id',
                profileId,
              )
              .maybeSingle();

      final patientId =
          patientRow?['id']
              ?.toString()
              .trim();

      if (patientId == null ||
          patientId.isEmpty) {
        return;
      }

      await supabase
          .from(
            'emergency_profiles',
          )
          .upsert(
            {
              'patient_id':
                  patientId,
              'created_by':
                  userId,
              'patient_name':
                  '$firstName $surname'
                      .trim(),
              'emergency_contact_phone':
                  phone,
              'allergies':
                  'Not provided',
              'current_medications':
                  'Not provided',
              'medical_conditions':
                  'Not provided',
              'notes':
                  'Created during registration.',
            },
            onConflict:
                'patient_id',
          );
    } catch (error) {
      /*
       * Emergency setup is useful, but it must never
       * block successful patient registration.
       */
      debugPrint(
        'Emergency profile creation skipped: $error',
      );
    }
  }

  // ============================================================
  // DATE OF BIRTH
  // ============================================================

  Future<void> _pickDob() async {
    final now =
        DateTime.now();

    final initial =
        _dob ??
        DateTime(
          now.year - 25,
          now.month,
          now.day,
        );

    final picked =
        await showDatePicker(
      context:
          context,
      initialDate:
          initial,
      firstDate:
          DateTime(
        1900,
      ),
      lastDate:
          now,
      helpText:
          'Select date of birth',
      cancelText:
          'Cancel',
      confirmText:
          'OK',
      builder:
          (
        ctx,
        child,
      ) {
        return Theme(
          data:
              ThemeData.light().copyWith(
            colorScheme:
                ColorScheme.light(
              primary:
                  CorviaColors.accent,
              onPrimary:
                  Colors.white,
              surface:
                  Colors.white,
              onSurface:
                  const Color(
                0xFF111827,
              ),
            ),
            scaffoldBackgroundColor:
                Colors.white,
            dialogTheme:
                const DialogThemeData(
              backgroundColor:
                  Colors.white,
            ),
            textTheme:
                ThemeData.light()
                    .textTheme
                    .apply(
              bodyColor:
                  const Color(
                0xFF111827,
              ),
              displayColor:
                  const Color(
                0xFF111827,
              ),
            ),
            textButtonTheme:
                TextButtonThemeData(
              style:
                  TextButton.styleFrom(
                foregroundColor:
                    CorviaColors.accent,
              ),
            ),
          ),
          child:
              child ??
              const SizedBox.shrink(),
        );
      },
    );

    if (picked != null &&
        mounted) {
      setState(() {
        _dob = picked;
      });

      _formKey.currentState
          ?.validate();
    }
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _snack(
    String msg,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    )
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text(
            msg,
          ),
        ),
      );
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  String? _validateIdNumber(
    String? value,
  ) {
    if (value == null ||
        value.trim().isEmpty) {
      return 'ID Number is required';
    }

    final trimmed =
        value.trim();

    if (trimmed.length != 13) {
      return 'Must be exactly 13 digits';
    }

    if (int.tryParse(
          trimmed,
        ) ==
        null) {
      return 'Digits only';
    }

    return null;
  }

  String? _validateEmail(
    String? value,
  ) {
    return ValidationService
        .validateEmail(
      value,
    );
  }

  String? _validatePassword(
    String? value,
  ) {
    return ValidationService
        .validatePassword(
      value,
    );
  }

  String? _validateConfirmPassword(
    String? value,
  ) {
    if (value == null ||
        value.isEmpty) {
      return 'Please confirm your password';
    }

    if (value !=
        _passwordController.text) {
      return 'Passwords do not match';
    }

    return null;
  }

  String? _validatePhone(
    String? value,
  ) {
    return ValidationService
        .validatePhone(
      value,
    );
  }

  // ============================================================
  // FORM FIELD
  // ============================================================

  Widget _field(
    String label,
    TextEditingController controller, {
    Key? fieldKey,
    bool obscure = false,
    TextInputType? keyboard,
    bool required = false,
    String? Function(String?)?
        customValidator,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical:
            8,
      ),
      child:
          TextFormField(
        key:
            fieldKey,
        controller:
            controller,
        obscureText:
            obscure,
        keyboardType:
            keyboard,
        style:
            TextStyle(
          color:
              CorviaColors.textPrimary,
        ),
        decoration:
            InputDecoration(
          label:
              _labelWidget(
            label,
            required,
          ),
        ),
        validator:
            customValidator ??
            (
              required
                  ? (
                      value,
                    ) {
                      if (value ==
                              null ||
                          value
                              .trim()
                              .isEmpty) {
                        return '$label is required';
                      }

                      return null;
                    }
                  : null
            ),
        autovalidateMode:
            AutovalidateMode
                .onUnfocus,
      ),
    );
  }

  // ============================================================
  // DOB FIELD
  // ============================================================

  Widget _dobPickerField() {
    final hasValue =
        _dob != null;

    final display =
        hasValue
        ? DateFormat(
            'd MMMM yyyy',
          ).format(
            _dob!,
          )
        : 'Select a date';

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical:
            8,
      ),
      child:
          InkWell(
        onTap:
            _pickDob,
        borderRadius:
            BorderRadius.circular(
          8,
        ),
        child:
            InputDecorator(
          decoration:
              InputDecoration(
            label:
                _labelWidget(
              'Date of Birth',
              false,
            ),
            suffixIcon:
                Icon(
              Icons.calendar_today,
              color:
                  CorviaColors
                      .accentLight,
              size:
                  20,
            ),
          ),
          child:
              Text(
            display,
            style:
                TextStyle(
              color:
                  hasValue
                  ? CorviaColors
                      .textPrimary
                  : Colors.grey,
              fontSize:
                  16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _labelWidget(
    String label,
    bool required,
  ) {
    if (!required) {
      return Text(
        label,
      );
    }

    return Text.rich(
      TextSpan(
        text:
            label,
        children:
            const [
          TextSpan(
            text:
                ' *',
            style:
                TextStyle(
              color:
                  Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PAGE
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          context.cBgPrimary,

      appBar:
          AppBar(
        title:
            const Text(
          'Register',
        ),
      ),

      body:
          SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            24,
          ),
          child:
              Form(
            key:
                _formKey,
            child:
                Column(
              children: [
                const CorviaLogo(
                  size: 80,
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  'Corvia',
                  style:
                      TextStyle(
                    fontSize:
                        34,
                    fontWeight:
                        FontWeight.bold,
                    color:
                        CorviaColors.accent,
                  ),
                ),

                const SizedBox(
                  height:
                      6,
                ),

                Text(
                  'Create a New Account',
                  style:
                      TextStyle(
                    fontSize:
                        18,
                    color:
                        CorviaColors
                            .textSecondary,
                  ),
                ),

                const SizedBox(
                  height:
                      20,
                ),

                GestureDetector(
                  onTap:
                      _loading
                      ? null
                      : _pickImage,
                  child:
                      CircleAvatar(
                    radius:
                        50,
                    backgroundColor:
                        CorviaColors
                            .secondaryDark,
                    backgroundImage:
                        _selectedImage !=
                                null
                        ? FileImage(
                            _selectedImage!,
                          )
                        : null,
                    child:
                        _selectedImage ==
                                null
                        ? Icon(
                            Icons.camera_alt,
                            size:
                                40,
                            color:
                                CorviaColors
                                    .accentLight,
                          )
                        : null,
                  ),
                ),

                const SizedBox(
                  height:
                      20,
                ),

                _field(
                  'First Name',
                  _nameController,
                  fieldKey:
                      const Key(
                    'firstNameField',
                  ),
                  required:
                      true,
                ),

                _field(
                  'Surname',
                  _surnameController,
                  fieldKey:
                      const Key(
                    'surnameField',
                  ),
                  required:
                      true,
                ),

                _field(
                  'ID Number (13 digits)',
                  _idController,
                  fieldKey:
                      const Key(
                    'idField',
                  ),
                  keyboard:
                      TextInputType.number,
                  required:
                      true,
                  customValidator:
                      _validateIdNumber,
                ),

                _field(
                  'Email',
                  _emailController,
                  fieldKey:
                      const Key(
                    'emailField',
                  ),
                  keyboard:
                      TextInputType
                          .emailAddress,
                  required:
                      true,
                  customValidator:
                      _validateEmail,
                ),

                _field(
                  'Password',
                  _passwordController,
                  fieldKey:
                      const Key(
                    'passwordField',
                  ),
                  obscure:
                      true,
                  required:
                      true,
                  customValidator:
                      _validatePassword,
                ),

                _field(
                  'Confirm Password',
                  _confirmPasswordController,
                  fieldKey:
                      const Key(
                    'confirmPasswordField',
                  ),
                  obscure:
                      true,
                  required:
                      true,
                  customValidator:
                      _validateConfirmPassword,
                ),

                _field(
                  'Address',
                  _addressController,
                  fieldKey:
                      const Key(
                    'addressField',
                  ),
                ),

                _field(
                  'Phone Number',
                  _phoneController,
                  fieldKey:
                      const Key(
                    'phoneField',
                  ),
                  keyboard:
                      TextInputType.phone,
                  customValidator:
                      _validatePhone,
                ),

                _dobPickerField(),

                Row(
                  children: [
                    Align(
                      alignment:
                          AlignmentGeometry
                              .topLeft,
                      child:
                          Checkbox(
                        value:
                            termsAndConditionsChecked,
                        onChanged:
                            termsAndConditionsRead
                            ? (
                                bool? value,
                              ) {
                                setState(
                                  () {
                                    termsAndConditionsChecked =
                                        value ??
                                        false;
                                  },
                                );
                              }
                            : null,
                      ),
                    ),

                    Align(
                      alignment:
                          AlignmentGeometry
                              .bottomLeft,
                      child:
                          TextButton(
                        onPressed:
                            termsAndConditions,
                        child:
                            const Text(
                          'Terms and conditions',
                        ),
                      ),
                    ),
                  ],
                ),

                Row(
                  children: [
                    Align(
                      alignment:
                          AlignmentGeometry
                              .topLeft,
                      child:
                          Checkbox(
                        value:
                            policyChecked,
                        onChanged:
                            policyRead
                            ? (
                                bool? value,
                              ) {
                                setState(
                                  () {
                                    policyChecked =
                                        value ??
                                        false;
                                  },
                                );
                              }
                            : null,
                      ),
                    ),

                    Align(
                      alignment:
                          AlignmentGeometry
                              .bottomLeft,
                      child:
                          TextButton(
                        onPressed:
                            policy,
                        child:
                            const Text(
                          'User Policy',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height:
                      20,
                ),

                if (_loading)
                  CircularProgressIndicator(
                    color:
                        CorviaColors.accent,
                  )
                else
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        ElevatedButton(
                      key:
                          const Key(
                        'registerButton',
                      ),
                      onPressed:
                          _registerUser,
                      child:
                          const Text(
                        'Register',
                        style:
                            TextStyle(
                          fontSize:
                              18,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(
                  height:
                      12,
                ),

                TextButton(
                  onPressed:
                      _loading
                      ? null
                      : () {
                          Navigator.pop(
                            context,
                          );
                        },
                  child:
                      Text(
                    'Already have an account? Login',
                    style:
                        TextStyle(
                      color:
                          CorviaColors
                              .accentLight,
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
