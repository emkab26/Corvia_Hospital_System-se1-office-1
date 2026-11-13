import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class HospitalFormEngineService {
  HospitalFormEngineService({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  String? get currentUserId {
    return _client.auth.currentUser?.id;
  }

  bool get isAuthenticated {
    return _client.auth.currentUser != null;
  }

  // ===========================================================================
  // AUTHENTICATION AND PROFILE HELPERS
  // ===========================================================================

  void _requireAuthentication() {
    if (_client.auth.currentUser == null) {
      throw const HospitalFormEngineException(
        'You must be signed in to use hospital forms.',
      );
    }
  }

  Future<String?> resolveCurrentProfileId() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return null;
    }

    try {
      final response = await _client
          .from('profiles')
          .select('id')
          .eq(
            'user_id',
            user.id,
          )
          .maybeSingle();

      final profileId = _string(
        response?['id'],
      );

      if (profileId != null) {
        return profileId;
      }
    } on PostgrestException {
      // Fall through to legacy lookup.
    }

    try {
      final response = await _client
          .from('profiles')
          .select('id')
          .eq(
            'id',
            user.id,
          )
          .maybeSingle();

      return _string(
        response?['id'],
      );
    } on PostgrestException {
      return null;
    }
  }

  Future<String?> resolveCurrentPatientId() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return null;
    }

    final profileId = await resolveCurrentProfileId();

    if (profileId != null) {
      try {
        final response = await _client
            .from('patients')
            .select('id')
            .eq(
              'profile_id',
              profileId,
            )
            .limit(1);

        final rows = _mapList(response);

        if (rows.isNotEmpty) {
          return _string(
            rows.first['id'],
          );
        }
      } on PostgrestException {
        // Try the legacy profile relation below.
      }
    }

    try {
      final response = await _client
          .from('patients')
          .select('id')
          .eq(
            'profile_id',
            user.id,
          )
          .limit(1);

      final rows = _mapList(response);

      if (rows.isEmpty) {
        return null;
      }

      return _string(
        rows.first['id'],
      );
    } on PostgrestException {
      return null;
    }
  }

  // ===========================================================================
  // TEMPLATE LIST
  // ===========================================================================

  Future<List<HospitalFormTemplateRecord>> loadTemplates({
    required String hospitalId,
    bool activeOnly = true,
    String? category,
    String? documentClassification,
  }) async {
    _requireAuthentication();

    final cleanHospitalId = _requiredId(
      hospitalId,
      'Hospital ID',
    );

    dynamic query = _client.from('hospital_form_templates').select(
      '''
          id,
          hospital_id,
          code,
          name,
          category,
          department,
          description,
          source_type,
          document_classification,
          statutory_code,
          status,
          requires_patient,
          requires_admission,
          requires_break_glass,
          patient_release_mode,
          retention_category,
          retention_years,
          current_version_id,
          approved_at,
          retired_at,
          created_at,
          updated_at
          ''',
    ).eq(
      'hospital_id',
      cleanHospitalId,
    );

    if (activeOnly) {
      query = query.eq(
        'status',
        'active',
      );
    }

    final cleanCategory = _nullableString(category);

    if (cleanCategory != null) {
      query = query.eq(
        'category',
        cleanCategory,
      );
    }

    final cleanClassification = _nullableString(
      documentClassification,
    );

    if (cleanClassification != null) {
      query = query.eq(
        'document_classification',
        cleanClassification,
      );
    }

    final response = await query
        .order(
          'category',
          ascending: true,
        )
        .order(
          'name',
          ascending: true,
        );

    return _mapList(response)
        .map(
          HospitalFormTemplateRecord.fromMap,
        )
        .toList(
          growable: false,
        );
  }

  Future<List<HospitalFormTemplateRecord>> loadPatientVisibleTemplates({
    required String hospitalId,
  }) {
    return loadTemplates(
      hospitalId: hospitalId,
      activeOnly: true,
      documentClassification: 'patient_visible',
    );
  }

  Future<List<String>> loadTemplateCategories({
    required String hospitalId,
  }) async {
    final templates = await loadTemplates(
      hospitalId: hospitalId,
    );

    final categories = templates
        .map(
          (template) => template.category,
        )
        .where(
          (category) => category.trim().isNotEmpty,
        )
        .toSet()
        .toList();

    categories.sort();

    return categories;
  }

  // ===========================================================================
  // TEMPLATE DEFINITION
  // ===========================================================================

  Future<HospitalFormTemplateDefinition> loadTemplateDefinition({
    required String templateId,
    String? versionId,
  }) async {
    _requireAuthentication();

    final cleanTemplateId = _requiredId(
      templateId,
      'Template ID',
    );

    final templateResponse = await _client
        .from('hospital_form_templates')
        .select(
          '''
          id,
          hospital_id,
          code,
          name,
          category,
          department,
          description,
          source_type,
          document_classification,
          statutory_code,
          status,
          requires_patient,
          requires_admission,
          requires_break_glass,
          patient_release_mode,
          retention_category,
          retention_years,
          current_version_id,
          approved_at,
          retired_at,
          created_at,
          updated_at
          ''',
        )
        .eq(
          'id',
          cleanTemplateId,
        )
        .maybeSingle();

    if (templateResponse == null) {
      throw const HospitalFormEngineException(
        'The hospital form template was not found or access was denied.',
      );
    }

    final template = HospitalFormTemplateRecord.fromMap(
      _map(templateResponse),
    );

    final resolvedVersionId =
        _nullableString(versionId) ?? template.currentVersionId;

    if (resolvedVersionId == null) {
      throw HospitalFormEngineException(
        'The form "${template.name}" does not have an active version.',
      );
    }

    final versionResponse = await _client
        .from(
          'hospital_form_template_versions',
        )
        .select(
          '''
          id,
          template_id,
          hospital_id,
          version_number,
          version_label,
          approval_status,
          schema_json,
          print_layout_json,
          language_code,
          approval_notes,
          content_hash,
          effective_at,
          approved_at,
          retired_at,
          created_at
          ''',
        )
        .eq(
          'id',
          resolvedVersionId,
        )
        .eq(
          'template_id',
          cleanTemplateId,
        )
        .maybeSingle();

    if (versionResponse == null) {
      throw HospitalFormEngineException(
        'The selected version of "${template.name}" was not found.',
      );
    }

    final version = HospitalFormTemplateVersionRecord.fromMap(
      _map(versionResponse),
    );

    final fieldResponse = await _client
        .from(
          'hospital_form_template_fields',
        )
        .select(
          '''
          id,
          hospital_id,
          template_id,
          version_id,
          section_key,
          section_title,
          field_key,
          field_label,
          field_type,
          display_order,
          is_required,
          is_read_only,
          is_patient_visible,
          sensitivity,
          placeholder,
          help_text,
          options_json,
          validation_json,
          visibility_rule,
          calculation_rule,
          created_at
          ''',
        )
        .eq(
          'template_id',
          cleanTemplateId,
        )
        .eq(
          'version_id',
          resolvedVersionId,
        )
        .order(
          'display_order',
          ascending: true,
        );

    final fields = _mapList(fieldResponse)
        .map(
          HospitalFormFieldRecord.fromMap,
        )
        .toList(
          growable: false,
        );

    List<HospitalFormPermissionRecord> permissions = const [];

    /*
     * The permissions table is intentionally
     * restricted. Hospital admins may see it,
     * while clinical users may receive an empty
     * list because their access is enforced by
     * the database functions and RLS.
     */

    try {
      final permissionResponse = await _client
          .from(
            'hospital_form_role_permissions',
          )
          .select(
            '''
            id,
            hospital_id,
            template_id,
            role,
            can_view,
            can_create,
            can_edit,
            can_submit,
            can_approve,
            can_sign,
            can_amend,
            can_release_to_patient,
            can_print,
            can_export,
            requires_patient_assignment,
            created_at,
            updated_at
            ''',
          )
          .eq(
            'template_id',
            cleanTemplateId,
          )
          .order(
            'role',
            ascending: true,
          );

      permissions = _mapList(permissionResponse)
          .map(
            HospitalFormPermissionRecord.fromMap,
          )
          .toList(
            growable: false,
          );
    } on PostgrestException {
      permissions = const [];
    }

    return HospitalFormTemplateDefinition(
      template: template,
      version: version,
      fields: fields,
      permissions: permissions,
    );
  }

  Future<List<HospitalFormFieldRecord>> loadTemplateFields({
    required String templateId,
    String? versionId,
  }) async {
    final definition = await loadTemplateDefinition(
      templateId: templateId,
      versionId: versionId,
    );

    return definition.fields;
  }

  // ===========================================================================
  // FORM INSTANCES
  // ===========================================================================

  Future<String> startFormInstance({
    required String templateId,
    String? patientId,
    String? admissionId,
    String? contextType,
    String? contextId,
    bool offlineCreated = false,
    String? offlineSyncKey,
    String? sourceDeviceId,
    Map<String, dynamic> workflowMetadata = const {},
  }) async {
    _requireAuthentication();

    final response = await _client.rpc(
      'corvia_form_start_instance',
      params: {
        'p_template_id': _requiredId(
          templateId,
          'Template ID',
        ),
        'p_patient_id': _nullableString(patientId),
        'p_admission_id': _nullableString(admissionId),
        'p_context_type': _nullableString(contextType),
        'p_context_id': _nullableString(contextId),
        'p_offline_created': offlineCreated,
        'p_offline_sync_key': _nullableString(offlineSyncKey),
        'p_source_device_id': _nullableString(sourceDeviceId),
        'p_workflow_metadata': workflowMetadata,
      },
    );

    return _requiredRpcId(
      response,
      'The form instance could not be created.',
    );
  }

  Future<List<HospitalFormInstanceRecord>> loadInstances({
    String? hospitalId,
    String? patientId,
    String? admissionId,
    String? templateId,
    List<String>? statuses,
    int limit = 100,
  }) async {
    _requireAuthentication();

    dynamic query = _client.from('hospital_form_instances').select(
      '''
          id,
          hospital_id,
          template_id,
          template_version_id,
          patient_id,
          admission_id,
          context_type,
          context_id,
          document_number,
          status,
          revision_number,
          template_snapshot,
          patient_snapshot,
          workflow_metadata,
          offline_created,
          offline_sync_key,
          source_device_id,
          started_by,
          submitted_by,
          approved_by,
          finalized_by,
          started_at,
          submitted_at,
          approved_at,
          finalized_at,
          released_to_patient_at,
          released_to_patient_by,
          is_legal_hold,
          void_reason,
          voided_by,
          voided_at,
          created_at,
          updated_at
          ''',
    );

    final cleanHospitalId = _nullableString(hospitalId);

    if (cleanHospitalId != null) {
      query = query.eq(
        'hospital_id',
        cleanHospitalId,
      );
    }

    final cleanPatientId = _nullableString(patientId);

    if (cleanPatientId != null) {
      query = query.eq(
        'patient_id',
        cleanPatientId,
      );
    }

    final cleanAdmissionId = _nullableString(admissionId);

    if (cleanAdmissionId != null) {
      query = query.eq(
        'admission_id',
        cleanAdmissionId,
      );
    }

    final cleanTemplateId = _nullableString(templateId);

    if (cleanTemplateId != null) {
      query = query.eq(
        'template_id',
        cleanTemplateId,
      );
    }

    final cleanStatuses = statuses
        ?.map(
          (status) => status.trim(),
        )
        .where(
          (status) => status.isNotEmpty,
        )
        .toList(
          growable: false,
        );

    if (cleanStatuses != null && cleanStatuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        cleanStatuses,
      );
    }

    final safeLimit = limit.clamp(
      1,
      500,
    );

    final response = await query
        .order(
          'created_at',
          ascending: false,
        )
        .limit(safeLimit);

    return _mapList(response)
        .map(
          HospitalFormInstanceRecord.fromMap,
        )
        .toList(
          growable: false,
        );
  }

  Future<List<HospitalFormInstanceRecord>> loadPatientForms({
    required String patientId,
    int limit = 100,
  }) {
    return loadInstances(
      patientId: patientId,
      limit: limit,
    );
  }

  Future<List<HospitalFormInstanceRecord>> loadCurrentPatientForms({
    int limit = 100,
  }) async {
    final patientId = await resolveCurrentPatientId();

    if (patientId == null) {
      return const [];
    }

    return loadPatientForms(
      patientId: patientId,
      limit: limit,
    );
  }

  Future<List<HospitalFormInstanceRecord>> loadAdmissionForms({
    required String admissionId,
    int limit = 100,
  }) {
    return loadInstances(
      admissionId: admissionId,
      limit: limit,
    );
  }

  Future<HospitalFormInstanceRecord> loadInstance({
    required String instanceId,
  }) async {
    _requireAuthentication();

    final response = await _client
        .from('hospital_form_instances')
        .select(
          '''
          id,
          hospital_id,
          template_id,
          template_version_id,
          patient_id,
          admission_id,
          context_type,
          context_id,
          document_number,
          status,
          revision_number,
          template_snapshot,
          patient_snapshot,
          workflow_metadata,
          offline_created,
          offline_sync_key,
          source_device_id,
          started_by,
          submitted_by,
          approved_by,
          finalized_by,
          started_at,
          submitted_at,
          approved_at,
          finalized_at,
          released_to_patient_at,
          released_to_patient_by,
          is_legal_hold,
          void_reason,
          voided_by,
          voided_at,
          created_at,
          updated_at
          ''',
        )
        .eq(
          'id',
          _requiredId(
            instanceId,
            'Instance ID',
          ),
        )
        .maybeSingle();

    if (response == null) {
      throw const HospitalFormEngineException(
        'The form instance was not found or access was denied.',
      );
    }

    return HospitalFormInstanceRecord.fromMap(
      _map(response),
    );
  }

  Future<HospitalFormInstanceWorkspace> loadInstanceWorkspace({
    required String instanceId,
  }) async {
    final instance = await loadInstance(
      instanceId: instanceId,
    );

    final definition = await loadTemplateDefinition(
      templateId: instance.templateId,
      versionId: instance.templateVersionId,
    );

    final valueResponse = await _client
        .from(
          'hospital_form_instance_values',
        )
        .select(
          '''
          id,
          hospital_id,
          instance_id,
          field_id,
          field_key,
          value_jsonb,
          value_text,
          revision_number,
          is_current,
          source,
          entered_by,
          entered_at,
          amended_from_value_id,
          amendment_reason
          ''',
        )
        .eq(
          'instance_id',
          instance.id,
        )
        .eq(
          'is_current',
          true,
        )
        .order(
          'entered_at',
          ascending: true,
        );

    final signatureResponse = await _client
        .from('hospital_form_signatures')
        .select(
          '''
          id,
          hospital_id,
          instance_id,
          signer_profile_id,
          signer_role,
          signer_name,
          signer_identifier,
          signature_method,
          signature_evidence,
          declaration_text,
          witness_profile_id,
          witness_name,
          source_device_id,
          signed_at,
          is_valid,
          revoked_at,
          revoked_by,
          revocation_reason
          ''',
        )
        .eq(
          'instance_id',
          instance.id,
        )
        .eq(
          'is_valid',
          true,
        )
        .order(
          'signed_at',
          ascending: true,
        );

    final attachmentResponse = await _client
        .from('hospital_form_attachments')
        .select(
          '''
          id,
          hospital_id,
          instance_id,
          attachment_type,
          file_name,
          storage_bucket,
          storage_path,
          mime_type,
          file_size_bytes,
          checksum_sha256,
          description,
          document_classification,
          uploaded_by,
          uploaded_at,
          is_active,
          deactivated_at,
          deactivated_by,
          deactivation_reason
          ''',
        )
        .eq(
          'instance_id',
          instance.id,
        )
        .eq(
          'is_active',
          true,
        )
        .order(
          'uploaded_at',
          ascending: false,
        );

    final values = _mapList(valueResponse)
        .map(
          HospitalFormValueRecord.fromMap,
        )
        .toList(
          growable: false,
        );

    final signatures = _mapList(signatureResponse)
        .map(
          HospitalFormSignatureRecord.fromMap,
        )
        .toList(
          growable: false,
        );

    final attachments = _mapList(attachmentResponse)
        .map(
          HospitalFormAttachmentRecord.fromMap,
        )
        .toList(
          growable: false,
        );

    return HospitalFormInstanceWorkspace(
      instance: instance,
      definition: definition,
      values: values,
      signatures: signatures,
      attachments: attachments,
    );
  }

  // ===========================================================================
  // ANSWERS
  // ===========================================================================

  Future<String> saveValue({
    required String instanceId,
    required String fieldKey,
    required Object? value,
    String? valueText,
    String source = 'manual',
    String? amendmentReason,
  }) async {
    _requireAuthentication();

    final cleanFieldKey = fieldKey.trim();

    if (cleanFieldKey.isEmpty) {
      throw const HospitalFormEngineException(
        'A form field key is required.',
      );
    }

    final normalizedValue = _normaliseJsonValue(value);

    final response = await _client.rpc(
      'corvia_form_save_value',
      params: {
        'p_instance_id': _requiredId(
          instanceId,
          'Instance ID',
        ),
        'p_field_key': cleanFieldKey,
        'p_value': normalizedValue,
        'p_value_text': _nullableString(valueText) ??
            valueToText(
              normalizedValue,
            ),
        'p_source': source.trim().isEmpty ? 'manual' : source.trim(),
        'p_amendment_reason': _nullableString(
          amendmentReason,
        ),
      },
    );

    return _requiredRpcId(
      response,
      'The form answer could not be saved.',
    );
  }

  Future<Map<String, String>> saveAnswers({
    required String instanceId,
    required Map<String, Object?> answers,
    Map<String, String?> valueText = const {},
    String source = 'manual',
    String? amendmentReason,
    void Function(
      int completed,
      int total,
      String fieldKey,
    )? onProgress,
  }) async {
    if (answers.isEmpty) {
      return const {};
    }

    final savedValueIds = <String, String>{};

    final entries = answers.entries.toList(
      growable: false,
    );

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];

      final valueId = await saveValue(
        instanceId: instanceId,
        fieldKey: entry.key,
        value: entry.value,
        valueText: valueText[entry.key],
        source: source,
        amendmentReason: amendmentReason,
      );

      savedValueIds[entry.key] = valueId;

      onProgress?.call(
        index + 1,
        entries.length,
        entry.key,
      );
    }

    return Map.unmodifiable(
      savedValueIds,
    );
  }

  Future<List<HospitalFormValueRecord>> loadValueHistory({
    required String instanceId,
    required String fieldKey,
  }) async {
    _requireAuthentication();

    final response = await _client
        .from(
          'hospital_form_instance_values',
        )
        .select(
          '''
          id,
          hospital_id,
          instance_id,
          field_id,
          field_key,
          value_jsonb,
          value_text,
          revision_number,
          is_current,
          source,
          entered_by,
          entered_at,
          amended_from_value_id,
          amendment_reason
          ''',
        )
        .eq(
          'instance_id',
          _requiredId(
            instanceId,
            'Instance ID',
          ),
        )
        .eq(
          'field_key',
          fieldKey.trim(),
        )
        .order(
          'revision_number',
          ascending: false,
        );

    return _mapList(response)
        .map(
          HospitalFormValueRecord.fromMap,
        )
        .toList(
          growable: false,
        );
  }

  // ===========================================================================
  // WORKFLOW
  // ===========================================================================

  Future<bool> submitForm({
    required String instanceId,
  }) async {
    _requireAuthentication();

    final response = await _client.rpc(
      'corvia_form_submit_instance',
      params: {
        'p_instance_id': _requiredId(
          instanceId,
          'Instance ID',
        ),
      },
    );

    return _rpcBoolean(
      response,
      operationName: 'submit the form',
    );
  }

  Future<String> signForm({
    required String instanceId,
    required String signerRole,
    required String signerName,
    required String signatureMethod,
    Map<String, dynamic> signatureEvidence = const {},
    String? signerIdentifier,
    String? declarationText,
    String? witnessProfileId,
    String? witnessName,
    String? sourceDeviceId,
  }) async {
    _requireAuthentication();

    if (signerRole.trim().isEmpty) {
      throw const HospitalFormEngineException(
        'The signer role is required.',
      );
    }

    if (signerName.trim().isEmpty) {
      throw const HospitalFormEngineException(
        'The signer name is required.',
      );
    }

    if (signatureMethod.trim().isEmpty) {
      throw const HospitalFormEngineException(
        'The signature method is required.',
      );
    }

    final response = await _client.rpc(
      'corvia_form_sign_instance',
      params: {
        'p_instance_id': _requiredId(
          instanceId,
          'Instance ID',
        ),
        'p_signer_role': signerRole.trim(),
        'p_signer_name': signerName.trim(),
        'p_signature_method': signatureMethod.trim(),
        'p_signature_evidence': signatureEvidence,
        'p_signer_identifier': _nullableString(
          signerIdentifier,
        ),
        'p_declaration_text': _nullableString(
          declarationText,
        ),
        'p_witness_profile_id': _nullableString(
          witnessProfileId,
        ),
        'p_witness_name': _nullableString(
          witnessName,
        ),
        'p_source_device_id': _nullableString(
          sourceDeviceId,
        ),
      },
    );

    return _requiredRpcId(
      response,
      'The form signature could not be recorded.',
    );
  }

  Future<bool> finalizeForm({
    required String instanceId,
    bool releaseToPatient = false,
  }) async {
    _requireAuthentication();

    final response = await _client.rpc(
      'corvia_form_finalize_instance',
      params: {
        'p_instance_id': _requiredId(
          instanceId,
          'Instance ID',
        ),
        'p_release_to_patient': releaseToPatient,
      },
    );

    return _rpcBoolean(
      response,
      operationName: 'finalize the form',
    );
  }

  Future<bool> releaseFormToPatient({
    required String instanceId,
  }) async {
    _requireAuthentication();

    final response = await _client.rpc(
      'corvia_form_release_to_patient',
      params: {
        'p_instance_id': _requiredId(
          instanceId,
          'Instance ID',
        ),
      },
    );

    return _rpcBoolean(
      response,
      operationName: 'release the form to the patient',
    );
  }

  // ===========================================================================
  // ATTACHMENT METADATA
  // ===========================================================================

  Future<String> addAttachmentMetadata({
    required String instanceId,
    required String attachmentType,
    required String fileName,
    required String storageBucket,
    required String storagePath,
    String? mimeType,
    int? fileSizeBytes,
    String? checksumSha256,
    String? description,
    String documentClassification = 'clinical',
  }) async {
    _requireAuthentication();

    if (fileName.trim().isEmpty) {
      throw const HospitalFormEngineException(
        'The attachment file name is required.',
      );
    }

    if (storageBucket.trim().isEmpty) {
      throw const HospitalFormEngineException(
        'The Storage bucket is required.',
      );
    }

    if (storagePath.trim().isEmpty) {
      throw const HospitalFormEngineException(
        'The Storage path is required.',
      );
    }

    final response = await _client.rpc(
      'corvia_form_add_attachment',
      params: {
        'p_instance_id': _requiredId(
          instanceId,
          'Instance ID',
        ),
        'p_attachment_type': attachmentType.trim().isEmpty
            ? 'supporting_document'
            : attachmentType.trim(),
        'p_file_name': fileName.trim(),
        'p_storage_bucket': storageBucket.trim(),
        'p_storage_path': storagePath.trim(),
        'p_mime_type': _nullableString(mimeType),
        'p_file_size_bytes': fileSizeBytes,
        'p_checksum_sha256': _nullableString(
          checksumSha256,
        ),
        'p_description': _nullableString(description),
        'p_document_classification': documentClassification.trim(),
      },
    );

    return _requiredRpcId(
      response,
      'The attachment metadata could not be saved.',
    );
  }

  // ===========================================================================
  // BREAK-GLASS ACCESS
  // ===========================================================================

  Future<String> startBreakGlassAccess({
    required String hospitalId,
    required String patientId,
    required String reason,
    int durationMinutes = 30,
  }) async {
    _requireAuthentication();

    if (reason.trim().isEmpty) {
      throw const HospitalFormEngineException(
        'A break-glass reason is required.',
      );
    }

    final response = await _client.rpc(
      'corvia_form_start_break_glass',
      params: {
        'p_hospital_id': _requiredId(
          hospitalId,
          'Hospital ID',
        ),
        'p_patient_id': _requiredId(
          patientId,
          'Patient ID',
        ),
        'p_reason': reason.trim(),
        'p_duration_minutes': durationMinutes.clamp(
          5,
          60,
        ),
      },
    );

    return _requiredRpcId(
      response,
      'Break-glass access could not be started.',
    );
  }

  Future<bool> endBreakGlassAccess({
    required String sessionId,
  }) async {
    _requireAuthentication();

    final response = await _client.rpc(
      'corvia_form_end_break_glass',
      params: {
        'p_session_id': _requiredId(
          sessionId,
          'Break-glass session ID',
        ),
      },
    );

    return _rpcBoolean(
      response,
      operationName: 'end break-glass access',
    );
  }

  // ===========================================================================
  // LEGAL HOLD AND EXPORT AUDIT
  // ===========================================================================

  Future<String> placeLegalHold({
    required String instanceId,
    required String holdReason,
    String? referenceNumber,
  }) async {
    _requireAuthentication();

    if (holdReason.trim().isEmpty) {
      throw const HospitalFormEngineException(
        'A legal-hold reason is required.',
      );
    }

    final response = await _client.rpc(
      'corvia_form_place_legal_hold',
      params: {
        'p_instance_id': _requiredId(
          instanceId,
          'Instance ID',
        ),
        'p_hold_reason': holdReason.trim(),
        'p_reference_number': _nullableString(
          referenceNumber,
        ),
      },
    );

    return _requiredRpcId(
      response,
      'The legal hold could not be created.',
    );
  }

  Future<String> logExport({
    required String instanceId,
    required String exportType,
    String? storageBucket,
    String? storagePath,
    String? destination,
    String? reason,
  }) async {
    _requireAuthentication();

    final allowedTypes = {
      'pdf',
      'print',
      'download',
      'share',
      'external_submission',
    };

    final cleanExportType = exportType.trim();

    if (!allowedTypes.contains(
      cleanExportType,
    )) {
      throw HospitalFormEngineException(
        'Unsupported export type: '
        '$cleanExportType',
      );
    }

    final response = await _client.rpc(
      'corvia_form_log_export',
      params: {
        'p_instance_id': _requiredId(
          instanceId,
          'Instance ID',
        ),
        'p_export_type': cleanExportType,
        'p_storage_bucket': _nullableString(
          storageBucket,
        ),
        'p_storage_path': _nullableString(
          storagePath,
        ),
        'p_destination': _nullableString(
          destination,
        ),
        'p_reason': _nullableString(reason),
      },
    );

    return _requiredRpcId(
      response,
      'The form export event could not be recorded.',
    );
  }

  // ===========================================================================
  // AUDIT EVENTS
  // ===========================================================================

  Future<List<HospitalFormAuditEventRecord>> loadAuditEvents({
    required String instanceId,
    int limit = 200,
  }) async {
    _requireAuthentication();

    final response = await _client
        .from(
          'hospital_form_audit_events',
        )
        .select(
          '''
          id,
          hospital_id,
          template_id,
          instance_id,
          patient_id,
          event_type,
          event_key,
          actor_profile_id,
          actor_role,
          reason,
          metadata,
          source_device_id,
          occurred_at
          ''',
        )
        .eq(
          'instance_id',
          _requiredId(
            instanceId,
            'Instance ID',
          ),
        )
        .order(
          'occurred_at',
          ascending: false,
        )
        .limit(
          limit.clamp(
            1,
            500,
          ),
        );

    return _mapList(response)
        .map(
          HospitalFormAuditEventRecord.fromMap,
        )
        .toList(
          growable: false,
        );
  }

  // ===========================================================================
  // VALUE HELPERS
  // ===========================================================================

  static String? valueToText(
    Object? value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      final clean = value.trim();

      return clean.isEmpty ? null : clean;
    }

    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    if (value is bool || value is num) {
      return value.toString();
    }

    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  static Object? _normaliseJsonValue(
    Object? value,
  ) {
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    if (value is Iterable) {
      return value
          .map(
            _normaliseJsonValue,
          )
          .toList();
    }

    if (value is Map) {
      return value.map(
        (
          key,
          mapValue,
        ) {
          return MapEntry(
            key.toString(),
            _normaliseJsonValue(
              mapValue,
            ),
          );
        },
      );
    }

    return value;
  }

  static String _requiredId(
    String value,
    String label,
  ) {
    final clean = value.trim();

    if (clean.isEmpty) {
      throw HospitalFormEngineException(
        '$label is required.',
      );
    }

    return clean;
  }

  static String? _nullableString(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    final clean = value.toString().trim();

    if (clean.isEmpty || clean.toLowerCase() == 'null') {
      return null;
    }

    return clean;
  }

  static String? _string(
    dynamic value,
  ) {
    return _nullableString(value);
  }

  static bool _rpcBoolean(
    dynamic response, {
    required String operationName,
  }) {
    if (response is bool) {
      return response;
    }

    if (response is num) {
      return response != 0;
    }

    final text = response?.toString().trim().toLowerCase();

    if (text == 'true' || text == '1') {
      return true;
    }

    if (text == 'false' || text == '0') {
      return false;
    }

    throw HospitalFormEngineException(
      'Corvia could not $operationName.',
    );
  }

  static String _requiredRpcId(
    dynamic response,
    String errorMessage,
  ) {
    final direct = _nullableString(
      response,
    );

    if (direct != null && !direct.startsWith('{') && !direct.startsWith('[')) {
      return direct;
    }

    if (response is Map) {
      final responseMap = _map(
        response,
      );

      final id = _nullableString(
        responseMap['id'],
      );

      if (id != null) {
        return id;
      }
    }

    if (response is List && response.isNotEmpty) {
      final first = response.first;

      if (first is Map) {
        final id = _nullableString(
          first['id'],
        );

        if (id != null) {
          return id;
        }
      }

      final firstText = _nullableString(first);

      if (firstText != null) {
        return firstText;
      }
    }

    throw HospitalFormEngineException(
      errorMessage,
    );
  }

  static Map<String, dynamic> _map(
    dynamic value,
  ) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _mapList(
    dynamic value,
  ) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(
            row,
          ),
        )
        .toList(
          growable: false,
        );
  }
}

// =============================================================================
// TEMPLATE MODEL
// =============================================================================

class HospitalFormTemplateRecord {
  const HospitalFormTemplateRecord({
    required this.id,
    required this.hospitalId,
    required this.code,
    required this.name,
    required this.category,
    required this.sourceType,
    required this.documentClassification,
    required this.status,
    required this.requiresPatient,
    required this.requiresAdmission,
    required this.requiresBreakGlass,
    required this.patientReleaseMode,
    this.department,
    this.description,
    this.statutoryCode,
    this.retentionCategory,
    this.retentionYears,
    this.currentVersionId,
    this.approvedAt,
    this.retiredAt,
    this.createdAt,
    this.updatedAt,
  });

  factory HospitalFormTemplateRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormTemplateRecord(
      id: _requiredText(
        map['id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      code: _requiredText(
        map['code'],
      ),
      name: _requiredText(
        map['name'],
      ),
      category: _requiredText(
        map['category'],
      ),
      department: _optionalText(
        map['department'],
      ),
      description: _optionalText(
        map['description'],
      ),
      sourceType: _textOr(
        map['source_type'],
        'hospital_specific',
      ),
      documentClassification: _textOr(
        map['document_classification'],
        'clinical',
      ),
      statutoryCode: _optionalText(
        map['statutory_code'],
      ),
      status: _textOr(
        map['status'],
        'draft',
      ),
      requiresPatient: _boolOr(
        map['requires_patient'],
        true,
      ),
      requiresAdmission: _boolOr(
        map['requires_admission'],
        false,
      ),
      requiresBreakGlass: _boolOr(
        map['requires_break_glass'],
        false,
      ),
      patientReleaseMode: _textOr(
        map['patient_release_mode'],
        'after_approval',
      ),
      retentionCategory: _optionalText(
        map['retention_category'],
      ),
      retentionYears: _intOrNull(
        map['retention_years'],
      ),
      currentVersionId: _optionalText(
        map['current_version_id'],
      ),
      approvedAt: _dateTimeOrNull(
        map['approved_at'],
      ),
      retiredAt: _dateTimeOrNull(
        map['retired_at'],
      ),
      createdAt: _dateTimeOrNull(
        map['created_at'],
      ),
      updatedAt: _dateTimeOrNull(
        map['updated_at'],
      ),
    );
  }

  final String id;
  final String hospitalId;
  final String code;
  final String name;
  final String category;

  final String? department;
  final String? description;

  final String sourceType;
  final String documentClassification;
  final String? statutoryCode;
  final String status;

  final bool requiresPatient;
  final bool requiresAdmission;
  final bool requiresBreakGlass;

  final String patientReleaseMode;
  final String? retentionCategory;
  final int? retentionYears;

  final String? currentVersionId;

  final DateTime? approvedAt;
  final DateTime? retiredAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive {
    return status == 'active' && currentVersionId != null;
  }

  bool get isPatientVisible {
    return documentClassification == 'patient_visible';
  }

  bool get isClinical {
    return documentClassification == 'clinical';
  }

  bool get isHighlyRestricted {
    return documentClassification == 'highly_restricted';
  }

  bool get mayReleaseToPatient {
    return patientReleaseMode != 'never';
  }

  String get displayCategory {
    return _humanize(category);
  }
}

// =============================================================================
// TEMPLATE VERSION MODEL
// =============================================================================

class HospitalFormTemplateVersionRecord {
  const HospitalFormTemplateVersionRecord({
    required this.id,
    required this.templateId,
    required this.hospitalId,
    required this.versionNumber,
    required this.versionLabel,
    required this.approvalStatus,
    required this.schemaJson,
    required this.printLayoutJson,
    required this.languageCode,
    this.approvalNotes,
    this.contentHash,
    this.effectiveAt,
    this.approvedAt,
    this.retiredAt,
    this.createdAt,
  });

  factory HospitalFormTemplateVersionRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormTemplateVersionRecord(
      id: _requiredText(
        map['id'],
      ),
      templateId: _requiredText(
        map['template_id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      versionNumber: _intOr(
        map['version_number'],
        1,
      ),
      versionLabel: _textOr(
        map['version_label'],
        'Version 1',
      ),
      approvalStatus: _textOr(
        map['approval_status'],
        'draft',
      ),
      schemaJson: _jsonMap(
        map['schema_json'],
      ),
      printLayoutJson: _jsonMap(
        map['print_layout_json'],
      ),
      languageCode: _textOr(
        map['language_code'],
        'en-ZA',
      ),
      approvalNotes: _optionalText(
        map['approval_notes'],
      ),
      contentHash: _optionalText(
        map['content_hash'],
      ),
      effectiveAt: _dateTimeOrNull(
        map['effective_at'],
      ),
      approvedAt: _dateTimeOrNull(
        map['approved_at'],
      ),
      retiredAt: _dateTimeOrNull(
        map['retired_at'],
      ),
      createdAt: _dateTimeOrNull(
        map['created_at'],
      ),
    );
  }

  final String id;
  final String templateId;
  final String hospitalId;

  final int versionNumber;
  final String versionLabel;
  final String approvalStatus;

  final Map<String, dynamic> schemaJson;
  final Map<String, dynamic> printLayoutJson;

  final String languageCode;
  final String? approvalNotes;
  final String? contentHash;

  final DateTime? effectiveAt;
  final DateTime? approvedAt;
  final DateTime? retiredAt;
  final DateTime? createdAt;

  bool get isApproved {
    return approvalStatus == 'approved';
  }

  bool get isDemoOnly {
    return schemaJson['demo_only'] == true;
  }

  bool get productionApproved {
    return schemaJson['production_approved'] == true;
  }
}

// =============================================================================
// FIELD MODEL
// =============================================================================

class HospitalFormFieldRecord {
  const HospitalFormFieldRecord({
    required this.id,
    required this.hospitalId,
    required this.templateId,
    required this.versionId,
    required this.sectionKey,
    required this.sectionTitle,
    required this.fieldKey,
    required this.fieldLabel,
    required this.fieldType,
    required this.displayOrder,
    required this.isRequired,
    required this.isReadOnly,
    required this.isPatientVisible,
    required this.sensitivity,
    required this.options,
    required this.validation,
    required this.visibilityRule,
    required this.calculationRule,
    this.placeholder,
    this.helpText,
    this.createdAt,
  });

  factory HospitalFormFieldRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormFieldRecord(
      id: _requiredText(
        map['id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      templateId: _requiredText(
        map['template_id'],
      ),
      versionId: _requiredText(
        map['version_id'],
      ),
      sectionKey: _textOr(
        map['section_key'],
        'general',
      ),
      sectionTitle: _textOr(
        map['section_title'],
        'General',
      ),
      fieldKey: _requiredText(
        map['field_key'],
      ),
      fieldLabel: _requiredText(
        map['field_label'],
      ),
      fieldType: _requiredText(
        map['field_type'],
      ),
      displayOrder: _intOr(
        map['display_order'],
        0,
      ),
      isRequired: _boolOr(
        map['is_required'],
        false,
      ),
      isReadOnly: _boolOr(
        map['is_read_only'],
        false,
      ),
      isPatientVisible: _boolOr(
        map['is_patient_visible'],
        false,
      ),
      sensitivity: _textOr(
        map['sensitivity'],
        'standard',
      ),
      placeholder: _optionalText(
        map['placeholder'],
      ),
      helpText: _optionalText(
        map['help_text'],
      ),
      options: _jsonList(
        map['options_json'],
      ),
      validation: _jsonMap(
        map['validation_json'],
      ),
      visibilityRule: _jsonMap(
        map['visibility_rule'],
      ),
      calculationRule: _jsonMap(
        map['calculation_rule'],
      ),
      createdAt: _dateTimeOrNull(
        map['created_at'],
      ),
    );
  }

  final String id;
  final String hospitalId;
  final String templateId;
  final String versionId;

  final String sectionKey;
  final String sectionTitle;

  final String fieldKey;
  final String fieldLabel;
  final String fieldType;

  final int displayOrder;

  final bool isRequired;
  final bool isReadOnly;
  final bool isPatientVisible;

  final String sensitivity;

  final String? placeholder;
  final String? helpText;

  final List<dynamic> options;
  final Map<String, dynamic> validation;
  final Map<String, dynamic> visibilityRule;
  final Map<String, dynamic> calculationRule;

  final DateTime? createdAt;

  bool get isInformation {
    return fieldType == 'information';
  }

  bool get isSignature {
    return fieldType == 'signature';
  }

  bool get supportsMultipleValues {
    return fieldType == 'multiple_choice';
  }

  List<String> get stringOptions {
    return options
        .map(
          (option) => option.toString(),
        )
        .toList(
          growable: false,
        );
  }

  bool shouldShow(
    Map<String, Object?> answers,
  ) {
    if (visibilityRule.isEmpty) {
      return true;
    }

    final dependencyField = visibilityRule['field']?.toString().trim();

    if (dependencyField == null || dependencyField.isEmpty) {
      return true;
    }

    final operator =
        visibilityRule['operator']?.toString().trim().toLowerCase() ?? 'equals';

    final expected = visibilityRule['value'];

    final actual = answers[dependencyField];

    switch (operator) {
      case 'equals':
      case 'eq':
        return _valuesEqual(
          actual,
          expected,
        );

      case 'not_equals':
      case 'neq':
        return !_valuesEqual(
          actual,
          expected,
        );

      case 'in':
        if (expected is List) {
          return expected.any(
            (item) => _valuesEqual(
              actual,
              item,
            ),
          );
        }

        return false;

      case 'not_in':
        if (expected is List) {
          return !expected.any(
            (item) => _valuesEqual(
              actual,
              item,
            ),
          );
        }

        return true;

      case 'is_empty':
        return _isEmptyValue(actual);

      case 'is_not_empty':
        return !_isEmptyValue(actual);

      case 'truthy':
      case 'is_true':
        return actual == true;

      case 'falsy':
      case 'is_false':
        return actual == false;

      default:
        return true;
    }
  }

  String? validateValue(
    Object? value,
  ) {
    if (isInformation) {
      return null;
    }

    if (isRequired && _isEmptyValue(value)) {
      return '$fieldLabel is required.';
    }

    if (_isEmptyValue(value)) {
      return null;
    }

    final minLength = _numOrNull(
      validation['min_length'],
    )?.toInt();

    final maxLength = _numOrNull(
      validation['max_length'],
    )?.toInt();

    final text = value.toString();

    if (minLength != null && text.length < minLength) {
      return '$fieldLabel must contain at least '
          '$minLength characters.';
    }

    if (maxLength != null && text.length > maxLength) {
      return '$fieldLabel may not contain more than '
          '$maxLength characters.';
    }

    final numericValue = _numOrNull(value);

    final minimum = _numOrNull(
      validation['min'],
    );

    final maximum = _numOrNull(
      validation['max'],
    );

    if (numericValue != null && minimum != null && numericValue < minimum) {
      return '$fieldLabel may not be less than '
          '$minimum.';
    }

    if (numericValue != null && maximum != null && numericValue > maximum) {
      return '$fieldLabel may not be greater than '
          '$maximum.';
    }

    final regexPattern = _optionalText(
      validation['regex'],
    );

    if (regexPattern != null) {
      try {
        final regex = RegExp(
          regexPattern,
        );

        if (!regex.hasMatch(text)) {
          return '$fieldLabel is not in the required format.';
        }
      } on FormatException {
        // Invalid template regex should not crash
        // the form renderer.
      }
    }

    return null;
  }
}

// =============================================================================
// ROLE PERMISSION MODEL
// =============================================================================

class HospitalFormPermissionRecord {
  const HospitalFormPermissionRecord({
    required this.id,
    required this.hospitalId,
    required this.templateId,
    required this.role,
    required this.canView,
    required this.canCreate,
    required this.canEdit,
    required this.canSubmit,
    required this.canApprove,
    required this.canSign,
    required this.canAmend,
    required this.canReleaseToPatient,
    required this.canPrint,
    required this.canExport,
    required this.requiresPatientAssignment,
    this.createdAt,
    this.updatedAt,
  });

  factory HospitalFormPermissionRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormPermissionRecord(
      id: _requiredText(
        map['id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      templateId: _requiredText(
        map['template_id'],
      ),
      role: _requiredText(
        map['role'],
      ),
      canView: _boolOr(
        map['can_view'],
        false,
      ),
      canCreate: _boolOr(
        map['can_create'],
        false,
      ),
      canEdit: _boolOr(
        map['can_edit'],
        false,
      ),
      canSubmit: _boolOr(
        map['can_submit'],
        false,
      ),
      canApprove: _boolOr(
        map['can_approve'],
        false,
      ),
      canSign: _boolOr(
        map['can_sign'],
        false,
      ),
      canAmend: _boolOr(
        map['can_amend'],
        false,
      ),
      canReleaseToPatient: _boolOr(
        map['can_release_to_patient'],
        false,
      ),
      canPrint: _boolOr(
        map['can_print'],
        false,
      ),
      canExport: _boolOr(
        map['can_export'],
        false,
      ),
      requiresPatientAssignment: _boolOr(
        map['requires_patient_assignment'],
        false,
      ),
      createdAt: _dateTimeOrNull(
        map['created_at'],
      ),
      updatedAt: _dateTimeOrNull(
        map['updated_at'],
      ),
    );
  }

  final String id;
  final String hospitalId;
  final String templateId;
  final String role;

  final bool canView;
  final bool canCreate;
  final bool canEdit;
  final bool canSubmit;
  final bool canApprove;
  final bool canSign;
  final bool canAmend;
  final bool canReleaseToPatient;
  final bool canPrint;
  final bool canExport;

  final bool requiresPatientAssignment;

  final DateTime? createdAt;
  final DateTime? updatedAt;
}

// =============================================================================
// TEMPLATE DEFINITION
// =============================================================================

class HospitalFormTemplateDefinition {
  const HospitalFormTemplateDefinition({
    required this.template,
    required this.version,
    required this.fields,
    required this.permissions,
  });

  final HospitalFormTemplateRecord template;
  final HospitalFormTemplateVersionRecord version;

  final List<HospitalFormFieldRecord> fields;
  final List<HospitalFormPermissionRecord> permissions;

  List<String> get sectionKeys {
    final result = <String>[];

    for (final field in fields) {
      if (!result.contains(
        field.sectionKey,
      )) {
        result.add(
          field.sectionKey,
        );
      }
    }

    return result;
  }

  List<HospitalFormFieldRecord> fieldsForSection(
    String sectionKey,
  ) {
    return fields
        .where(
          (field) => field.sectionKey == sectionKey,
        )
        .toList(
          growable: false,
        );
  }

  String sectionTitle(
    String sectionKey,
  ) {
    for (final field in fields) {
      if (field.sectionKey == sectionKey) {
        return field.sectionTitle;
      }
    }

    return _humanize(
      sectionKey,
    );
  }

  HospitalFormFieldRecord? fieldByKey(
    String fieldKey,
  ) {
    for (final field in fields) {
      if (field.fieldKey == fieldKey) {
        return field;
      }
    }

    return null;
  }

  HospitalFormPermissionRecord? permissionForRole(
    String role,
  ) {
    final cleanRole = role.trim().toLowerCase();

    for (final permission in permissions) {
      if (permission.role.trim().toLowerCase() == cleanRole) {
        return permission;
      }
    }

    return null;
  }

  Map<String, String> validateAnswers(
    Map<String, Object?> answers,
  ) {
    final errors = <String, String>{};

    for (final field in fields) {
      if (!field.shouldShow(
        answers,
      )) {
        continue;
      }

      final error = field.validateValue(
        answers[field.fieldKey],
      );

      if (error != null) {
        errors[field.fieldKey] = error;
      }
    }

    return errors;
  }
}

// =============================================================================
// INSTANCE MODEL
// =============================================================================

class HospitalFormInstanceRecord {
  const HospitalFormInstanceRecord({
    required this.id,
    required this.hospitalId,
    required this.templateId,
    required this.templateVersionId,
    required this.documentNumber,
    required this.status,
    required this.revisionNumber,
    required this.templateSnapshot,
    required this.patientSnapshot,
    required this.workflowMetadata,
    required this.offlineCreated,
    required this.isLegalHold,
    this.patientId,
    this.admissionId,
    this.contextType,
    this.contextId,
    this.offlineSyncKey,
    this.sourceDeviceId,
    this.startedBy,
    this.submittedBy,
    this.approvedBy,
    this.finalizedBy,
    this.startedAt,
    this.submittedAt,
    this.approvedAt,
    this.finalizedAt,
    this.releasedToPatientAt,
    this.releasedToPatientBy,
    this.voidReason,
    this.voidedBy,
    this.voidedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory HospitalFormInstanceRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormInstanceRecord(
      id: _requiredText(
        map['id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      templateId: _requiredText(
        map['template_id'],
      ),
      templateVersionId: _requiredText(
        map['template_version_id'],
      ),
      patientId: _optionalText(
        map['patient_id'],
      ),
      admissionId: _optionalText(
        map['admission_id'],
      ),
      contextType: _optionalText(
        map['context_type'],
      ),
      contextId: _optionalText(
        map['context_id'],
      ),
      documentNumber: _requiredText(
        map['document_number'],
      ),
      status: _textOr(
        map['status'],
        'draft',
      ),
      revisionNumber: _intOr(
        map['revision_number'],
        1,
      ),
      templateSnapshot: _jsonMap(
        map['template_snapshot'],
      ),
      patientSnapshot: _jsonMap(
        map['patient_snapshot'],
      ),
      workflowMetadata: _jsonMap(
        map['workflow_metadata'],
      ),
      offlineCreated: _boolOr(
        map['offline_created'],
        false,
      ),
      offlineSyncKey: _optionalText(
        map['offline_sync_key'],
      ),
      sourceDeviceId: _optionalText(
        map['source_device_id'],
      ),
      startedBy: _optionalText(
        map['started_by'],
      ),
      submittedBy: _optionalText(
        map['submitted_by'],
      ),
      approvedBy: _optionalText(
        map['approved_by'],
      ),
      finalizedBy: _optionalText(
        map['finalized_by'],
      ),
      startedAt: _dateTimeOrNull(
        map['started_at'],
      ),
      submittedAt: _dateTimeOrNull(
        map['submitted_at'],
      ),
      approvedAt: _dateTimeOrNull(
        map['approved_at'],
      ),
      finalizedAt: _dateTimeOrNull(
        map['finalized_at'],
      ),
      releasedToPatientAt: _dateTimeOrNull(
        map['released_to_patient_at'],
      ),
      releasedToPatientBy: _optionalText(
        map['released_to_patient_by'],
      ),
      isLegalHold: _boolOr(
        map['is_legal_hold'],
        false,
      ),
      voidReason: _optionalText(
        map['void_reason'],
      ),
      voidedBy: _optionalText(
        map['voided_by'],
      ),
      voidedAt: _dateTimeOrNull(
        map['voided_at'],
      ),
      createdAt: _dateTimeOrNull(
        map['created_at'],
      ),
      updatedAt: _dateTimeOrNull(
        map['updated_at'],
      ),
    );
  }

  final String id;
  final String hospitalId;
  final String templateId;
  final String templateVersionId;

  final String? patientId;
  final String? admissionId;

  final String? contextType;
  final String? contextId;

  final String documentNumber;
  final String status;
  final int revisionNumber;

  final Map<String, dynamic> templateSnapshot;
  final Map<String, dynamic> patientSnapshot;
  final Map<String, dynamic> workflowMetadata;

  final bool offlineCreated;
  final String? offlineSyncKey;
  final String? sourceDeviceId;

  final String? startedBy;
  final String? submittedBy;
  final String? approvedBy;
  final String? finalizedBy;

  final DateTime? startedAt;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final DateTime? finalizedAt;

  final DateTime? releasedToPatientAt;
  final String? releasedToPatientBy;

  final bool isLegalHold;

  final String? voidReason;
  final String? voidedBy;
  final DateTime? voidedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isEditable {
    return {
      'draft',
      'in_progress',
      'amended',
    }.contains(status);
  }

  bool get isSubmitted {
    return {
      'submitted',
      'under_review',
      'approved',
      'finalized',
    }.contains(status);
  }

  bool get isFinalized {
    return status == 'finalized';
  }

  bool get isReleasedToPatient {
    return releasedToPatientAt != null;
  }

  String get templateName {
    return _textOr(
      templateSnapshot['template_name'],
      'Hospital Form',
    );
  }

  String get templateCode {
    return _textOr(
      templateSnapshot['template_code'],
      '',
    );
  }

  String get versionLabel {
    return _textOr(
      templateSnapshot['version_label'],
      '',
    );
  }
}

// =============================================================================
// VALUE MODEL
// =============================================================================

class HospitalFormValueRecord {
  const HospitalFormValueRecord({
    required this.id,
    required this.hospitalId,
    required this.instanceId,
    required this.fieldKey,
    required this.value,
    required this.revisionNumber,
    required this.isCurrent,
    required this.source,
    this.fieldId,
    this.valueText,
    this.enteredBy,
    this.enteredAt,
    this.amendedFromValueId,
    this.amendmentReason,
  });

  factory HospitalFormValueRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormValueRecord(
      id: _requiredText(
        map['id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      instanceId: _requiredText(
        map['instance_id'],
      ),
      fieldId: _optionalText(
        map['field_id'],
      ),
      fieldKey: _requiredText(
        map['field_key'],
      ),
      value: map['value_jsonb'],
      valueText: _optionalText(
        map['value_text'],
      ),
      revisionNumber: _intOr(
        map['revision_number'],
        1,
      ),
      isCurrent: _boolOr(
        map['is_current'],
        true,
      ),
      source: _textOr(
        map['source'],
        'manual',
      ),
      enteredBy: _optionalText(
        map['entered_by'],
      ),
      enteredAt: _dateTimeOrNull(
        map['entered_at'],
      ),
      amendedFromValueId: _optionalText(
        map['amended_from_value_id'],
      ),
      amendmentReason: _optionalText(
        map['amendment_reason'],
      ),
    );
  }

  final String id;
  final String hospitalId;
  final String instanceId;
  final String? fieldId;

  final String fieldKey;
  final dynamic value;
  final String? valueText;

  final int revisionNumber;
  final bool isCurrent;
  final String source;

  final String? enteredBy;
  final DateTime? enteredAt;

  final String? amendedFromValueId;
  final String? amendmentReason;
}

// =============================================================================
// SIGNATURE MODEL
// =============================================================================

class HospitalFormSignatureRecord {
  const HospitalFormSignatureRecord({
    required this.id,
    required this.hospitalId,
    required this.instanceId,
    required this.signerRole,
    required this.signerName,
    required this.signatureMethod,
    required this.signatureEvidence,
    required this.isValid,
    this.signerProfileId,
    this.signerIdentifier,
    this.declarationText,
    this.witnessProfileId,
    this.witnessName,
    this.sourceDeviceId,
    this.signedAt,
    this.revokedAt,
    this.revokedBy,
    this.revocationReason,
  });

  factory HospitalFormSignatureRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormSignatureRecord(
      id: _requiredText(
        map['id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      instanceId: _requiredText(
        map['instance_id'],
      ),
      signerProfileId: _optionalText(
        map['signer_profile_id'],
      ),
      signerRole: _requiredText(
        map['signer_role'],
      ),
      signerName: _requiredText(
        map['signer_name'],
      ),
      signerIdentifier: _optionalText(
        map['signer_identifier'],
      ),
      signatureMethod: _requiredText(
        map['signature_method'],
      ),
      signatureEvidence: _jsonMap(
        map['signature_evidence'],
      ),
      declarationText: _optionalText(
        map['declaration_text'],
      ),
      witnessProfileId: _optionalText(
        map['witness_profile_id'],
      ),
      witnessName: _optionalText(
        map['witness_name'],
      ),
      sourceDeviceId: _optionalText(
        map['source_device_id'],
      ),
      signedAt: _dateTimeOrNull(
        map['signed_at'],
      ),
      isValid: _boolOr(
        map['is_valid'],
        true,
      ),
      revokedAt: _dateTimeOrNull(
        map['revoked_at'],
      ),
      revokedBy: _optionalText(
        map['revoked_by'],
      ),
      revocationReason: _optionalText(
        map['revocation_reason'],
      ),
    );
  }

  final String id;
  final String hospitalId;
  final String instanceId;

  final String? signerProfileId;
  final String signerRole;
  final String signerName;
  final String? signerIdentifier;

  final String signatureMethod;
  final Map<String, dynamic> signatureEvidence;

  final String? declarationText;

  final String? witnessProfileId;
  final String? witnessName;

  final String? sourceDeviceId;
  final DateTime? signedAt;

  final bool isValid;

  final DateTime? revokedAt;
  final String? revokedBy;
  final String? revocationReason;
}

// =============================================================================
// ATTACHMENT MODEL
// =============================================================================

class HospitalFormAttachmentRecord {
  const HospitalFormAttachmentRecord({
    required this.id,
    required this.hospitalId,
    required this.instanceId,
    required this.attachmentType,
    required this.fileName,
    required this.storageBucket,
    required this.storagePath,
    required this.documentClassification,
    required this.isActive,
    this.mimeType,
    this.fileSizeBytes,
    this.checksumSha256,
    this.description,
    this.uploadedBy,
    this.uploadedAt,
    this.deactivatedAt,
    this.deactivatedBy,
    this.deactivationReason,
  });

  factory HospitalFormAttachmentRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormAttachmentRecord(
      id: _requiredText(
        map['id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      instanceId: _requiredText(
        map['instance_id'],
      ),
      attachmentType: _textOr(
        map['attachment_type'],
        'supporting_document',
      ),
      fileName: _requiredText(
        map['file_name'],
      ),
      storageBucket: _requiredText(
        map['storage_bucket'],
      ),
      storagePath: _requiredText(
        map['storage_path'],
      ),
      mimeType: _optionalText(
        map['mime_type'],
      ),
      fileSizeBytes: _intOrNull(
        map['file_size_bytes'],
      ),
      checksumSha256: _optionalText(
        map['checksum_sha256'],
      ),
      description: _optionalText(
        map['description'],
      ),
      documentClassification: _textOr(
        map['document_classification'],
        'clinical',
      ),
      uploadedBy: _optionalText(
        map['uploaded_by'],
      ),
      uploadedAt: _dateTimeOrNull(
        map['uploaded_at'],
      ),
      isActive: _boolOr(
        map['is_active'],
        true,
      ),
      deactivatedAt: _dateTimeOrNull(
        map['deactivated_at'],
      ),
      deactivatedBy: _optionalText(
        map['deactivated_by'],
      ),
      deactivationReason: _optionalText(
        map['deactivation_reason'],
      ),
    );
  }

  final String id;
  final String hospitalId;
  final String instanceId;

  final String attachmentType;
  final String fileName;

  final String storageBucket;
  final String storagePath;

  final String? mimeType;
  final int? fileSizeBytes;
  final String? checksumSha256;
  final String? description;

  final String documentClassification;

  final String? uploadedBy;
  final DateTime? uploadedAt;

  final bool isActive;

  final DateTime? deactivatedAt;
  final String? deactivatedBy;
  final String? deactivationReason;
}

// =============================================================================
// AUDIT EVENT MODEL
// =============================================================================

class HospitalFormAuditEventRecord {
  const HospitalFormAuditEventRecord({
    required this.id,
    required this.hospitalId,
    required this.eventType,
    required this.metadata,
    this.templateId,
    this.instanceId,
    this.patientId,
    this.eventKey,
    this.actorProfileId,
    this.actorRole,
    this.reason,
    this.sourceDeviceId,
    this.occurredAt,
  });

  factory HospitalFormAuditEventRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalFormAuditEventRecord(
      id: _requiredText(
        map['id'],
      ),
      hospitalId: _requiredText(
        map['hospital_id'],
      ),
      templateId: _optionalText(
        map['template_id'],
      ),
      instanceId: _optionalText(
        map['instance_id'],
      ),
      patientId: _optionalText(
        map['patient_id'],
      ),
      eventType: _requiredText(
        map['event_type'],
      ),
      eventKey: _optionalText(
        map['event_key'],
      ),
      actorProfileId: _optionalText(
        map['actor_profile_id'],
      ),
      actorRole: _optionalText(
        map['actor_role'],
      ),
      reason: _optionalText(
        map['reason'],
      ),
      metadata: _jsonMap(
        map['metadata'],
      ),
      sourceDeviceId: _optionalText(
        map['source_device_id'],
      ),
      occurredAt: _dateTimeOrNull(
        map['occurred_at'],
      ),
    );
  }

  final String id;
  final String hospitalId;

  final String? templateId;
  final String? instanceId;
  final String? patientId;

  final String eventType;
  final String? eventKey;

  final String? actorProfileId;
  final String? actorRole;

  final String? reason;
  final Map<String, dynamic> metadata;

  final String? sourceDeviceId;
  final DateTime? occurredAt;

  String get displayEventType {
    return _humanize(
      eventType,
    );
  }
}

// =============================================================================
// INSTANCE WORKSPACE
// =============================================================================

class HospitalFormInstanceWorkspace {
  const HospitalFormInstanceWorkspace({
    required this.instance,
    required this.definition,
    required this.values,
    required this.signatures,
    required this.attachments,
  });

  final HospitalFormInstanceRecord instance;
  final HospitalFormTemplateDefinition definition;

  final List<HospitalFormValueRecord> values;
  final List<HospitalFormSignatureRecord> signatures;

  final List<HospitalFormAttachmentRecord> attachments;

  Map<String, Object?> get answers {
    return Map.unmodifiable({
      for (final value in values)
        if (value.isCurrent) value.fieldKey: value.value,
    });
  }

  HospitalFormValueRecord? valueFor(
    String fieldKey,
  ) {
    for (final value in values) {
      if (value.fieldKey == fieldKey && value.isCurrent) {
        return value;
      }
    }

    return null;
  }

  Object? answerFor(
    String fieldKey,
  ) {
    return valueFor(
      fieldKey,
    )?.value;
  }

  bool get hasSignatures {
    return signatures.any(
      (signature) => signature.isValid,
    );
  }

  bool get hasAttachments {
    return attachments.any(
      (attachment) => attachment.isActive,
    );
  }

  Map<String, String> validateCurrentAnswers() {
    return definition.validateAnswers(
      answers,
    );
  }
}

// =============================================================================
// EXCEPTION
// =============================================================================

class HospitalFormEngineException implements Exception {
  const HospitalFormEngineException(
    this.message,
  );

  final String message;

  @override
  String toString() {
    return message;
  }
}

// =============================================================================
// MODEL PARSING HELPERS
// =============================================================================

String _requiredText(
  dynamic value,
) {
  final text = value?.toString().trim() ?? '';

  return text;
}

String? _optionalText(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();

  if (text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }

  return text;
}

String _textOr(
  dynamic value,
  String fallback,
) {
  return _optionalText(value) ?? fallback;
}

bool _boolOr(
  dynamic value,
  bool fallback,
) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final text = value?.toString().trim().toLowerCase();

  if (text == 'true' || text == '1' || text == 'yes') {
    return true;
  }

  if (text == 'false' || text == '0' || text == 'no') {
    return false;
  }

  return fallback;
}

int _intOr(
  dynamic value,
  int fallback,
) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      fallback;
}

int? _intOrNull(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
    value.toString(),
  );
}

num? _numOrNull(
  dynamic value,
) {
  if (value is num) {
    return value;
  }

  if (value == null) {
    return null;
  }

  return num.tryParse(
    value.toString(),
  );
}

DateTime? _dateTimeOrNull(
  dynamic value,
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

Map<String, dynamic> _jsonMap(
  dynamic value,
) {
  if (value is Map<String, dynamic>) {
    return Map.unmodifiable(
      value,
    );
  }

  if (value is Map) {
    return Map.unmodifiable(
      Map<String, dynamic>.from(
        value,
      ),
    );
  }

  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);

      if (decoded is Map) {
        return Map.unmodifiable(
          Map<String, dynamic>.from(
            decoded,
          ),
        );
      }
    } catch (_) {
      return const {};
    }
  }

  return const {};
}

List<dynamic> _jsonList(
  dynamic value,
) {
  if (value is List) {
    return List.unmodifiable(
      value,
    );
  }

  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);

      if (decoded is List) {
        return List.unmodifiable(
          decoded,
        );
      }
    } catch (_) {
      return const [];
    }
  }

  return const [];
}

bool _valuesEqual(
  Object? first,
  Object? second,
) {
  if (first == second) {
    return true;
  }

  if (first == null || second == null) {
    return false;
  }

  if (first is num && second is num) {
    return first == second;
  }

  return first.toString().trim().toLowerCase() ==
      second.toString().trim().toLowerCase();
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
        RegExp(r'[_-]+'),
        ' ',
      )
      .replaceAll(
        RegExp(r'\s+'),
        ' ',
      );

  if (clean.isEmpty) {
    return '';
  }

  return clean.split(' ').map(
    (word) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    },
  ).join(' ');
}
