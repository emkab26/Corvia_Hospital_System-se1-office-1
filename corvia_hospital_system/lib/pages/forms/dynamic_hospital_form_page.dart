import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/hospital_form_engine_service.dart';

import 'hospital_form_audit_page.dart';
import 'hospital_form_pdf_preview_page.dart';

class DynamicHospitalFormPage extends StatefulWidget {
  const DynamicHospitalFormPage({
    super.key,
    required this.instanceId,
  });

  final String instanceId;

  @override
  State<DynamicHospitalFormPage> createState() {
    return _DynamicHospitalFormPageState();
  }
}

class _DynamicHospitalFormPageState extends State<DynamicHospitalFormPage> {
  final HospitalFormEngineService _service = HospitalFormEngineService();

  final SupabaseClient _supabase = Supabase.instance.client;

  final ScrollController _scrollController = ScrollController();

  final Map<String, TextEditingController> _controllers = {};

  final Map<String, Object?> _answers = {};
  final Set<String> _dirtyFields = {};

  final Map<String, String> _fieldErrors = {};

  HospitalFormInstanceWorkspace? _workspace;

  _ControlledInstanceBindingStatus? _controlledBindingStatus;

  String? _controlledBindingError;

  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  bool _finalizing = false;
  bool _releasing = false;
  bool _capturingSignature = false;
  bool _refreshingBinding = false;

  String? _errorMessage;
  double _saveProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
  }

  @override
  void dispose() {
    _disposeControllers();
    _scrollController.dispose();
    super.dispose();
  }

  void _disposeControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }

    _controllers.clear();
  }

  Future<void> _loadWorkspace() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
        _controlledBindingError = null;
      });
    }

    try {
      final workspace = await _service.loadInstanceWorkspace(
        instanceId: widget.instanceId,
      );

      _ControlledInstanceBindingStatus? bindingStatus;
      String? bindingError;

      try {
        bindingStatus = await _fetchControlledBindingStatus();
      } catch (error) {
        bindingError = _friendlyControlledBindingError(error);
      }

      _disposeControllers();

      _answers
        ..clear()
        ..addAll(workspace.answers);

      _dirtyFields.clear();
      _fieldErrors.clear();

      _applySystemDefaults(workspace);

      for (final field in workspace.definition.fields) {
        if (_usesTextController(field)) {
          _controllers[field.fieldKey] = TextEditingController(
            text: _displayValue(
              _answers[field.fieldKey],
            ),
          );
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;
        _controlledBindingStatus = bindingStatus;
        _controlledBindingError = bindingError;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  Future<_ControlledInstanceBindingStatus?>
      _fetchControlledBindingStatus() async {
    final response = await _supabase.rpc(
      'corvia_controlled_instance_binding_status',
      params: {
        'p_instance_id': widget.instanceId,
      },
    );

    if (response == null) {
      return null;
    }

    if (response is Map<String, dynamic>) {
      return _ControlledInstanceBindingStatus.fromMap(
        response,
      );
    }

    if (response is Map) {
      return _ControlledInstanceBindingStatus.fromMap(
        Map<String, dynamic>.from(response),
      );
    }

    if (response is List && response.isNotEmpty && response.first is Map) {
      return _ControlledInstanceBindingStatus.fromMap(
        Map<String, dynamic>.from(
          response.first as Map,
        ),
      );
    }

    throw Exception(
      'Unexpected controlled-form binding response: '
      '${response.runtimeType}',
    );
  }

  Future<void> _refreshControlledBindingStatus({
    bool showMessage = false,
  }) async {
    if (_refreshingBinding) {
      return;
    }

    if (mounted) {
      setState(() {
        _refreshingBinding = true;
        _controlledBindingError = null;
      });
    }

    try {
      final status = await _fetchControlledBindingStatus();

      if (!mounted) {
        return;
      }

      setState(() {
        _controlledBindingStatus = status;
      });

      if (showMessage) {
        _showMessage(
          'Official master binding status refreshed.',
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _controlledBindingError = _friendlyControlledBindingError(
          error,
        );
      });

      if (showMessage) {
        _showMessage(
          _friendlyControlledBindingError(
            error,
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshingBinding = false;
        });
      }
    }
  }

  void _applySystemDefaults(
    HospitalFormInstanceWorkspace workspace,
  ) {
    for (final field in workspace.definition.fields) {
      if (_answers.containsKey(field.fieldKey) &&
          !_isEmptyValue(
            _answers[field.fieldKey],
          )) {
        continue;
      }

      if (field.fieldKey == 'privacy_notice_version') {
        _answers[field.fieldKey] = workspace.definition.version.versionLabel;

        _dirtyFields.add(field.fieldKey);
      }
    }
  }

  bool _usesTextController(
    HospitalFormFieldRecord field,
  ) {
    return !{
      'boolean',
      'single_choice',
      'multiple_choice',
      'signature',
      'information',
    }.contains(field.fieldType);
  }

  bool get _busy {
    return _loading ||
        _saving ||
        _submitting ||
        _finalizing ||
        _releasing ||
        _capturingSignature ||
        _refreshingBinding;
  }

  bool get _editable {
    return _workspace?.instance.isEditable ?? false;
  }

  void _setAnswer(
    HospitalFormFieldRecord field,
    Object? value, {
    bool markDirty = true,
  }) {
    setState(() {
      _answers[field.fieldKey] = value;

      if (markDirty) {
        _dirtyFields.add(field.fieldKey);
      }

      _fieldErrors.remove(field.fieldKey);
    });
  }

  Future<bool> _saveDraft({
    bool silent = false,
  }) async {
    final workspace = _workspace;

    if (workspace == null) {
      return false;
    }

    if (!_editable) {
      if (!silent) {
        _showMessage(
          'This form is no longer editable.',
          isError: true,
        );
      }

      return false;
    }

    if (_dirtyFields.isEmpty) {
      if (!silent) {
        _showMessage(
          'No unsaved changes.',
        );
      }

      return true;
    }

    final fieldsByKey = {
      for (final field in workspace.definition.fields) field.fieldKey: field,
    };

    final answersToSave = <String, Object?>{};

    for (final fieldKey in _dirtyFields.toList()) {
      final field = fieldsByKey[fieldKey];

      if (field == null || field.isInformation) {
        continue;
      }

      answersToSave[fieldKey] = _answers[fieldKey];
    }

    if (answersToSave.isEmpty) {
      setState(() {
        _dirtyFields.clear();
      });

      return true;
    }

    setState(() {
      _saving = true;
      _saveProgress = 0;
    });

    try {
      await _service.saveAnswers(
        instanceId: workspace.instance.id,
        answers: answersToSave,
        onProgress: (
          completed,
          total,
          fieldKey,
        ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _saveProgress = total == 0 ? 0 : completed / total;
          });
        },
      );

      if (!mounted) {
        return false;
      }

      setState(() {
        _dirtyFields.removeAll(
          answersToSave.keys,
        );

        _saveProgress = 1;
      });

      if (!silent) {
        _showMessage(
          'Draft saved successfully.',
        );
      }

      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      _showMessage(
        _friendlyError(error),
        isError: true,
      );

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveProgress = 0;
        });
      }
    }
  }

  Future<void> _submitForm() async {
    final workspace = _workspace;

    if (workspace == null || _submitting) {
      return;
    }

    final validationErrors = workspace.definition.validateAnswers(
      _answers,
    );

    if (validationErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(validationErrors);
      });

      _showMessage(
        '${validationErrors.length} required or invalid field(s) must be corrected.',
        isError: true,
      );

      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(
            milliseconds: 350,
          ),
          curve: Curves.easeOut,
        );
      }

      return;
    }

    final saved = await _saveDraft(
      silent: true,
    );

    if (!saved) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await _service.submitForm(
        instanceId: workspace.instance.id,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Form submitted successfully.',
      );

      await _loadWorkspace();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _friendlyError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _finalizeForm() async {
    final workspace = _workspace;

    if (workspace == null || _finalizing) {
      return;
    }

    try {
      final freshBinding = await _fetchControlledBindingStatus();

      if (mounted) {
        setState(() {
          _controlledBindingStatus = freshBinding;
          _controlledBindingError = null;
        });
      }

      if (freshBinding != null &&
          freshBinding.isControlledForm &&
          !freshBinding.isBound &&
          (!freshBinding.registryProductionApproved ||
              freshBinding.currentControlledVersionId == null)) {
        _showMessage(
          'This is a controlled official form and no '
          'production-approved official master is available. '
          'Finalization is blocked until the controlled master '
          'passes approval.',
          isError: true,
        );

        return;
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _controlledBindingError = _friendlyControlledBindingError(
            error,
          );
        });
      }

      /*
       * Do not bypass the database guard.
       *
       * If the client cannot load binding status, the database
       * finalization trigger still remains the final authority.
       */
    }

    final confirmed = await _confirmAction(
      title: 'Finalize hospital form?',
      message: 'Finalized forms cannot be edited directly. '
          'Amendments must be recorded as a new revision.\n\n'
          'For controlled official forms, Corvia will also verify '
          'the exact production-approved master binding before '
          'finalization.',
      confirmText: 'Finalize',
    );

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _finalizing = true;
    });

    try {
      await _service.finalizeForm(
        instanceId: workspace.instance.id,
        releaseToPatient: false,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Form finalized successfully.',
      );

      await _loadWorkspace();
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = _friendlyError(error);

      if (message.contains(
            'CONTROLLED_FORM_NOT_APPROVED',
          ) ||
          message.contains(
            'CONTROLLED_FORM_MASTER_INVALID',
          )) {
        _showMessage(
          'Controlled official form finalization was blocked. '
          'A valid production-approved official master must be '
          'available and bound first.',
          isError: true,
        );
      } else {
        _showMessage(
          message,
          isError: true,
        );
      }

      await _refreshControlledBindingStatus();
    } finally {
      if (mounted) {
        setState(() {
          _finalizing = false;
        });
      }
    }
  }

  Future<void> _releaseToPatient() async {
    final workspace = _workspace;

    if (workspace == null || _releasing) {
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Release form to patient?',
      message: 'The finalized document will become visible '
          'in the patient record.',
      confirmText: 'Release',
    );

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _releasing = true;
    });

    try {
      await _service.releaseFormToPatient(
        instanceId: workspace.instance.id,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Form released to the patient.',
      );

      await _loadWorkspace();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _friendlyError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _releasing = false;
        });
      }
    }
  }

  Future<void> _captureSignature(
    HospitalFormFieldRecord field,
  ) async {
    if (!_editable || _capturingSignature) {
      return;
    }

    final signature = await _showSignatureDialog(
      field,
    );

    if (signature == null || !mounted) {
      return;
    }

    setState(() {
      _capturingSignature = true;
    });

    try {
      final signatureId = await _service.signForm(
        instanceId: widget.instanceId,
        signerRole: signature.signerRole,
        signerName: signature.signerName,
        signatureMethod: 'typed_confirmation',
        signerIdentifier: signature.signerIdentifier,
        declarationText: signature.declarationText,
        witnessName: signature.witnessName,
        signatureEvidence: {
          'field_key': field.fieldKey,
          'typed_name': signature.signerName,
          'confirmed': signature.confirmed,
          'captured_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      final signatureValue = {
        'signature_id': signatureId,
        'field_key': field.fieldKey,
        'signer_role': signature.signerRole,
        'signer_name': signature.signerName,
        'signature_method': 'typed_confirmation',
        'signed_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _service.saveValue(
        instanceId: widget.instanceId,
        fieldKey: field.fieldKey,
        value: signatureValue,
        valueText: '${signature.signerName} — '
            '${_humanize(signature.signerRole)}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _answers[field.fieldKey] = signatureValue;

        _dirtyFields.remove(
          field.fieldKey,
        );

        _fieldErrors.remove(
          field.fieldKey,
        );
      });

      _showMessage(
        'Signature recorded successfully.',
      );

      await _loadWorkspace();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _friendlyError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _capturingSignature = false;
        });
      }
    }
  }

  Future<_SignatureDraft?> _showSignatureDialog(
    HospitalFormFieldRecord field,
  ) async {
    final nameController = TextEditingController();

    final identifierController = TextEditingController();

    final witnessController = TextEditingController();

    String signerRole = _defaultSignerRole(field);

    bool confirmed = false;

    final result = await showDialog<_SignatureDraft>(
      context: context,
      barrierDismissible: false,
      builder: (
        dialogContext,
      ) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            final canConfirm =
                nameController.text.trim().isNotEmpty && confirmed;

            return AlertDialog(
              title: Text(
                field.fieldLabel,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: signerRole,
                      decoration: const InputDecoration(
                        labelText: 'Signer role',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'patient',
                          child: Text(
                            'Patient',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'guardian',
                          child: Text(
                            'Guardian',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'caregiver',
                          child: Text(
                            'Caregiver',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'doctor',
                          child: Text(
                            'Doctor',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'specialist',
                          child: Text(
                            'Specialist',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'nurse',
                          child: Text(
                            'Nurse',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'pharmacist',
                          child: Text(
                            'Pharmacist',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'reception',
                          child: Text(
                            'Reception',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'witness',
                          child: Text(
                            'Witness',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text(
                            'Other',
                          ),
                        ),
                      ],
                      onChanged: (
                        value,
                      ) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(
                          () {
                            signerRole = value;
                          },
                        );
                      },
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) {
                        setDialogState(
                          () {},
                        );
                      },
                      decoration: const InputDecoration(
                        labelText: 'Full name of signer',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    TextField(
                      controller: identifierController,
                      decoration: const InputDecoration(
                        labelText: 'Identifier or staff number',
                        hintText: 'Optional',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    TextField(
                      controller: witnessController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Witness name',
                        hintText: 'Optional',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: confirmed,
                      title: const Text(
                        'I confirm that this typed signature '
                        'represents the named signer.',
                      ),
                      subtitle: const Text(
                        'The date, user and signature evidence '
                        'will be recorded in the audit trail.',
                      ),
                      onChanged: (
                        value,
                      ) {
                        setDialogState(
                          () {
                            confirmed = value ?? false;
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(
                      dialogContext,
                    ).pop();
                  },
                  child: const Text(
                    'Cancel',
                  ),
                ),
                FilledButton(
                  onPressed: canConfirm
                      ? () {
                          Navigator.of(
                            dialogContext,
                          ).pop(
                            _SignatureDraft(
                              signerRole: signerRole,
                              signerName: nameController.text.trim(),
                              signerIdentifier: _nullableText(
                                identifierController.text,
                              ),
                              witnessName: _nullableText(
                                witnessController.text,
                              ),
                              declarationText: 'I confirm that the information '
                                  'recorded in this form is correct '
                                  'to the best of my knowledge.',
                              confirmed: confirmed,
                            ),
                          );
                        }
                      : null,
                  child: const Text(
                    'Sign form',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    identifierController.dispose();
    witnessController.dispose();

    return result;
  }

  Future<void> _openPdfPreview() async {
    if (_busy) {
      return;
    }

    if (_workspace == null) {
      _showMessage(
        'The hospital form workspace is unavailable.',
        isError: true,
      );

      return;
    }

    if (_editable && _dirtyFields.isNotEmpty) {
      final saved = await _saveDraft(
        silent: true,
      );

      if (!saved || !mounted) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return HospitalFormPdfPreviewPage(
            instanceId: widget.instanceId,
            title: _workspace?.instance.templateName,
          );
        },
      ),
    );
  }

  Future<void> _openAuditHistory() async {
    if (_busy) {
      return;
    }

    final workspace = _workspace;

    if (workspace == null) {
      _showMessage(
        'The hospital form workspace is unavailable.',
        isError: true,
      );

      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return HospitalFormAuditPage(
            instanceId: widget.instanceId,
            title: '${workspace.instance.templateName} '
                'Audit History',
          );
        },
      ),
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: Text(
            title,
          ),
          content: Text(
            message,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  true,
                );
              },
              child: Text(
                confirmText,
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
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
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final workspace = _workspace;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          workspace?.instance.templateName ?? 'Hospital Form',
        ),
        actions: [
          IconButton(
            tooltip: 'PDF Preview',
            onPressed: _busy || workspace == null ? null : _openPdfPreview,
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Audit History',
            onPressed: _busy || workspace == null ? null : _openAuditHistory,
            icon: const Icon(
              Icons.history_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Refresh master binding',
            onPressed: _busy || workspace == null
                ? null
                : () {
                    _refreshControlledBindingStatus(
                      showMessage: true,
                    );
                  },
            icon: const Icon(
              Icons.verified_user_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _loadWorkspace,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: workspace == null || _loading
          ? null
          : _buildBottomActions(
              workspace,
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return _RendererErrorState(
        message: _errorMessage!,
        onRetry: _loadWorkspace,
      );
    }

    final workspace = _workspace;

    if (workspace == null) {
      return const Center(
        child: Text(
          'Hospital form workspace is unavailable.',
        ),
      );
    }

    final definition = workspace.definition;

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildHeader(
            workspace,
          ),
        ),
        if (_fieldErrors.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildValidationSummary(),
          ),
        ...definition.sectionKeys.map(
          (
            sectionKey,
          ) {
            return SliverToBoxAdapter(
              child: _buildSection(
                definition,
                sectionKey,
              ),
            );
          },
        ),
        const SliverToBoxAdapter(
          child: SizedBox(
            height: 120,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    HospitalFormInstanceWorkspace workspace,
  ) {
    final instance = workspace.instance;

    final template = workspace.definition.template;

    final version = workspace.definition.version;

    final statusColor = _statusColor(
      context,
      instance.status,
    );

    final requiredFields = workspace.definition.fields.where(
      (
        field,
      ) {
        return field.isRequired &&
            !field.isInformation &&
            field.shouldShow(
              _answers,
            );
      },
    ).toList();

    final completedRequired = requiredFields.where(
      (
        field,
      ) {
        return !_isEmptyValue(
          _answers[field.fieldKey],
        );
      },
    ).length;

    final completion = requiredFields.isEmpty
        ? 1.0
        : completedRequired / requiredFields.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        6,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(
            16,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.name,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  _FormStatusPill(
                    text: _humanize(
                      instance.status,
                    ),
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                instance.documentNumber,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(
                height: 4,
              ),
              Text(
                '${version.versionLabel} • '
                '${version.languageCode}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall,
              ),
              if (template.description != null &&
                  template.description!.isNotEmpty) ...[
                const SizedBox(
                  height: 12,
                ),
                Text(
                  template.description!,
                ),
              ],
              if (version.isDemoOnly && !version.productionApproved) ...[
                const SizedBox(
                  height: 12,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(
                    12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child: Text(
                          'Corvia demo template. Formal hospital, '
                          'clinical and legal approval is required '
                          'before production use.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_controlledBindingStatus != null ||
                  _controlledBindingError != null) ...[
                const SizedBox(
                  height: 12,
                ),
                _buildControlledMasterEvidence(),
              ],
              const SizedBox(
                height: 16,
              ),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: completion,
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Text(
                    '$completedRequired/'
                    '${requiredFields.length}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(
                height: 7,
              ),
              Text(
                'Required fields completed',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall,
              ),
              if (_dirtyFields.isNotEmpty) ...[
                const SizedBox(
                  height: 12,
                ),
                Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary,
                    ),
                    const SizedBox(
                      width: 6,
                    ),
                    Text(
                      '${_dirtyFields.length} '
                      'unsaved change(s)',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ],
              if (instance.isLegalHold) ...[
                const SizedBox(
                  height: 12,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(
                    12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.gavel_outlined,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child: Text(
                          'This document is under legal hold.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(
                height: 14,
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openPdfPreview,
                    icon: const Icon(
                      Icons.picture_as_pdf_outlined,
                    ),
                    label: const Text(
                      'PDF Preview',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openAuditHistory,
                    icon: const Icon(
                      Icons.history_outlined,
                    ),
                    label: const Text(
                      'Audit History',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            _refreshControlledBindingStatus(
                              showMessage: true,
                            );
                          },
                    icon: const Icon(
                      Icons.verified_user_outlined,
                    ),
                    label: const Text(
                      'Verify Official Master',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlledMasterEvidence() {
    final binding = _controlledBindingStatus;

    if (binding == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          12,
        ),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: Theme.of(
                context,
              ).colorScheme.tertiary,
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Official master verification unavailable',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    _controlledBindingError ??
                        'Corvia could not load the controlled-form '
                            'binding status. Database finalization '
                            'safeguards remain active.',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (!binding.isControlledForm) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          12,
        ),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
          borderRadius: BorderRadius.circular(
            12,
          ),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.description_outlined,
            ),
            SizedBox(
              width: 10,
            ),
            Expanded(
              child: Text(
                'Standard Corvia hospital form. '
                'No controlled official master binding is required.',
              ),
            ),
          ],
        ),
      );
    }

    if (!binding.isBound) {
      final approvedMasterAvailable = binding.registryProductionApproved &&
          binding.currentControlledVersionId != null;

      final color = approvedMasterAvailable
          ? Colors.orange.shade800
          : Theme.of(context).colorScheme.error;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          14,
        ),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: 0.09,
          ),
          borderRadius: BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: color.withValues(
              alpha: 0.35,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.policy_outlined,
                  color: color,
                ),
                const SizedBox(
                  width: 9,
                ),
                Expanded(
                  child: Text(
                    'CONTROLLED FORM — OFFICIAL MASTER NOT BOUND',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              binding.officialFormName ??
                  binding.formCode ??
                  'Controlled Official Form',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(
              height: 5,
            ),
            Text(
              approvedMasterAvailable
                  ? 'A production-approved official master is '
                      'available. Corvia will verify and bind the '
                      'exact master before finalization.'
                  : 'No production-approved official master is '
                      'currently available. Finalization is blocked '
                      'until the official master passes approval.',
            ),
            if (binding.registryProductionStatus != null) ...[
              const SizedBox(
                height: 7,
              ),
              Text(
                'Registry status: '
                '${_humanize(binding.registryProductionStatus!)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    }

    final color = Colors.green.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          12,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user,
                color: color,
              ),
              const SizedBox(
                width: 9,
              ),
              Expanded(
                child: Text(
                  'OFFICIAL MASTER BOUND',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _FormStatusPill(
                text: 'Verified',
                color: color,
              ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            binding.officialFormName ??
                binding.formCode ??
                'Controlled Official Form',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            'Master Version '
            '${binding.versionNumber ?? '—'}'
            '${binding.versionLabel == null ? '' : ' • ${binding.versionLabel}'}',
          ),
          if (binding.officialFormNumber != null) ...[
            const SizedBox(
              height: 4,
            ),
            Text(
              'Official Form Number: '
              '${binding.officialFormNumber}',
            ),
          ],
          if (binding.officialVersionReference != null) ...[
            const SizedBox(
              height: 4,
            ),
            Text(
              'Official Version: '
              '${binding.officialVersionReference}',
            ),
          ],
          if (binding.officialRevisionReference != null) ...[
            const SizedBox(
              height: 4,
            ),
            Text(
              'Official Revision: '
              '${binding.officialRevisionReference}',
            ),
          ],
          const SizedBox(
            height: 8,
          ),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (binding.effectiveOn != null)
                Text(
                  'Effective: '
                  '${_formatDateForDisplay(binding.effectiveOn!)}',
                ),
              if (binding.approvedAt != null)
                Text(
                  'Approved: '
                  '${_formatDateTimeDisplay(binding.approvedAt!)}',
                ),
              if (binding.boundAt != null)
                Text(
                  'Bound: '
                  '${_formatDateTimeDisplay(binding.boundAt!)}',
                ),
            ],
          ),
          if (binding.sha256 != null && binding.sha256!.trim().isNotEmpty) ...[
            const SizedBox(
              height: 10,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    'SHA-256: ${binding.sha256}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy SHA-256',
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: binding.sha256!,
                      ),
                    );

                    if (mounted) {
                      _showMessage(
                        'SHA-256 copied.',
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.copy,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValidationSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        10,
        16,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          14,
        ),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(
            14,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(
                context,
              ).colorScheme.onErrorContainer,
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Text(
                '${_fieldErrors.length} field(s) require '
                'attention before this form can be submitted.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    HospitalFormTemplateDefinition definition,
    String sectionKey,
  ) {
    final fields = definition
        .fieldsForSection(
          sectionKey,
        )
        .where(
          (
            field,
          ) =>
              field.shouldShow(
            _answers,
          ),
        )
        .toList(
          growable: false,
        );

    if (fields.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        14,
        16,
        0,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(
            16,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _sectionIcon(
                      sectionKey,
                    ),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(
                    width: 9,
                  ),
                  Expanded(
                    child: Text(
                      definition.sectionTitle(
                        sectionKey,
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 16,
              ),
              ...fields.map(
                (
                  field,
                ) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: 16,
                    ),
                    child: _buildField(
                      field,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    HospitalFormFieldRecord field,
  ) {
    switch (field.fieldType) {
      case 'information':
        return _buildInformationField(
          field,
        );

      case 'boolean':
        return _buildBooleanField(
          field,
        );

      case 'single_choice':
        return _buildSingleChoiceField(
          field,
        );

      case 'multiple_choice':
        return _buildMultipleChoiceField(
          field,
        );

      case 'date':
        return _buildDateField(
          field,
        );

      case 'time':
        return _buildTimeField(
          field,
        );

      case 'datetime':
        return _buildDateTimeField(
          field,
        );

      case 'signature':
        return _buildSignatureField(
          field,
        );

      case 'integer':
        return _buildNumericField(
          field,
          decimal: false,
        );

      case 'decimal':
        return _buildNumericField(
          field,
          decimal: true,
        );

      case 'long_text':
        return _buildTextField(
          field,
          maxLines: 5,
        );

      case 'calculated':
        return _buildTextField(
          field,
          maxLines: 2,
          forceReadOnly: true,
        );

      default:
        return _buildTextField(
          field,
          maxLines: 1,
        );
    }
  }

  Widget _buildInformationField(
    HospitalFormFieldRecord field,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(
          12,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.fieldLabel,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (field.helpText != null && field.helpText!.isNotEmpty) ...[
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    field.helpText!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBooleanField(
    HospitalFormFieldRecord field,
  ) {
    final current = _answers[field.fieldKey];

    final value = current is bool ? current : false;

    return InputDecorator(
      decoration: _decoration(
        field,
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          value ? 'Yes' : 'No',
        ),
        value: value,
        onChanged: !_editable || field.isReadOnly
            ? null
            : (
                newValue,
              ) {
                _setAnswer(
                  field,
                  newValue,
                );
              },
      ),
    );
  }

  Widget _buildSingleChoiceField(
    HospitalFormFieldRecord field,
  ) {
    final options = field.stringOptions;

    final current = _answers[field.fieldKey]?.toString();

    final selectedValue = options.contains(current) ? current : null;

    return DropdownButtonFormField<String>(
      key: ValueKey(
        '${field.fieldKey}-$selectedValue',
      ),
      initialValue: selectedValue,
      isExpanded: true,
      decoration: _decoration(
        field,
      ),
      items: options.map(
        (
          option,
        ) {
          return DropdownMenuItem<String>(
            value: option,
            child: Text(
              _humanize(
                option,
              ),
            ),
          );
        },
      ).toList(),
      onChanged: !_editable || field.isReadOnly
          ? null
          : (
              value,
            ) {
              _setAnswer(
                field,
                value,
              );
            },
    );
  }

  Widget _buildMultipleChoiceField(
    HospitalFormFieldRecord field,
  ) {
    final options = field.stringOptions;

    final existing = _answers[field.fieldKey];

    final selected = existing is List
        ? existing
            .map(
              (
                value,
              ) =>
                  value.toString(),
            )
            .toSet()
        : <String>{};

    return InputDecorator(
      decoration: _decoration(
        field,
      ),
      child: options.isEmpty
          ? const Text(
              'No options configured.',
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map(
                (
                  option,
                ) {
                  return FilterChip(
                    label: Text(
                      _humanize(
                        option,
                      ),
                    ),
                    selected: selected.contains(
                      option,
                    ),
                    onSelected: !_editable || field.isReadOnly
                        ? null
                        : (
                            isSelected,
                          ) {
                            final updated = Set<String>.from(
                              selected,
                            );

                            if (isSelected) {
                              updated.add(
                                option,
                              );
                            } else {
                              updated.remove(
                                option,
                              );
                            }

                            _setAnswer(
                              field,
                              updated.toList(),
                            );
                          },
                  );
                },
              ).toList(),
            ),
    );
  }

  Widget _buildTextField(
    HospitalFormFieldRecord field, {
    required int maxLines,
    bool forceReadOnly = false,
  }) {
    final controller = _controllerFor(
      field,
    );

    final readOnly = forceReadOnly || field.isReadOnly || !_editable;

    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      minLines: maxLines > 1 ? 3 : 1,
      textCapitalization: TextCapitalization.sentences,
      onChanged: readOnly
          ? null
          : (
              value,
            ) {
              _setAnswer(
                field,
                value.trim().isEmpty ? null : value,
              );
            },
      decoration: _decoration(
        field,
      ),
    );
  }

  Widget _buildNumericField(
    HospitalFormFieldRecord field, {
    required bool decimal,
  }) {
    final controller = _controllerFor(
      field,
    );

    final readOnly = field.isReadOnly || !_editable;

    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
        signed: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal
              ? RegExp(
                  r'^-?\d*\.?\d*$',
                )
              : RegExp(
                  r'^-?\d*$',
                ),
        ),
      ],
      onChanged: readOnly
          ? null
          : (
              value,
            ) {
              final clean = value.trim();

              Object? parsedValue;

              if (clean.isEmpty) {
                parsedValue = null;
              } else if (decimal) {
                parsedValue = double.tryParse(
                      clean,
                    ) ??
                    clean;
              } else {
                parsedValue = int.tryParse(
                      clean,
                    ) ??
                    clean;
              }

              _setAnswer(
                field,
                parsedValue,
              );
            },
      decoration: _decoration(
        field,
      ),
    );
  }

  Widget _buildDateField(
    HospitalFormFieldRecord field,
  ) {
    final controller = _controllerFor(
      field,
    );

    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: !_editable || field.isReadOnly
          ? null
          : () async {
              final current = _parseDate(
                _answers[field.fieldKey],
              );

              final selected = await showDatePicker(
                context: context,
                initialDate: current ?? DateTime.now(),
                firstDate: DateTime(
                  1900,
                ),
                lastDate: DateTime(
                  2200,
                ),
              );

              if (selected == null || !mounted) {
                return;
              }

              final value = _formatDateValue(
                selected,
              );

              controller.text = value;

              _setAnswer(
                field,
                value,
              );
            },
      decoration: _decoration(
        field,
      ).copyWith(
        suffixIcon: const Icon(
          Icons.calendar_today,
        ),
      ),
    );
  }

  Widget _buildTimeField(
    HospitalFormFieldRecord field,
  ) {
    final controller = _controllerFor(
      field,
    );

    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: !_editable || field.isReadOnly
          ? null
          : () async {
              final selected = await showTimePicker(
                context: context,
                initialTime: _parseTime(
                      _answers[field.fieldKey],
                    ) ??
                    TimeOfDay.now(),
              );

              if (selected == null || !mounted) {
                return;
              }

              final value = '${selected.hour.toString().padLeft(2, '0')}:'
                  '${selected.minute.toString().padLeft(2, '0')}';

              controller.text = value;

              _setAnswer(
                field,
                value,
              );
            },
      decoration: _decoration(
        field,
      ).copyWith(
        suffixIcon: const Icon(
          Icons.access_time,
        ),
      ),
    );
  }

  Widget _buildDateTimeField(
    HospitalFormFieldRecord field,
  ) {
    final controller = _controllerFor(
      field,
    );

    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: !_editable || field.isReadOnly
          ? null
          : () async {
              final current = _parseDate(
                    _answers[field.fieldKey],
                  ) ??
                  DateTime.now();

              final selectedDate = await showDatePicker(
                context: context,
                initialDate: current,
                firstDate: DateTime(
                  1900,
                ),
                lastDate: DateTime(
                  2200,
                ),
              );

              if (selectedDate == null || !mounted) {
                return;
              }

              final selectedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(
                  current,
                ),
              );

              if (selectedTime == null || !mounted) {
                return;
              }

              final selectedDateTime = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                selectedTime.hour,
                selectedTime.minute,
              );

              final value = selectedDateTime.toIso8601String();

              controller.text = _formatDateTimeDisplay(
                selectedDateTime,
              );

              _setAnswer(
                field,
                value,
              );
            },
      decoration: _decoration(
        field,
      ).copyWith(
        suffixIcon: const Icon(
          Icons.event_available,
        ),
      ),
    );
  }

  Widget _buildSignatureField(
    HospitalFormFieldRecord field,
  ) {
    final value = _answers[field.fieldKey];

    final signed = value is Map && value['signature_id'] != null;

    final signerName =
        signed ? value['signer_name']?.toString() ?? 'Signed' : null;

    final error = _fieldErrors[field.fieldKey];

    return Container(
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: error != null
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(
          12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${field.fieldLabel}'
                  '${field.isRequired ? ' *' : ''}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Icon(
                signed ? Icons.verified : Icons.draw_outlined,
                color: signed
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          if (field.helpText != null && field.helpText!.isNotEmpty) ...[
            const SizedBox(
              height: 6,
            ),
            Text(
              field.helpText!,
            ),
          ],
          const SizedBox(
            height: 12,
          ),
          if (signed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(
                12,
              ),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(
                  24,
                ),
                borderRadius: BorderRadius.circular(
                  10,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(
                    width: 9,
                  ),
                  Expanded(
                    child: Text(
                      'Signed by $signerName',
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: !_editable || field.isReadOnly || _capturingSignature
                    ? null
                    : () {
                        _captureSignature(
                          field,
                        );
                      },
                icon: const Icon(
                  Icons.draw_outlined,
                ),
                label: Text(
                  _capturingSignature
                      ? 'Recording signature...'
                      : 'Add signature',
                ),
              ),
            ),
          if (error != null) ...[
            const SizedBox(
              height: 7,
            ),
            Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  TextEditingController _controllerFor(
    HospitalFormFieldRecord field,
  ) {
    return _controllers.putIfAbsent(
      field.fieldKey,
      () {
        return TextEditingController(
          text: _displayValue(
            _answers[field.fieldKey],
          ),
        );
      },
    );
  }

  InputDecoration _decoration(
    HospitalFormFieldRecord field,
  ) {
    return InputDecoration(
      labelText: '${field.fieldLabel}'
          '${field.isRequired ? ' *' : ''}',
      hintText: field.placeholder,
      helperText: field.helpText,
      errorText: _fieldErrors[field.fieldKey],
      border: const OutlineInputBorder(),
      alignLabelWithHint: field.fieldType == 'long_text',
    );
  }

  Widget _buildBottomActions(
    HospitalFormInstanceWorkspace workspace,
  ) {
    final instance = workspace.instance;

    final template = workspace.definition.template;

    Widget child;

    if (instance.isEditable) {
      child = Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      _saveDraft();
                    },
              icon: const Icon(
                Icons.save_outlined,
              ),
              label: Text(
                _saving ? 'Saving...' : 'Save draft',
              ),
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _submitForm,
              icon: const Icon(
                Icons.send_outlined,
              ),
              label: Text(
                _submitting ? 'Submitting...' : 'Submit',
              ),
            ),
          ),
        ],
      );
    } else if ({
      'submitted',
      'under_review',
      'approved',
    }.contains(
      instance.status,
    )) {
      child = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : _finalizeForm,
          icon: const Icon(
            Icons.verified_outlined,
          ),
          label: Text(
            _finalizing ? 'Finalizing...' : 'Finalize form',
          ),
        ),
      );
    } else if (instance.isFinalized &&
        template.mayReleaseToPatient &&
        !instance.isReleasedToPatient) {
      child = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : _releaseToPatient,
          icon: const Icon(
            Icons.person_add_alt,
          ),
          label: Text(
            _releasing ? 'Releasing...' : 'Release to patient',
          ),
        ),
      );
    } else {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            instance.isReleasedToPatient
                ? Icons.verified_user_outlined
                : Icons.lock_outline,
          ),
          const SizedBox(
            width: 8,
          ),
          Text(
            instance.isReleasedToPatient
                ? 'Finalized and released'
                : _humanize(
                    instance.status,
                  ),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      );
    }

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(
            14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving) ...[
                LinearProgressIndicator(
                  value: _saveProgress == 0 ? null : _saveProgress,
                ),
                const SizedBox(
                  height: 10,
                ),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlledInstanceBindingStatus {
  const _ControlledInstanceBindingStatus({
    required this.instanceId,
    required this.isControlledForm,
    required this.bindingRequired,
    required this.isBound,
    required this.registryProductionApproved,
    this.hospitalId,
    this.templateId,
    this.bindingId,
    this.registryId,
    this.formCode,
    this.officialFormName,
    this.registryProductionStatus,
    this.currentControlledVersionId,
    this.controlledVersionId,
    this.versionNumber,
    this.versionLabel,
    this.officialFormNumber,
    this.officialVersionReference,
    this.officialRevisionReference,
    this.effectiveOn,
    this.retiredOn,
    this.approvedAt,
    this.boundAt,
    this.boundBy,
    this.approvalStatus,
    this.productionApproved,
    this.sourceDocumentName,
    this.storageBucket,
    this.storagePath,
    this.sha256,
    this.bindingMetadata = const {},
  });

  final String instanceId;
  final String? hospitalId;
  final String? templateId;

  final bool isControlledForm;
  final bool bindingRequired;
  final bool isBound;

  final String? bindingId;
  final DateTime? boundAt;
  final String? boundBy;

  final Map<String, dynamic> bindingMetadata;

  final String? registryId;
  final String? formCode;
  final String? officialFormName;

  final String? registryProductionStatus;
  final bool registryProductionApproved;

  final String? currentControlledVersionId;

  final String? controlledVersionId;

  final int? versionNumber;
  final String? versionLabel;

  final String? officialFormNumber;
  final String? officialVersionReference;
  final String? officialRevisionReference;

  final DateTime? effectiveOn;
  final DateTime? retiredOn;
  final DateTime? approvedAt;

  final String? approvalStatus;
  final bool? productionApproved;

  final String? sourceDocumentName;
  final String? storageBucket;
  final String? storagePath;
  final String? sha256;

  factory _ControlledInstanceBindingStatus.fromMap(
    Map<String, dynamic> map,
  ) {
    return _ControlledInstanceBindingStatus(
      instanceId: map['instance_id']?.toString() ?? '',
      hospitalId: _cleanString(
        map['hospital_id'],
      ),
      templateId: _cleanString(
        map['template_id'],
      ),
      isControlledForm: _boolValue(
        map['is_controlled_form'],
      ),
      bindingRequired: _boolValue(
        map['binding_required'],
      ),
      isBound: _boolValue(
        map['is_bound'],
      ),
      bindingId: _cleanString(
        map['binding_id'],
      ),
      boundAt: _dateValue(
        map['bound_at'],
      ),
      boundBy: _cleanString(
        map['bound_by'],
      ),
      bindingMetadata: map['binding_metadata'] is Map
          ? Map<String, dynamic>.from(
              map['binding_metadata'] as Map,
            )
          : const {},
      registryId: _cleanString(
        map['registry_id'],
      ),
      formCode: _cleanString(
        map['form_code'],
      ),
      officialFormName: _cleanString(
        map['official_form_name'],
      ),
      registryProductionStatus: _cleanString(
        map['registry_production_status'],
      ),
      registryProductionApproved: _boolValue(
        map['registry_production_approved'],
      ),
      currentControlledVersionId: _cleanString(
        map['current_controlled_version_id'],
      ),
      controlledVersionId: _cleanString(
        map['controlled_version_id'],
      ),
      versionNumber: _intValue(
        map['version_number'],
      ),
      versionLabel: _cleanString(
        map['version_label'],
      ),
      officialFormNumber: _cleanString(
        map['official_form_number'],
      ),
      officialVersionReference: _cleanString(
        map['official_version_reference'],
      ),
      officialRevisionReference: _cleanString(
        map['official_revision_reference'],
      ),
      effectiveOn: _dateValue(
        map['effective_on'],
      ),
      retiredOn: _dateValue(
        map['retired_on'],
      ),
      approvedAt: _dateValue(
        map['approved_at'],
      ),
      approvalStatus: _cleanString(
        map['approval_status'],
      ),
      productionApproved: map.containsKey(
        'production_approved',
      )
          ? _boolValue(
              map['production_approved'],
            )
          : null,
      sourceDocumentName: _cleanString(
        map['source_document_name'],
      ),
      storageBucket: _cleanString(
        map['storage_bucket'],
      ),
      storagePath: _cleanString(
        map['storage_path'],
      ),
      sha256: _cleanString(
        map['sha256'],
      ),
    );
  }

  static bool _boolValue(
    dynamic value,
  ) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase();

    return text == 'true' || text == '1' || text == 'yes';
  }

  static int? _intValue(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(
      value.toString(),
    );
  }

  static DateTime? _dateValue(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toLocal();
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }

  static String? _cleanString(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }
}

class _SignatureDraft {
  const _SignatureDraft({
    required this.signerRole,
    required this.signerName,
    required this.declarationText,
    required this.confirmed,
    this.signerIdentifier,
    this.witnessName,
  });

  final String signerRole;
  final String signerName;

  final String? signerIdentifier;
  final String? witnessName;

  final String declarationText;
  final bool confirmed;
}

class _FormStatusPill extends StatelessWidget {
  const _FormStatusPill({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(
          26,
        ),
        borderRadius: BorderRadius.circular(
          999,
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _RendererErrorState extends StatelessWidget {
  const _RendererErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 58,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'Unable to open form',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 18,
            ),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try again',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _sectionIcon(
  String sectionKey,
) {
  switch (sectionKey) {
    case 'admission':
      return Icons.login;

    case 'notice':
    case 'acknowledgement':
      return Icons.privacy_tip_outlined;

    case 'arrival':
    case 'triage':
      return Icons.emergency_outlined;

    case 'vitals':
    case 'observation':
      return Icons.monitor_heart_outlined;

    case 'clinical':
    case 'assessment':
    case 'clinical_history':
    case 'history':
      return Icons.medical_information_outlined;

    case 'risk':
    case 'risk_screening':
    case 'safety':
    case 'screening':
      return Icons.health_and_safety_outlined;

    case 'procedure':
      return Icons.medical_services_outlined;

    case 'medication':
    case 'prescription':
    case 'administration':
    case 'dispensing':
      return Icons.medication_outlined;

    case 'tests':
    case 'specimen':
    case 'collection':
    case 'investigations':
      return Icons.science_outlined;

    case 'contrast':
    case 'request':
      return Icons.image_outlined;

    case 'transport':
    case 'transfer':
    case 'destination':
      return Icons.transfer_within_a_station;

    case 'discharge':
    case 'instructions':
    case 'follow_up':
      return Icons.logout;

    case 'consent':
    case 'signature':
    case 'signatures':
      return Icons.draw_outlined;

    default:
      return Icons.description_outlined;
  }
}

Color _statusColor(
  BuildContext context,
  String status,
) {
  final scheme = Theme.of(context).colorScheme;

  switch (status) {
    case 'draft':
      return scheme.secondary;

    case 'in_progress':
      return scheme.primary;

    case 'submitted':
    case 'under_review':
      return scheme.tertiary;

    case 'approved':
    case 'finalized':
      return Colors.green.shade700;

    case 'rejected':
    case 'void':
      return scheme.error;

    case 'amended':
      return Colors.orange.shade800;

    default:
      return scheme.primary;
  }
}

String _defaultSignerRole(
  HospitalFormFieldRecord field,
) {
  final text = '${field.fieldKey} ${field.fieldLabel}'.toLowerCase();

  if (text.contains(
    'guardian',
  )) {
    return 'guardian';
  }

  if (text.contains(
        'patient',
      ) ||
      text.contains(
        'collector',
      )) {
    return 'patient';
  }

  if (text.contains(
    'nurse',
  )) {
    return 'nurse';
  }

  if (text.contains(
    'pharmacist',
  )) {
    return 'pharmacist';
  }

  if (text.contains(
    'specialist',
  )) {
    return 'specialist';
  }

  if (text.contains(
        'doctor',
      ) ||
      text.contains(
        'clinician',
      ) ||
      text.contains(
        'surgeon',
      )) {
    return 'doctor';
  }

  if (text.contains(
    'witness',
  )) {
    return 'witness';
  }

  return field.isPatientVisible ? 'patient' : 'doctor';
}

DateTime? _parseDate(
  Object? value,
) {
  if (value == null) {
    return null;
  }

  if (value is DateTime) {
    return value;
  }

  return DateTime.tryParse(
    value.toString(),
  );
}

TimeOfDay? _parseTime(
  Object? value,
) {
  if (value == null) {
    return null;
  }

  final parts = value.toString().split(
        ':',
      );

  if (parts.length < 2) {
    return null;
  }

  final hour = int.tryParse(
    parts[0],
  );

  final minute = int.tryParse(
    parts[1],
  );

  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }

  return TimeOfDay(
    hour: hour,
    minute: minute,
  );
}

String _formatDateValue(
  DateTime value,
) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _formatDateForDisplay(
  DateTime value,
) {
  final local = value.toLocal();

  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}

String _formatDateTimeDisplay(
  DateTime value,
) {
  final local = value.toLocal();

  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _displayValue(
  Object? value,
) {
  if (value == null) {
    return '';
  }

  if (value is DateTime) {
    return _formatDateTimeDisplay(
      value,
    );
  }

  if (value is Map) {
    return value['signer_name']?.toString() ?? value.toString();
  }

  if (value is List) {
    return value.join(
      ', ',
    );
  }

  final date = DateTime.tryParse(
    value.toString(),
  );

  if (date != null &&
      value.toString().contains(
            'T',
          )) {
    return _formatDateTimeDisplay(
      date,
    );
  }

  return value.toString();
}

String? _nullableText(
  String? value,
) {
  if (value == null) {
    return null;
  }

  final clean = value.trim();

  return clean.isEmpty ? null : clean;
}

bool _isEmptyValue(
  Object? value,
) {
  if (value == null) {
    return true;
  }

  if (value is String) {
    return value.trim().isEmpty;
  }

  if (value is Iterable) {
    return value.isEmpty;
  }

  if (value is Map) {
    return value.isEmpty;
  }

  return false;
}

String _humanize(
  String value,
) {
  final clean = value
      .trim()
      .replaceAll(
        RegExp(
          r'[_-]+',
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\s+',
        ),
        ' ',
      );

  if (clean.isEmpty) {
    return '';
  }

  return clean
      .split(
    ' ',
  )
      .map(
    (
      word,
    ) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    },
  ).join(
    ' ',
  );
}

String _friendlyError(
  Object error,
) {
  if (error is HospitalFormEngineException) {
    return error.message;
  }

  final message = error.toString().trim();

  if (message.isEmpty) {
    return 'An unknown hospital form error occurred.';
  }

  return message;
}

String _friendlyControlledBindingError(
  Object error,
) {
  if (error is PostgrestException) {
    final details = error.details?.toString().trim() ?? '';

    if (details.isNotEmpty && details.toLowerCase() != 'null') {
      return '${error.message} $details';
    }

    return error.message;
  }

  final message = error.toString().trim();

  if (message.isEmpty) {
    return 'Controlled official master verification failed.';
  }

  return message.replaceFirst(
    'Exception: ',
    '',
  );
}
