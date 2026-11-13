import 'package:flutter/material.dart';
import '../../widgets/input_device_button.dart';
import '../../services/windows_input_devices.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../utils/phone_number_format.dart';
import 'package:flutter/services.dart';

/// A form for patients to enter their medical aid details via typed input or
/// voice dictation. Provider verification stays unavailable until a real
/// medical-aid integration is connected.
class MedicalAidInfoPage extends StatefulWidget {
  const MedicalAidInfoPage({super.key});

  @override
  State<MedicalAidInfoPage> createState() => _MedicalAidInfoPageState();
}

class _MedicalAidInfoPageState extends State<MedicalAidInfoPage>
    with SingleTickerProviderStateMixin {
  // Controllers
  final _provider = TextEditingController();
  final _memberNo = TextEditingController();
  final _plan = TextEditingController();
  final _dependent = TextEditingController();
  final _emergency = TextEditingController();
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  // Focus nodes
  final _nMemberNo = FocusNode();
  final _nPlan = FocusNode();
  final _nDependent = FocusNode();
  final _nEmergency = FocusNode();

  String _existingText = '';
  String _lastRecognized = '';

  // Provider list is loaded from Supabase (`medical_aid_providers` table).
  // Falls back to a small offline list if the request fails so the form
  // remains usable without network.
  static const List<String> _fallbackProviders = [
    'Discovery Health',
    'Bonitas',
    'Momentum',
    'Medshield',
    'Bestmed',
    'GEMS',
    'Polmed',
    _selfPayOption,
    'Other',
  ];

  /// Patients without cover pick this; it hides the membership fields.
  static const String _selfPayOption = 'Self Pay (no medical aid)';
  List<String> _providerOptions = _fallbackProviders;
  final Map<String, String> _providerIdsByName = {};
  String? _selectedProvider;

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  // Voice & TTS
  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _listening = false;
  String _microphoneId = '';
  TextEditingController? _active;

  @override
  void initState() {
    super.initState();

    // An unsaved patient must explicitly choose a provider. Prefilling
    // Discovery Health made an empty form look like verified cover.

    for (final n in [_nMemberNo, _nPlan, _nDependent, _nEmergency]) {
      n.addListener(_onFocusChange);
    }
    _tts.setSpeechRate(0.45);
    _bootstrap();

    // Animation controller for pulsing effect
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // Scale animation (size change)
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Opacity animation (fade in/out)
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      await _loadProviders();
      await _loadMedicalAidInfo();
    } catch (error) {
      debugPrint('Medical aid bootstrap failed: $error');

      if (mounted) {
        setState(() {
          _loadError = friendlyErrorMessage(
            error,
            whatFailed: "Couldn't load your medical aid information.",
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadProviders() async {
    try {
      final res = await SupabaseService.client
          .from('medical_aid_providers')
          .select('id, name')
          .eq('is_active', true)
          .order('display_order');

      final names = <String>[];
      final idsByName = <String, String>{};

      for (final raw in res as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final name = row['name']?.toString().trim() ?? '';
        final id = row['id']?.toString().trim() ?? '';

        if (name.isEmpty) {
          continue;
        }

        names.add(name);

        if (id.isNotEmpty) {
          idsByName[name] = id;
        }
      }

      if (!names.any(_isSelfPayName)) {
        names.add(_selfPayOption);
      }

      if (!names.contains('Other')) {
        names.add('Other');
      }

      if (!mounted) return;

      setState(() {
        if (names.isNotEmpty) {
          _providerOptions = names;
          _providerIdsByName
            ..clear()
            ..addAll(idsByName);

          if (_selectedProvider != null &&
              !_providerOptions.contains(_selectedProvider)) {
            _selectedProvider = null;
            _provider.clear();
          }
        }
      });
    } catch (error) {
      debugPrint('Medical aid provider load failed: $error');
    }
  }

  Future<void> _loadMedicalAidInfo() async {
    final patientId = await SupabaseService.currentPatientId();

    if (patientId == null) {
      throw StateError('No patient profile is linked to this account.');
    }

    final row = await SupabaseService.client
        .from('patients')
        .select(
          'medical_aid_provider, medical_aid_provider_id, '
          'medical_aid_member_number, medical_aid_plan, '
          'medical_aid_dependent_code, emergency_contact_phone',
        )
        .eq('id', patientId)
        .maybeSingle();

    if (row == null || !mounted) {
      return;
    }

    final storedProvider = row['medical_aid_provider']?.toString().trim() ?? '';
    final storedProviderId =
        row['medical_aid_provider_id']?.toString().trim() ?? '';

    setState(() {
      if (storedProvider.isNotEmpty) {
        if (!_providerOptions.contains(storedProvider)) {
          _providerOptions = [
            storedProvider,
            ..._providerOptions,
          ];
        }

        _selectedProvider = storedProvider;
        _provider.text = storedProvider;

        if (storedProviderId.isNotEmpty) {
          _providerIdsByName[storedProvider] = storedProviderId;
        }
      }

      _memberNo.text =
          row['medical_aid_member_number']?.toString().trim() ?? '';
      _plan.text = row['medical_aid_plan']?.toString().trim() ?? '';
      _dependent.text =
          row['medical_aid_dependent_code']?.toString().trim() ?? '';
      _emergency.text = formatPhoneNumber(
        row['emergency_contact_phone']?.toString().trim() ?? '',
      );
    });
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _onFocusChange() {
    _safeSetState(() {
      if (_nMemberNo.hasFocus) {
        _active = _memberNo;
      } else if (_nPlan.hasFocus) {
        _active = _plan;
      } else if (_nDependent.hasFocus) {
        _active = _dependent;
      } else if (_nEmergency.hasFocus) {
        _active = _emergency;
      } else {
        _active = null;
      }
    });
  }

  Future<void> _toggleListen() async {
    if (!_listening && _active == null) {
      _snack('Tap a field first, then use the mic.');
      return;
    }

    // Stop listening
    if (_listening) {
      await _stt.stop();
      _safeSetState(() {
        _listening = false;
        _controller.stop();
        _controller.reset();
      });
      return;
    }

    final ok = await _stt.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _safeSetState(() {
            _listening = false;
            _controller.stop();
            _controller.reset();
          });
        }
      },
      onError: (error) {
        _safeSetState(() {
          _listening = false;
          _controller.stop();
          _controller.reset();
        });
      },
    );

    if (!ok || _active == null) return;

    if (isWindowsDesktop) {
      try {
        await WindowsInputDevices.selectSpeechMicrophone(_microphoneId);
      } catch (_) {
        _snack('Microphone unavailable. Select Default or another microphone.');
        return;
      }
    }

    // Save whatever was already typed
    _existingText = _active!.text.trim();

    _safeSetState(() {
      _listening = true;
      _controller.repeat(reverse: true);
    });

    _lastRecognized = '';
    await _stt.listen(
      onResult: (result) {
        if (_active == null) return;

        final spoken = result.recognizedWords.trim();

        // Ignore duplicate callbacks
        if (spoken == _lastRecognized) return;

        _lastRecognized = spoken;

        _active!.text =
            _existingText.isEmpty ? spoken : '$_existingText $spoken';

        _active!.selection = TextSelection.fromPosition(
          TextPosition(offset: _active!.text.length),
        );

        if (result.finalResult) {
          _stt.stop();

          _safeSetState(() {
            _listening = false;
            _controller.stop();
            _controller.reset();
          });
        }
      },
      listenOptions: stt.SpeechListenOptions(
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 30),
        localeId: 'en_ZA',
      ),
    );
  }

  Future<void> _readBack() async {
    await _tts.stop();
    final providerText = _selectedProvider ?? _provider.text;
    final msg = [
      if (providerText.isNotEmpty) 'Provider: $providerText.',
      if (!_isSelfPay && _memberNo.text.isNotEmpty)
        'Member number: ${_memberNo.text}.',
      if (!_isSelfPay && _plan.text.isNotEmpty) 'Plan: ${_plan.text}.',
      if (!_isSelfPay && _dependent.text.isNotEmpty)
        'Dependent code: ${_dependent.text}.',
      if (_emergency.text.isNotEmpty) 'Emergency contact: ${_emergency.text}.',
    ].join(' ');
    await _tts.speak(msg.isEmpty ? 'Form is empty.' : msg);
  }

  static bool _isSelfPayName(String? name) {
    final value = (name ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return value.startsWith('selfpay') ||
        value.startsWith('private') ||
        value.startsWith('cash') ||
        value == 'none' ||
        value.startsWith('nomedicalaid');
  }

  bool get _isSelfPay => _isSelfPayName(_selectedProvider);

  String get _resolvedProviderName {
    if (_selectedProvider == 'Other') {
      return _provider.text.trim();
    }

    return _selectedProvider?.trim() ?? _provider.text.trim();
  }

  Future<void> _save() async {
    if (_saving || _loading) {
      return;
    }

    final providerName = _resolvedProviderName;
    final memberNumber = _memberNo.text.trim();

    if (providerName.isEmpty) {
      _snack('Select or enter your medical aid provider.');
      return;
    }

    if (memberNumber.isEmpty && !_isSelfPay) {
      _snack('Enter your medical aid member number.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final response = await SupabaseService.client.rpc(
        'corvia_patient_save_medical_aid',
        params: {
          'p_provider_name': providerName,
          'p_provider_id': _providerIdsByName[providerName],
          'p_member_number': _isSelfPay ? '' : memberNumber,
          'p_plan': _isSelfPay ? '' : _plan.text.trim(),
          'p_dependent_code': _isSelfPay ? '' : _dependent.text.trim(),
          'p_emergency_contact_phone': _emergency.text.trim(),
        },
      );

      if (response is! Map || response['saved'] != true) {
        throw StateError('The database did not confirm the save.');
      }

      if (!mounted) {
        return;
      }

      _snack('Medical aid information saved.', success: true);
      await _loadMedicalAidInfo();
    } catch (error) {
      debugPrint('Medical aid save failed: $error');

      if (mounted) {
        _snack(
          friendlyErrorMessage(
            error,
            whatFailed: "Couldn't save your medical aid information.",
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : null,
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_provider, _memberNo, _plan, _dependent, _emergency]) {
      c.dispose();
    }
    for (final n in [_nMemberNo, _nPlan, _nDependent, _nEmergency]) {
      n.dispose();
    }
    _stt.cancel();
    _tts.stop();
    _controller.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.cTextSecondary),
        filled: true,
        fillColor: context.cBgSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CorviaColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CorviaColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CorviaColors.accent, width: 1.6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final selfPay = _isSelfPay;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Medical Aid Info'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              if (_loading) ...[
                LinearProgressIndicator(color: CorviaColors.accent),
                const SizedBox(height: 16),
              ],
              _buildIntroCard(selfPay),
              const SizedBox(height: 16),
              if (_loadError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CorviaColors.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: CorviaColors.danger.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    _loadError!,
                    style: TextStyle(color: context.cTextPrimary),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _bootstrap,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
                const SizedBox(height: 16),
              ],
              _buildSection(
                title: 'Cover',
                icon: Icons.health_and_safety_outlined,
                children: [
                  // Keyed on the selection so the field follows data that
                  // loads after the first build; initialValue is read once.
                  DropdownButtonFormField<String>(
                    key: ValueKey('provider-${_selectedProvider ?? ''}'),
                    initialValue: _selectedProvider,
                    isExpanded: true,
                    hint: const Text('Select a medical aid provider'),
                    items: _providerOptions
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p,
                            child: Text(
                              p,
                              style: TextStyle(color: context.cTextPrimary),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            _safeSetState(() {
                              _selectedProvider = value;
                              _provider.text =
                                  value == 'Other' ? '' : value ?? '';
                            });
                          },
                    iconEnabledColor: context.cTextSecondary,
                    decoration: _dec('Provider').copyWith(
                      prefixIcon: const Icon(Icons.business_outlined),
                    ),
                  ),
                  if (_selectedProvider == 'Other') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _provider,
                      enabled: !_saving,
                      style: TextStyle(color: context.cTextPrimary),
                      decoration: _dec('Custom Provider Name'),
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                  if (!selfPay) ...[
                    const SizedBox(height: 12),
                    TextField(
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))
                      ],
                      controller: _memberNo,
                      focusNode: _nMemberNo,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: context.cTextPrimary),
                      decoration: _dec('Member Number').copyWith(
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _plan,
                            focusNode: _nPlan,
                            style: TextStyle(color: context.cTextPrimary),
                            decoration: _dec('Plan'),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _dependent,
                            focusNode: _nDependent,
                            style: TextStyle(color: context.cTextPrimary),
                            decoration: _dec('Dependent Code'),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'Emergency contact',
                icon: Icons.contact_phone_outlined,
                children: [
                  TextField(
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                      LengthLimitingTextInputFormatter(18),
                      const SouthAfricanPhoneInputFormatter(),
                    ],
                    controller: _emergency,
                    focusNode: _nEmergency,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: context.cTextPrimary),
                    decoration: _dec('Emergency Contact Number').copyWith(
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Opacity(
                            opacity: _opacityAnimation.value,
                            child: OutlinedButton.icon(
                              onPressed: _toggleListen,
                              icon:
                                  Icon(_listening ? Icons.mic_off : Icons.mic),
                              label: Text(
                                _listening
                                    ? 'Stop Listening'
                                    : 'Dictate to Focused Field',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _readBack,
                      icon: const Icon(Icons.volume_up),
                      label: const Text('Read Back'),
                    ),
                  ),
                  // Windows-only microphone picker; renders nothing elsewhere.
                  InputDeviceButton(
                    label: 'microphone',
                    selectedId: _microphoneId,
                    loadDevices: WindowsInputDevices.speechMicrophones,
                    onSelected: (id) async {
                      if (_listening) await _toggleListen();
                      await WindowsInputDevices.selectSpeechMicrophone(id);
                      if (mounted) setState(() => _microphoneId = id);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _saving || _loading || _loadError != null ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save Medical Aid'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard(bool selfPay) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CorviaColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CorviaColors.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: CorviaColors.accent.withValues(alpha: 0.15),
            child: Icon(
              selfPay ? Icons.payments_outlined : Icons.medical_services,
              color: context.cAccentReadable,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Medical Aid Details',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selfPay
                      ? 'You will pay for visits yourself. Reception will '
                          'confirm costs before treatment.'
                      : 'Hospitals use these details for billing and '
                          'pre-authorisation. Cover is not verified with '
                          'your provider in the app.',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: context.cAccentReadable),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
