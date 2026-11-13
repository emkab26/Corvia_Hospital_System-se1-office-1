import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ControlledFormService {
  ControlledFormService({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  static const String bucketId = 'controlled-hospital-forms';

  final SupabaseClient _client;

  // ==========================================================
  // REGISTRY
  // ==========================================================

  Future<List<ControlledFormRegistryRecord>> loadRegistry({
    required String hospitalId,
  }) async {
    try {
      final response = await _client
          .from('hospital_controlled_form_registry')
          .select()
          .eq('hospital_id', hospitalId)
          .order('official_form_name');

      return (response as List)
          .map(
            (row) => ControlledFormRegistryRecord.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (error) {
      throw ControlledFormException(
        'Failed to load controlled-form registry.',
        error,
      );
    }
  }

  Future<ControlledFormRegistryRecord?> loadRegistryItem({
    required String registryId,
  }) async {
    try {
      final response = await _client
          .from('hospital_controlled_form_registry')
          .select()
          .eq('id', registryId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return ControlledFormRegistryRecord.fromMap(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      throw ControlledFormException(
        'Failed to load controlled-form registry item.',
        error,
      );
    }
  }

  // ==========================================================
  // VERSIONS
  // ==========================================================

  Future<List<ControlledFormVersionRecord>> loadVersions({
    required String registryId,
  }) async {
    try {
      final response = await _client
          .from('hospital_controlled_form_versions')
          .select()
          .eq('registry_id', registryId)
          .order(
            'version_number',
            ascending: false,
          );

      return (response as List)
          .map(
            (row) => ControlledFormVersionRecord.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (error) {
      throw ControlledFormException(
        'Failed to load controlled-form versions.',
        error,
      );
    }
  }

  Future<List<ControlledFormVersionRecord>> loadHospitalVersions({
    required String hospitalId,
  }) async {
    try {
      final response = await _client
          .from('hospital_controlled_form_versions')
          .select()
          .eq('hospital_id', hospitalId)
          .order(
            'created_at',
            ascending: false,
          );

      return (response as List)
          .map(
            (row) => ControlledFormVersionRecord.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (error) {
      throw ControlledFormException(
        'Failed to load hospital controlled-form versions.',
        error,
      );
    }
  }

  Future<ControlledFormVersionRecord?> loadVersion({
    required String versionId,
  }) async {
    try {
      final response = await _client
          .from('hospital_controlled_form_versions')
          .select()
          .eq('id', versionId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return ControlledFormVersionRecord.fromMap(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      throw ControlledFormException(
        'Failed to load controlled-form version.',
        error,
      );
    }
  }

  // ==========================================================
  // PREPARE UPLOAD
  // ==========================================================

  Future<ControlledFormPreparedUpload> prepareUpload({
    required String registryId,
    required String versionLabel,
    required String originalFileName,
    String? officialFormNumber,
    String? officialVersionReference,
    String? officialRevisionReference,
    DateTime? effectiveOn,
    String? notes,
  }) async {
    try {
      final response = await _client.rpc(
        'corvia_controlled_prepare_upload',
        params: {
          'p_registry_id': registryId,
          'p_version_label': versionLabel.trim(),
          'p_original_file_name': originalFileName.trim(),
          'p_official_form_number': _emptyToNull(
            officialFormNumber,
          ),
          'p_official_version_reference': _emptyToNull(
            officialVersionReference,
          ),
          'p_official_revision_reference': _emptyToNull(
            officialRevisionReference,
          ),
          'p_effective_on': effectiveOn == null ? null : _dateOnly(effectiveOn),
          'p_notes': _emptyToNull(notes),
        },
      );

      return ControlledFormPreparedUpload.fromMap(
        _responseMap(response),
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not prepare the official form upload.',
        error,
      );
    }
  }

  // ==========================================================
  // COMPLETE PDF UPLOAD FLOW
  // ==========================================================

  Future<ControlledFormUploadResult> uploadOfficialPdf({
    required String registryId,
    required String versionLabel,
    required String originalFileName,
    required Uint8List bytes,
    String? officialFormNumber,
    String? officialVersionReference,
    String? officialRevisionReference,
    DateTime? effectiveOn,
    String? notes,
  }) async {
    _validatePdf(
      fileName: originalFileName,
      bytes: bytes,
    );

    if (bytes.length > 26214400) {
      throw const ControlledFormException(
        'The PDF is larger than the 25 MB controlled-form limit.',
      );
    }

    final prepared = await prepareUpload(
      registryId: registryId,
      versionLabel: versionLabel,
      originalFileName: originalFileName,
      officialFormNumber: officialFormNumber,
      officialVersionReference: officialVersionReference,
      officialRevisionReference: officialRevisionReference,
      effectiveOn: effectiveOn,
      notes: notes,
    );

    final sha256Value = sha256.convert(bytes).toString();

    try {
      await _client.storage.from(prepared.bucketId).uploadBinary(
            prepared.storagePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );
    } catch (error) {
      throw ControlledFormException(
        'The controlled PDF could not be uploaded to secure Storage.',
        error,
      );
    }

    try {
      final response = await _client.rpc(
        'corvia_controlled_finalize_upload',
        params: {
          'p_version_id': prepared.controlledVersionId,
          'p_storage_path': prepared.storagePath,
          'p_sha256': sha256Value,
          'p_file_size_bytes': bytes.length,
          'p_mime_type': 'application/pdf',
        },
      );

      final result = ControlledFormUploadResult.fromMap(
        _responseMap(response),
      );

      return result.copyWith(
        versionNumber: prepared.versionNumber,
        versionLabel: prepared.versionLabel,
        fileName: prepared.fileName,
      );
    } catch (error) {
      throw ControlledFormException(
        'The PDF was uploaded, but Corvia could not finalise the '
        'controlled master record. Do not upload another copy yet.',
        error,
      );
    }
  }

  // ==========================================================
  // UPLOAD STATUS
  // ==========================================================

  Future<ControlledFormUploadStatus> loadUploadStatus({
    required String versionId,
  }) async {
    try {
      final response = await _client.rpc(
        'corvia_controlled_upload_status',
        params: {
          'p_version_id': versionId,
        },
      );

      return ControlledFormUploadStatus.fromMap(
        _responseMap(response),
      );
    } catch (error) {
      throw ControlledFormException(
        'Failed to load controlled-form upload status.',
        error,
      );
    }
  }

  // ==========================================================
  // REVIEW GATES
  // ==========================================================

  Future<void> approveReviewGate({
    required String versionId,
    required ControlledFormReviewType reviewType,
    String? notes,
  }) async {
    try {
      await _client.rpc(
        'corvia_controlled_review_version',
        params: {
          'p_version_id': versionId,
          'p_review_type': reviewType.databaseValue,
          'p_decision': 'approved',
          'p_notes': _emptyToNull(notes),
        },
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not approve ${reviewType.displayName}.',
        error,
      );
    }
  }

  Future<void> rejectReviewGate({
    required String versionId,
    required ControlledFormReviewType reviewType,
    required String reason,
  }) async {
    final cleanReason = reason.trim();

    if (cleanReason.isEmpty) {
      throw const ControlledFormException(
        'A rejection reason is required.',
      );
    }

    try {
      await _client.rpc(
        'corvia_controlled_review_version',
        params: {
          'p_version_id': versionId,
          'p_review_type': reviewType.databaseValue,
          'p_decision': 'rejected',
          'p_notes': cleanReason,
        },
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not reject ${reviewType.displayName}.',
        error,
      );
    }
  }

  // ==========================================================
  // PRODUCTION APPROVAL
  // ==========================================================

  Future<void> approveForProduction({
    required String versionId,
    String? notes,
  }) async {
    try {
      await _client.rpc(
        'corvia_controlled_approve_version',
        params: {
          'p_version_id': versionId,
          'p_notes': _emptyToNull(notes),
        },
      );
    } catch (error) {
      throw ControlledFormException(
        'Production approval failed.',
        error,
      );
    }
  }

  // ==========================================================
  // RETIRE VERSION
  // ==========================================================

  Future<void> retireVersion({
    required String versionId,
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'corvia_controlled_retire_version',
        params: {
          'p_version_id': versionId,
          'p_reason': _emptyToNull(reason),
        },
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not retire the controlled-form version.',
        error,
      );
    }
  }

  // ==========================================================
  // AUDIT EVENTS
  // ==========================================================

  Future<List<ControlledFormApprovalEvent>> loadApprovalEvents({
    required String versionId,
  }) async {
    try {
      final response = await _client
          .from('hospital_controlled_form_approval_events')
          .select()
          .eq(
            'controlled_version_id',
            versionId,
          )
          .order(
            'created_at',
            ascending: false,
          );

      return (response as List)
          .map(
            (row) => ControlledFormApprovalEvent.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (error) {
      throw ControlledFormException(
        'Failed to load approval history.',
        error,
      );
    }
  }

  // ==========================================================
  // DOWNLOAD EXACT MASTER
  // ==========================================================

  Future<Uint8List> downloadOfficialPdf({
    required ControlledFormVersionRecord version,
  }) async {
    final path = version.storagePath;

    if (path == null || path.trim().isEmpty) {
      throw const ControlledFormException(
        'This controlled version has no uploaded PDF.',
      );
    }

    try {
      return await _client.storage
          .from(
            version.storageBucket ?? bucketId,
          )
          .download(path);
    } catch (error) {
      throw ControlledFormException(
        'Could not download the controlled master PDF.',
        error,
      );
    }
  }

  // ==========================================================
  // DASHBOARD STATS
  // ==========================================================

  Future<ControlledFormDashboardStats> loadDashboardStats({
    required String hospitalId,
  }) async {
    try {
      final response = await _client.rpc(
        'corvia_controlled_form_dashboard_stats',
        params: {
          'p_hospital_id': hospitalId,
        },
      );

      return ControlledFormDashboardStats.fromMap(
        _responseMap(response),
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not load controlled-form dashboard statistics.',
        error,
      );
    }
  }

  // ==========================================================
  // CONTROLLED PDF RENDER PROFILES
  // ==========================================================

  Future<List<ControlledFormRenderProfile>> loadRenderProfiles({
    required String controlledVersionId,
  }) async {
    final cleanVersionId = controlledVersionId.trim();

    if (cleanVersionId.isEmpty) {
      throw const ControlledFormException(
        'A controlled master version is required.',
      );
    }

    try {
      final response = await _client
          .from('hospital_controlled_form_render_profiles')
          .select()
          .eq(
            'controlled_version_id',
            cleanVersionId,
          )
          .order(
            'mapping_revision',
            ascending: false,
          );

      return (response as List)
          .map(
            (row) => ControlledFormRenderProfile.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (error) {
      throw ControlledFormException(
        'Could not load controlled PDF render profiles.',
        error,
      );
    }
  }

  Future<ControlledFormRenderProfile?> loadRenderProfile({
    required String renderProfileId,
  }) async {
    final cleanId = renderProfileId.trim();

    if (cleanId.isEmpty) {
      return null;
    }

    try {
      final response = await _client
          .from('hospital_controlled_form_render_profiles')
          .select()
          .eq(
            'id',
            cleanId,
          )
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return ControlledFormRenderProfile.fromMap(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not load the controlled PDF render profile.',
        error,
      );
    }
  }

  Future<ControlledFormRenderProfile?> loadApprovedRenderProfile({
    required String controlledVersionId,
  }) async {
    final cleanVersionId = controlledVersionId.trim();

    if (cleanVersionId.isEmpty) {
      return null;
    }

    try {
      final response = await _client
          .from('hospital_controlled_form_render_profiles')
          .select()
          .eq(
            'controlled_version_id',
            cleanVersionId,
          )
          .eq(
            'status',
            'approved',
          )
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return ControlledFormRenderProfile.fromMap(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not load the approved controlled PDF mapping.',
        error,
      );
    }
  }

  Future<String> createRenderProfile({
    required String controlledVersionId,
    String rendererType = 'pdf_overlay',
    String? notes,
  }) async {
    final cleanVersionId = controlledVersionId.trim();

    if (cleanVersionId.isEmpty) {
      throw const ControlledFormException(
        'A controlled master version is required.',
      );
    }

    final cleanRendererType = rendererType.trim();

    if (cleanRendererType != 'pdf_overlay' && cleanRendererType != 'acroform') {
      throw const ControlledFormException(
        'Renderer type must be pdf_overlay or acroform.',
      );
    }

    try {
      final response = await _client.rpc(
        'corvia_controlled_render_create_profile',
        params: {
          'p_controlled_version_id': cleanVersionId,
          'p_renderer_type': cleanRendererType,
          'p_notes': _emptyToNull(notes),
        },
      );

      final id = _responseString(response);

      if (id.isEmpty) {
        throw const ControlledFormException(
          'Supabase did not return a render profile ID.',
        );
      }

      return id;
    } catch (error) {
      if (error is ControlledFormException) {
        rethrow;
      }

      throw ControlledFormException(
        'Could not create the controlled PDF mapping revision.',
        error,
      );
    }
  }

  Future<void> submitRenderProfileForReview({
    required String renderProfileId,
  }) async {
    final cleanId = renderProfileId.trim();

    if (cleanId.isEmpty) {
      throw const ControlledFormException(
        'A render profile is required.',
      );
    }

    try {
      await _client.rpc(
        'corvia_controlled_render_submit_review',
        params: {
          'p_render_profile_id': cleanId,
        },
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not submit the PDF mapping for review.',
        error,
      );
    }
  }

  Future<void> approveRenderProfile({
    required String renderProfileId,
    String? notes,
  }) async {
    final cleanId = renderProfileId.trim();

    if (cleanId.isEmpty) {
      throw const ControlledFormException(
        'A render profile is required.',
      );
    }

    try {
      await _client.rpc(
        'corvia_controlled_render_approve_profile',
        params: {
          'p_render_profile_id': cleanId,
          'p_notes': _emptyToNull(notes),
        },
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not approve the controlled PDF mapping.',
        error,
      );
    }
  }

  Future<void> retireRenderProfile({
    required String renderProfileId,
    required String reason,
  }) async {
    final cleanId = renderProfileId.trim();
    final cleanReason = reason.trim();

    if (cleanId.isEmpty) {
      throw const ControlledFormException(
        'A render profile is required.',
      );
    }

    if (cleanReason.isEmpty) {
      throw const ControlledFormException(
        'A retirement reason is required.',
      );
    }

    try {
      await _client.rpc(
        'corvia_controlled_render_retire_profile',
        params: {
          'p_render_profile_id': cleanId,
          'p_reason': cleanReason,
        },
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not retire the controlled PDF mapping.',
        error,
      );
    }
  }

  // ==========================================================
  // CONTROLLED PDF RENDER FIELD MAPPINGS
  // ==========================================================

  Future<List<ControlledFormRenderField>> loadRenderFields({
    required String renderProfileId,
  }) async {
    final cleanId = renderProfileId.trim();

    if (cleanId.isEmpty) {
      return [];
    }

    try {
      final response = await _client
          .from('hospital_controlled_form_render_fields')
          .select()
          .eq(
            'render_profile_id',
            cleanId,
          )
          .order(
            'page_number',
            ascending: true,
          );

      final fields = (response as List)
          .map(
            (row) => ControlledFormRenderField.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();

      fields.sort(
        (first, second) {
          final pageCompare = first.pageNumber.compareTo(
            second.pageNumber,
          );

          if (pageCompare != 0) {
            return pageCompare;
          }

          return first.mappingKey.toLowerCase().compareTo(
                second.mappingKey.toLowerCase(),
              );
        },
      );

      return fields;
    } catch (error) {
      throw ControlledFormException(
        'Could not load controlled PDF field mappings.',
        error,
      );
    }
  }

  Future<String> saveRenderField({
    required ControlledFormRenderFieldInput input,
  }) async {
    _validateRenderFieldInput(input);

    try {
      final response = await _client.rpc(
        'corvia_controlled_render_save_field',
        params: {
          'p_render_profile_id': input.renderProfileId.trim(),
          'p_mapping_key': input.mappingKey.trim(),
          'p_label': _emptyToNull(input.label),
          'p_page_number': input.pageNumber,
          'p_source_scope': input.sourceScope.trim(),
          'p_source_key': input.sourceScope == 'static'
              ? null
              : _emptyToNull(input.sourceKey),
          'p_static_value':
              input.sourceScope == 'static' ? input.staticValue ?? '' : null,
          'p_widget_type': input.widgetType.trim(),
          'p_x_points': input.xPoints,
          'p_y_points': input.yPoints,
          'p_width_points': input.widthPoints,
          'p_height_points': input.heightPoints,
          'p_font_size_points': input.fontSizePoints,
          'p_font_name': input.fontName.trim(),
          'p_text_align': input.textAlign.trim(),
          'p_max_lines': input.maxLines,
          'p_allow_wrap': input.allowWrap,
          'p_required_for_render': input.requiredForRender,
          'p_checkbox_true_value': input.checkboxTrueValue,
          'p_checkbox_mark': input.checkboxMark,
          'p_prefix_text': _emptyToNull(input.prefixText),
          'p_suffix_text': _emptyToNull(input.suffixText),
          'p_date_format': input.dateFormat,
          'p_metadata': input.metadata,
        },
      );

      final id = _responseString(response);

      if (id.isEmpty) {
        throw const ControlledFormException(
          'Supabase did not return a render field ID.',
        );
      }

      return id;
    } catch (error) {
      if (error is ControlledFormException) {
        rethrow;
      }

      throw ControlledFormException(
        'Could not save the controlled PDF field mapping.',
        error,
      );
    }
  }

  Future<void> deleteRenderField({
    required String fieldId,
  }) async {
    final cleanId = fieldId.trim();

    if (cleanId.isEmpty) {
      throw const ControlledFormException(
        'A render field ID is required.',
      );
    }

    try {
      await _client.from('hospital_controlled_form_render_fields').delete().eq(
            'id',
            cleanId,
          );
    } catch (error) {
      throw ControlledFormException(
        'Could not delete the controlled PDF field mapping. '
        'Approved mappings cannot be changed.',
        error,
      );
    }
  }

  // ==========================================================
  // CONTROLLED PDF RENDER MANIFEST
  // ==========================================================

  Future<ControlledFormRenderManifest> loadRenderManifest({
    required String controlledVersionId,
  }) async {
    final cleanVersionId = controlledVersionId.trim();

    if (cleanVersionId.isEmpty) {
      throw const ControlledFormException(
        'A controlled master version is required.',
      );
    }

    try {
      final response = await _client.rpc(
        'corvia_controlled_render_manifest',
        params: {
          'p_controlled_version_id': cleanVersionId,
        },
      );

      return ControlledFormRenderManifest.fromMap(
        _responseMap(response),
      );
    } catch (error) {
      throw ControlledFormException(
        'Could not load the controlled PDF render manifest.',
        error,
      );
    }
  }

  // ==========================================================
  // RENDER FIELD INPUT VALIDATION
  // ==========================================================

  static void _validateRenderFieldInput(
    ControlledFormRenderFieldInput input,
  ) {
    if (input.renderProfileId.trim().isEmpty) {
      throw const ControlledFormException(
        'A render profile is required.',
      );
    }

    if (input.mappingKey.trim().isEmpty) {
      throw const ControlledFormException(
        'Mapping key is required.',
      );
    }

    if (input.pageNumber < 1) {
      throw const ControlledFormException(
        'Page number must be at least 1.',
      );
    }

    const sourceScopes = {
      'form_value',
      'patient',
      'admission',
      'instance',
      'signature',
      'static',
    };

    if (!sourceScopes.contains(input.sourceScope.trim())) {
      throw const ControlledFormException(
        'Invalid mapping source.',
      );
    }

    if (input.sourceScope.trim() != 'static' &&
        (input.sourceKey == null || input.sourceKey!.trim().isEmpty)) {
      throw const ControlledFormException(
        'A source key is required for this mapping.',
      );
    }

    if (input.sourceScope.trim() == 'static' && input.staticValue == null) {
      throw const ControlledFormException(
        'A static value is required for a static mapping.',
      );
    }

    const widgetTypes = {
      'text',
      'multiline_text',
      'checkbox',
      'radio',
      'date',
      'signature_text',
    };

    if (!widgetTypes.contains(input.widgetType.trim())) {
      throw const ControlledFormException(
        'Invalid controlled PDF widget type.',
      );
    }

    if (!input.xPoints.isFinite ||
        !input.yPoints.isFinite ||
        input.xPoints < 0 ||
        input.yPoints < 0) {
      throw const ControlledFormException(
        'X and Y coordinates must be valid positive PDF points.',
      );
    }

    if (input.widthPoints != null &&
        (!input.widthPoints!.isFinite || input.widthPoints! <= 0)) {
      throw const ControlledFormException(
        'Mapping width must be greater than zero.',
      );
    }

    if (input.heightPoints != null &&
        (!input.heightPoints!.isFinite || input.heightPoints! <= 0)) {
      throw const ControlledFormException(
        'Mapping height must be greater than zero.',
      );
    }

    if (!input.fontSizePoints.isFinite || input.fontSizePoints <= 0) {
      throw const ControlledFormException(
        'Font size must be greater than zero.',
      );
    }

    if (input.maxLines < 1) {
      throw const ControlledFormException(
        'Max lines must be at least 1.',
      );
    }

    const alignments = {
      'left',
      'center',
      'right',
    };

    if (!alignments.contains(input.textAlign.trim())) {
      throw const ControlledFormException(
        'Text alignment must be left, center or right.',
      );
    }
  }

  // ==========================================================
  // HELPERS
  // ==========================================================

  static void _validatePdf({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (!fileName.toLowerCase().endsWith('.pdf')) {
      throw const ControlledFormException(
        'Only PDF files may be uploaded.',
      );
    }

    if (bytes.isEmpty) {
      throw const ControlledFormException(
        'The selected PDF is empty.',
      );
    }

    if (bytes.length < 5) {
      throw const ControlledFormException(
        'The selected file does not appear to be a valid PDF.',
      );
    }

    final hasPdfHeader = bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;

    if (!hasPdfHeader) {
      throw const ControlledFormException(
        'The selected file does not have a valid PDF header.',
      );
    }
  }

  static Map<String, dynamic> _responseMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(
        value.first as Map,
      );
    }

    throw ControlledFormException(
      'Unexpected response from Supabase: ${value.runtimeType}.',
    );
  }

  static String _responseString(dynamic value) {
    if (value == null) {
      return '';
    }

    if (value is String) {
      return value.trim();
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);

      for (final key in const [
        'id',
        'render_profile_id',
        'field_id',
      ]) {
        final result = map[key]?.toString().trim();

        if (result != null && result.isNotEmpty) {
          return result;
        }
      }
    }

    if (value is List && value.length == 1) {
      return _responseString(value.first);
    }

    return value.toString().trim();
  }

  static String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static String? _emptyToNull(String? value) {
    final cleanValue = value?.trim();

    if (cleanValue == null || cleanValue.isEmpty) {
      return null;
    }

    return cleanValue;
  }
}

// ============================================================
// REVIEW TYPE
// ============================================================

enum ControlledFormReviewType {
  source,
  layout,
  clinical,
  legal,
  privacy,
  records,
  hospital,
}

extension ControlledFormReviewTypeX on ControlledFormReviewType {
  String get databaseValue {
    switch (this) {
      case ControlledFormReviewType.source:
        return 'source';

      case ControlledFormReviewType.layout:
        return 'layout';

      case ControlledFormReviewType.clinical:
        return 'clinical';

      case ControlledFormReviewType.legal:
        return 'legal';

      case ControlledFormReviewType.privacy:
        return 'privacy';

      case ControlledFormReviewType.records:
        return 'records';

      case ControlledFormReviewType.hospital:
        return 'hospital';
    }
  }

  String get displayName {
    switch (this) {
      case ControlledFormReviewType.source:
        return 'Official Source';

      case ControlledFormReviewType.layout:
        return 'Exact Layout';

      case ControlledFormReviewType.clinical:
        return 'Clinical Review';

      case ControlledFormReviewType.legal:
        return 'Legal Review';

      case ControlledFormReviewType.privacy:
        return 'Privacy / POPIA';

      case ControlledFormReviewType.records:
        return 'Records Management';

      case ControlledFormReviewType.hospital:
        return 'Hospital Approval';
    }
  }
}

// ============================================================
// REGISTRY MODEL
// ============================================================

class ControlledFormRegistryRecord {
  const ControlledFormRegistryRecord({
    required this.id,
    required this.hospitalId,
    required this.templateId,
    required this.formCode,
    required this.officialFormName,
    required this.jurisdiction,
    required this.sourceType,
    required this.requiresOfficialLayout,
    required this.requiresExternalSubmission,
    required this.productionStatus,
    required this.productionApproved,
    this.issuingAuthority,
    this.currentControlledVersionId,
    this.notes,
  });

  final String id;
  final String hospitalId;
  final String templateId;
  final String formCode;
  final String officialFormName;

  final String? issuingAuthority;

  final String jurisdiction;
  final String sourceType;

  final bool requiresOfficialLayout;
  final bool requiresExternalSubmission;

  final String productionStatus;
  final bool productionApproved;

  final String? currentControlledVersionId;
  final String? notes;

  factory ControlledFormRegistryRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return ControlledFormRegistryRecord(
      id: map['id']?.toString() ?? '',
      hospitalId: map['hospital_id']?.toString() ?? '',
      templateId: map['template_id']?.toString() ?? '',
      formCode: map['form_code']?.toString() ?? '',
      officialFormName:
          map['official_form_name']?.toString() ?? 'Controlled Form',
      issuingAuthority: map['issuing_authority']?.toString(),
      jurisdiction: map['jurisdiction']?.toString() ?? 'South Africa',
      sourceType: map['source_type']?.toString() ?? 'national',
      requiresOfficialLayout: map['requires_official_layout'] == true,
      requiresExternalSubmission: map['requires_external_submission'] == true,
      productionStatus:
          map['production_status']?.toString() ?? 'pending_official_source',
      productionApproved: map['production_approved'] == true,
      currentControlledVersionId:
          map['current_controlled_version_id']?.toString(),
      notes: map['notes']?.toString(),
    );
  }
}

// ============================================================
// VERSION MODEL
// ============================================================

class ControlledFormVersionRecord {
  const ControlledFormVersionRecord({
    required this.id,
    required this.registryId,
    required this.hospitalId,
    required this.templateId,
    required this.versionNumber,
    required this.versionLabel,
    required this.sourceVerified,
    required this.layoutVerified,
    required this.clinicalReviewed,
    required this.legalReviewed,
    required this.privacyReviewed,
    required this.recordsReviewed,
    required this.hospitalApproved,
    required this.productionApproved,
    required this.approvalStatus,
    this.officialFormNumber,
    this.officialVersionReference,
    this.officialRevisionReference,
    this.effectiveOn,
    this.retiredOn,
    this.sourceDocumentName,
    this.sourceDocumentUrl,
    this.storageBucket,
    this.storagePath,
    this.mimeType,
    this.fileSizeBytes,
    this.sha256,
    this.approvedAt,
    this.rejectionReason,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String registryId;
  final String hospitalId;
  final String templateId;

  final int versionNumber;
  final String versionLabel;

  final String? officialFormNumber;
  final String? officialVersionReference;
  final String? officialRevisionReference;

  final DateTime? effectiveOn;
  final DateTime? retiredOn;

  final String? sourceDocumentName;
  final String? sourceDocumentUrl;

  final String? storageBucket;
  final String? storagePath;
  final String? mimeType;

  final int? fileSizeBytes;
  final String? sha256;

  final bool sourceVerified;
  final bool layoutVerified;
  final bool clinicalReviewed;
  final bool legalReviewed;
  final bool privacyReviewed;
  final bool recordsReviewed;
  final bool hospitalApproved;

  final bool productionApproved;

  final String approvalStatus;

  final DateTime? approvedAt;

  final String? rejectionReason;
  final String? notes;

  final DateTime? createdAt;

  bool get hasUploadedSource {
    return storagePath != null &&
        storagePath!.trim().isNotEmpty &&
        sha256 != null &&
        sha256!.trim().isNotEmpty;
  }

  bool get allReviewGatesApproved {
    return sourceVerified &&
        layoutVerified &&
        clinicalReviewed &&
        legalReviewed &&
        privacyReviewed &&
        recordsReviewed &&
        hospitalApproved;
  }

  int get approvedGateCount {
    var count = 0;

    if (sourceVerified) count++;
    if (layoutVerified) count++;
    if (clinicalReviewed) count++;
    if (legalReviewed) count++;
    if (privacyReviewed) count++;
    if (recordsReviewed) count++;
    if (hospitalApproved) count++;

    return count;
  }

  bool reviewApproved(
    ControlledFormReviewType type,
  ) {
    switch (type) {
      case ControlledFormReviewType.source:
        return sourceVerified;

      case ControlledFormReviewType.layout:
        return layoutVerified;

      case ControlledFormReviewType.clinical:
        return clinicalReviewed;

      case ControlledFormReviewType.legal:
        return legalReviewed;

      case ControlledFormReviewType.privacy:
        return privacyReviewed;

      case ControlledFormReviewType.records:
        return recordsReviewed;

      case ControlledFormReviewType.hospital:
        return hospitalApproved;
    }
  }

  factory ControlledFormVersionRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    return ControlledFormVersionRecord(
      id: map['id']?.toString() ?? '',
      registryId: map['registry_id']?.toString() ?? '',
      hospitalId: map['hospital_id']?.toString() ?? '',
      templateId: map['template_id']?.toString() ?? '',
      versionNumber: _intValue(
        map['version_number'],
      ),
      versionLabel: map['version_label']?.toString() ?? 'Version',
      officialFormNumber: map['official_form_number']?.toString(),
      officialVersionReference: map['official_version_reference']?.toString(),
      officialRevisionReference: map['official_revision_reference']?.toString(),
      effectiveOn: _dateValue(
        map['effective_on'],
      ),
      retiredOn: _dateValue(
        map['retired_on'],
      ),
      sourceDocumentName: map['source_document_name']?.toString(),
      sourceDocumentUrl: map['source_document_url']?.toString(),
      storageBucket: map['storage_bucket']?.toString(),
      storagePath: map['storage_path']?.toString(),
      mimeType: map['mime_type']?.toString(),
      fileSizeBytes: map['file_size_bytes'] == null
          ? null
          : _intValue(
              map['file_size_bytes'],
            ),
      sha256: map['sha256']?.toString(),
      sourceVerified: map['source_verified'] == true,
      layoutVerified: map['layout_verified'] == true,
      clinicalReviewed: map['clinical_reviewed'] == true,
      legalReviewed: map['legal_reviewed'] == true,
      privacyReviewed: map['privacy_reviewed'] == true,
      recordsReviewed: map['records_reviewed'] == true,
      hospitalApproved: map['hospital_approved'] == true,
      productionApproved: map['production_approved'] == true,
      approvalStatus: map['approval_status']?.toString() ?? 'draft',
      approvedAt: _dateValue(map['approved_at']),
      rejectionReason: map['rejection_reason']?.toString(),
      notes: map['notes']?.toString(),
      createdAt: _dateValue(map['created_at']),
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    );
  }
}

// ============================================================
// PREPARED UPLOAD
// ============================================================

class ControlledFormPreparedUpload {
  const ControlledFormPreparedUpload({
    required this.hospitalId,
    required this.registryId,
    required this.controlledVersionId,
    required this.versionNumber,
    required this.versionLabel,
    required this.bucketId,
    required this.storagePath,
    required this.fileName,
    required this.approvalStatus,
    required this.productionApproved,
  });

  final String hospitalId;
  final String registryId;
  final String controlledVersionId;

  final int versionNumber;
  final String versionLabel;

  final String bucketId;
  final String storagePath;
  final String fileName;

  final String approvalStatus;
  final bool productionApproved;

  factory ControlledFormPreparedUpload.fromMap(
    Map<String, dynamic> map,
  ) {
    return ControlledFormPreparedUpload(
      hospitalId: map['hospital_id']?.toString() ?? '',
      registryId: map['registry_id']?.toString() ?? '',
      controlledVersionId: map['controlled_version_id']?.toString() ?? '',
      versionNumber: int.tryParse(
            map['version_number']?.toString() ?? '',
          ) ??
          0,
      versionLabel: map['version_label']?.toString() ?? '',
      bucketId: map['bucket_id']?.toString() ?? ControlledFormService.bucketId,
      storagePath: map['storage_path']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? '',
      approvalStatus: map['approval_status']?.toString() ?? 'draft',
      productionApproved: map['production_approved'] == true,
    );
  }
}

// ============================================================
// UPLOAD RESULT
// ============================================================

class ControlledFormUploadResult {
  const ControlledFormUploadResult({
    required this.registryId,
    required this.controlledVersionId,
    required this.storageBucket,
    required this.storagePath,
    required this.fileSizeBytes,
    required this.sha256,
    required this.approvalStatus,
    required this.productionApproved,
    this.nextStep,
    this.versionNumber,
    this.versionLabel,
    this.fileName,
  });

  final String registryId;
  final String controlledVersionId;

  final String storageBucket;
  final String storagePath;

  final int fileSizeBytes;
  final String sha256;

  final String approvalStatus;
  final bool productionApproved;

  final String? nextStep;

  final int? versionNumber;
  final String? versionLabel;
  final String? fileName;

  ControlledFormUploadResult copyWith({
    int? versionNumber,
    String? versionLabel,
    String? fileName,
  }) {
    return ControlledFormUploadResult(
      registryId: registryId,
      controlledVersionId: controlledVersionId,
      storageBucket: storageBucket,
      storagePath: storagePath,
      fileSizeBytes: fileSizeBytes,
      sha256: sha256,
      approvalStatus: approvalStatus,
      productionApproved: productionApproved,
      nextStep: nextStep,
      versionNumber: versionNumber ?? this.versionNumber,
      versionLabel: versionLabel ?? this.versionLabel,
      fileName: fileName ?? this.fileName,
    );
  }

  factory ControlledFormUploadResult.fromMap(
    Map<String, dynamic> map,
  ) {
    return ControlledFormUploadResult(
      registryId: map['registry_id']?.toString() ?? '',
      controlledVersionId: map['controlled_version_id']?.toString() ?? '',
      storageBucket:
          map['storage_bucket']?.toString() ?? ControlledFormService.bucketId,
      storagePath: map['storage_path']?.toString() ?? '',
      fileSizeBytes: int.tryParse(
            map['file_size_bytes']?.toString() ?? '',
          ) ??
          0,
      sha256: map['sha256']?.toString() ?? '',
      approvalStatus: map['approval_status']?.toString() ?? 'source_uploaded',
      productionApproved: map['production_approved'] == true,
      nextStep: map['next_step']?.toString(),
    );
  }
}

// ============================================================
// UPLOAD STATUS
// ============================================================

class ControlledFormUploadStatus {
  const ControlledFormUploadStatus({
    required this.registryId,
    required this.officialFormName,
    required this.productionStatus,
    required this.controlledVersionId,
    required this.versionNumber,
    required this.versionLabel,
    required this.approvalStatus,
    required this.productionApproved,
    required this.storageObjectExists,
    required this.sourceVerified,
    required this.layoutVerified,
    required this.clinicalReviewed,
    required this.legalReviewed,
    required this.privacyReviewed,
    required this.recordsReviewed,
    required this.hospitalApproved,
    this.storageBucket,
    this.storagePath,
    this.mimeType,
    this.fileSizeBytes,
    this.sha256,
  });

  final String registryId;
  final String officialFormName;
  final String productionStatus;

  final String controlledVersionId;
  final int versionNumber;
  final String versionLabel;

  final String approvalStatus;
  final bool productionApproved;

  final String? storageBucket;
  final String? storagePath;

  final bool storageObjectExists;

  final String? mimeType;
  final int? fileSizeBytes;
  final String? sha256;

  final bool sourceVerified;
  final bool layoutVerified;
  final bool clinicalReviewed;
  final bool legalReviewed;
  final bool privacyReviewed;
  final bool recordsReviewed;
  final bool hospitalApproved;

  factory ControlledFormUploadStatus.fromMap(
    Map<String, dynamic> map,
  ) {
    return ControlledFormUploadStatus(
      registryId: map['registry_id']?.toString() ?? '',
      officialFormName: map['official_form_name']?.toString() ?? '',
      productionStatus: map['production_status']?.toString() ?? '',
      controlledVersionId: map['controlled_version_id']?.toString() ?? '',
      versionNumber: int.tryParse(
            map['version_number']?.toString() ?? '',
          ) ??
          0,
      versionLabel: map['version_label']?.toString() ?? '',
      approvalStatus: map['approval_status']?.toString() ?? '',
      productionApproved: map['production_approved'] == true,
      storageBucket: map['storage_bucket']?.toString(),
      storagePath: map['storage_path']?.toString(),
      storageObjectExists: map['storage_object_exists'] == true,
      mimeType: map['mime_type']?.toString(),
      fileSizeBytes: map['file_size_bytes'] == null
          ? null
          : int.tryParse(
              map['file_size_bytes'].toString(),
            ),
      sha256: map['sha256']?.toString(),
      sourceVerified: map['source_verified'] == true,
      layoutVerified: map['layout_verified'] == true,
      clinicalReviewed: map['clinical_reviewed'] == true,
      legalReviewed: map['legal_reviewed'] == true,
      privacyReviewed: map['privacy_reviewed'] == true,
      recordsReviewed: map['records_reviewed'] == true,
      hospitalApproved: map['hospital_approved'] == true,
    );
  }
}

// ============================================================
// APPROVAL EVENT
// ============================================================

class ControlledFormApprovalEvent {
  const ControlledFormApprovalEvent({
    required this.id,
    required this.eventType,
    required this.createdAt,
    this.reviewType,
    this.decision,
    this.notes,
    this.metadata = const {},
  });

  final String id;
  final String eventType;

  final String? reviewType;
  final String? decision;
  final String? notes;

  final Map<String, dynamic> metadata;

  final DateTime? createdAt;

  factory ControlledFormApprovalEvent.fromMap(
    Map<String, dynamic> map,
  ) {
    final rawMetadata = map['metadata'];

    return ControlledFormApprovalEvent(
      id: map['id']?.toString() ?? '',
      eventType: map['event_type']?.toString() ?? 'event',
      reviewType: map['review_type']?.toString(),
      decision: map['decision']?.toString(),
      notes: map['notes']?.toString(),
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(rawMetadata)
          : const {},
      createdAt: DateTime.tryParse(
        map['created_at']?.toString() ?? '',
      ),
    );
  }
}

// ============================================================
// DASHBOARD STATS
// ============================================================

class ControlledFormDashboardStats {
  const ControlledFormDashboardStats({
    required this.hospitalId,
    required this.controlledForms,
    required this.pending,
    required this.underReview,
    required this.productionApproved,
    required this.rejected,
    required this.retired,
    required this.masterVersions,
  });

  final String hospitalId;

  final int controlledForms;
  final int pending;
  final int underReview;
  final int productionApproved;
  final int rejected;
  final int retired;
  final int masterVersions;

  factory ControlledFormDashboardStats.fromMap(
    Map<String, dynamic> map,
  ) {
    int readInt(String key) {
      return int.tryParse(
            map[key]?.toString() ?? '',
          ) ??
          0;
    }

    return ControlledFormDashboardStats(
      hospitalId: map['hospital_id']?.toString() ?? '',
      controlledForms: readInt('controlled_forms'),
      pending: readInt('pending'),
      underReview: readInt('under_review'),
      productionApproved: readInt('production_approved'),
      rejected: readInt('rejected'),
      retired: readInt('retired'),
      masterVersions: readInt('master_versions'),
    );
  }
}

// ============================================================
// CONTROLLED PDF RENDER PROFILE
// ============================================================

class ControlledFormRenderProfile {
  const ControlledFormRenderProfile({
    required this.id,
    required this.hospitalId,
    required this.registryId,
    required this.controlledVersionId,
    required this.templateId,
    required this.mappingRevision,
    required this.status,
    required this.rendererType,
    required this.coordinateOrigin,
    required this.pageUnit,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.approvedBy,
    this.approvedAt,
    this.retiredBy,
    this.retiredAt,
    this.retirementReason,
  });

  final String id;
  final String hospitalId;
  final String registryId;
  final String controlledVersionId;
  final String templateId;

  final int mappingRevision;

  final String status;
  final String rendererType;

  final String coordinateOrigin;
  final String pageUnit;

  final String? notes;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? approvedBy;
  final DateTime? approvedAt;

  final String? retiredBy;
  final DateTime? retiredAt;
  final String? retirementReason;

  bool get isDraft => status == 'draft';

  bool get isUnderReview => status == 'review';

  bool get isApproved => status == 'approved';

  bool get isRetired => status == 'retired';

  bool get canEdit => status == 'draft';

  bool get canSubmit => status == 'draft';

  bool get canApprove => status == 'review';

  bool get canRetire => status == 'approved';

  factory ControlledFormRenderProfile.fromMap(
    Map<String, dynamic> map,
  ) {
    return ControlledFormRenderProfile(
      id: _renderString(
        map['id'],
      ),
      hospitalId: _renderString(
        map['hospital_id'],
      ),
      registryId: _renderString(
        map['registry_id'],
      ),
      controlledVersionId: _renderString(
        map['controlled_version_id'],
      ),
      templateId: _renderString(
        map['template_id'],
      ),
      mappingRevision: _renderInt(
        map['mapping_revision'],
      ),
      status: _renderString(
        map['status'],
        fallback: 'draft',
      ),
      rendererType: _renderString(
        map['renderer_type'],
        fallback: 'pdf_overlay',
      ),
      coordinateOrigin: _renderString(
        map['coordinate_origin'],
        fallback: 'bottom_left',
      ),
      pageUnit: _renderString(
        map['page_unit'],
        fallback: 'points',
      ),
      notes: _renderNullableString(
        map['notes'],
      ),
      createdBy: _renderNullableString(
        map['created_by'],
      ),
      createdAt: _renderDate(
        map['created_at'],
      ),
      updatedAt: _renderDate(
        map['updated_at'],
      ),
      approvedBy: _renderNullableString(
        map['approved_by'],
      ),
      approvedAt: _renderDate(
        map['approved_at'],
      ),
      retiredBy: _renderNullableString(
        map['retired_by'],
      ),
      retiredAt: _renderDate(
        map['retired_at'],
      ),
      retirementReason: _renderNullableString(
        map['retirement_reason'],
      ),
    );
  }
}

// ============================================================
// CONTROLLED PDF RENDER FIELD
// ============================================================

class ControlledFormRenderField {
  const ControlledFormRenderField({
    required this.id,
    required this.renderProfileId,
    required this.mappingKey,
    required this.pageNumber,
    required this.sourceScope,
    required this.widgetType,
    required this.xPoints,
    required this.yPoints,
    required this.fontSizePoints,
    required this.fontName,
    required this.textAlign,
    required this.maxLines,
    required this.allowWrap,
    required this.requiredForRender,
    required this.checkboxTrueValue,
    required this.checkboxMark,
    required this.dateFormat,
    required this.metadata,
    this.label,
    this.sourceKey,
    this.staticValue,
    this.widthPoints,
    this.heightPoints,
    this.prefixText,
    this.suffixText,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String renderProfileId;

  final String mappingKey;
  final String? label;

  final int pageNumber;

  final String sourceScope;
  final String? sourceKey;
  final String? staticValue;

  final String widgetType;

  final double xPoints;
  final double yPoints;

  final double? widthPoints;
  final double? heightPoints;

  final double fontSizePoints;
  final String fontName;

  final String textAlign;

  final int maxLines;
  final bool allowWrap;

  final bool requiredForRender;

  final String checkboxTrueValue;
  final String checkboxMark;

  final String? prefixText;
  final String? suffixText;

  final String dateFormat;

  final Map<String, dynamic> metadata;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayLabel {
    final cleanLabel = label?.trim();

    if (cleanLabel != null && cleanLabel.isNotEmpty) {
      return cleanLabel;
    }

    return mappingKey
        .replaceAll('_', ' ')
        .split(' ')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
          (word) => word.length == 1
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}'
                  '${word.substring(1)}',
        )
        .join(' ');
  }

  String get sourceDisplay {
    if (sourceScope == 'static') {
      return staticValue ?? '';
    }

    return sourceKey ?? '';
  }

  factory ControlledFormRenderField.fromMap(
    Map<String, dynamic> map,
  ) {
    final rawMetadata = map['metadata'];

    return ControlledFormRenderField(
      id: _renderString(
        map['id'],
      ),
      renderProfileId: _renderString(
        map['render_profile_id'],
      ),
      mappingKey: _renderString(
        map['mapping_key'],
      ),
      label: _renderNullableString(
        map['label'],
      ),
      pageNumber: _renderInt(
        map['page_number'],
        fallback: 1,
      ),
      sourceScope: _renderString(
        map['source_scope'],
        fallback: 'form_value',
      ),
      sourceKey: _renderNullableString(
        map['source_key'],
      ),
      staticValue: _renderNullableString(
        map['static_value'],
      ),
      widgetType: _renderString(
        map['widget_type'],
        fallback: 'text',
      ),
      xPoints: _renderDouble(
        map['x_points'],
      ),
      yPoints: _renderDouble(
        map['y_points'],
      ),
      widthPoints: _renderNullableDouble(
        map['width_points'],
      ),
      heightPoints: _renderNullableDouble(
        map['height_points'],
      ),
      fontSizePoints: _renderDouble(
        map['font_size_points'],
        fallback: 9,
      ),
      fontName: _renderString(
        map['font_name'],
        fallback: 'Helvetica',
      ),
      textAlign: _renderString(
        map['text_align'],
        fallback: 'left',
      ),
      maxLines: _renderInt(
        map['max_lines'],
        fallback: 1,
      ),
      allowWrap: _renderBool(
        map['allow_wrap'],
      ),
      requiredForRender: _renderBool(
        map['required_for_render'],
      ),
      checkboxTrueValue: _renderString(
        map['checkbox_true_value'],
        fallback: 'true',
      ),
      checkboxMark: _renderString(
        map['checkbox_mark'],
        fallback: 'X',
      ),
      prefixText: _renderNullableString(
        map['prefix_text'],
      ),
      suffixText: _renderNullableString(
        map['suffix_text'],
      ),
      dateFormat: _renderString(
        map['date_format'],
        fallback: 'dd/MM/yyyy',
      ),
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(
              rawMetadata,
            )
          : const {},
      createdBy: _renderNullableString(
        map['created_by'],
      ),
      createdAt: _renderDate(
        map['created_at'],
      ),
      updatedAt: _renderDate(
        map['updated_at'],
      ),
    );
  }
}

// ============================================================
// CONTROLLED PDF RENDER FIELD INPUT
// ============================================================

class ControlledFormRenderFieldInput {
  const ControlledFormRenderFieldInput({
    required this.renderProfileId,
    required this.mappingKey,
    required this.pageNumber,
    required this.sourceScope,
    required this.widgetType,
    required this.xPoints,
    required this.yPoints,
    this.label,
    this.sourceKey,
    this.staticValue,
    this.widthPoints,
    this.heightPoints,
    this.fontSizePoints = 9,
    this.fontName = 'Helvetica',
    this.textAlign = 'left',
    this.maxLines = 1,
    this.allowWrap = false,
    this.requiredForRender = false,
    this.checkboxTrueValue = 'true',
    this.checkboxMark = 'X',
    this.prefixText,
    this.suffixText,
    this.dateFormat = 'dd/MM/yyyy',
    this.metadata = const {},
  });

  final String renderProfileId;

  final String mappingKey;
  final String? label;

  final int pageNumber;

  final String sourceScope;
  final String? sourceKey;
  final String? staticValue;

  final String widgetType;

  final double xPoints;
  final double yPoints;

  final double? widthPoints;
  final double? heightPoints;

  final double fontSizePoints;
  final String fontName;

  final String textAlign;

  final int maxLines;
  final bool allowWrap;

  final bool requiredForRender;

  final String checkboxTrueValue;
  final String checkboxMark;

  final String? prefixText;
  final String? suffixText;

  final String dateFormat;

  final Map<String, dynamic> metadata;

  factory ControlledFormRenderFieldInput.fromExisting(
    ControlledFormRenderField field,
  ) {
    return ControlledFormRenderFieldInput(
      renderProfileId: field.renderProfileId,
      mappingKey: field.mappingKey,
      label: field.label,
      pageNumber: field.pageNumber,
      sourceScope: field.sourceScope,
      sourceKey: field.sourceKey,
      staticValue: field.staticValue,
      widgetType: field.widgetType,
      xPoints: field.xPoints,
      yPoints: field.yPoints,
      widthPoints: field.widthPoints,
      heightPoints: field.heightPoints,
      fontSizePoints: field.fontSizePoints,
      fontName: field.fontName,
      textAlign: field.textAlign,
      maxLines: field.maxLines,
      allowWrap: field.allowWrap,
      requiredForRender: field.requiredForRender,
      checkboxTrueValue: field.checkboxTrueValue,
      checkboxMark: field.checkboxMark,
      prefixText: field.prefixText,
      suffixText: field.suffixText,
      dateFormat: field.dateFormat,
      metadata: field.metadata,
    );
  }
}

// ============================================================
// CONTROLLED PDF RENDER MANIFEST
// ============================================================

class ControlledFormRenderManifest {
  const ControlledFormRenderManifest({
    required this.mappingAvailable,
    required this.fields,
    this.renderProfileId,
    this.mappingRevision,
    this.rendererType,
    this.coordinateOrigin,
    this.pageUnit,
    this.hospitalId,
    this.registryId,
    this.templateId,
    this.controlledVersionId,
    this.sourceDocumentName,
    this.storageBucket,
    this.storagePath,
    this.masterSha256,
  });

  final bool mappingAvailable;

  final String? renderProfileId;
  final int? mappingRevision;

  final String? rendererType;
  final String? coordinateOrigin;
  final String? pageUnit;

  final String? hospitalId;
  final String? registryId;
  final String? templateId;
  final String? controlledVersionId;

  final String? sourceDocumentName;

  final String? storageBucket;
  final String? storagePath;

  final String? masterSha256;

  final List<ControlledFormRenderManifestField> fields;

  factory ControlledFormRenderManifest.fromMap(
    Map<String, dynamic> map,
  ) {
    final rawFields = map['fields'];

    final fields = <ControlledFormRenderManifestField>[];

    if (rawFields is List) {
      for (final rawField in rawFields) {
        if (rawField is Map) {
          fields.add(
            ControlledFormRenderManifestField.fromMap(
              Map<String, dynamic>.from(
                rawField,
              ),
            ),
          );
        }
      }
    }

    return ControlledFormRenderManifest(
      mappingAvailable: _renderBool(
        map['mapping_available'],
      ),
      renderProfileId: _renderNullableString(
        map['render_profile_id'],
      ),
      mappingRevision: map['mapping_revision'] == null
          ? null
          : _renderInt(
              map['mapping_revision'],
            ),
      rendererType: _renderNullableString(
        map['renderer_type'],
      ),
      coordinateOrigin: _renderNullableString(
        map['coordinate_origin'],
      ),
      pageUnit: _renderNullableString(
        map['page_unit'],
      ),
      hospitalId: _renderNullableString(
        map['hospital_id'],
      ),
      registryId: _renderNullableString(
        map['registry_id'],
      ),
      templateId: _renderNullableString(
        map['template_id'],
      ),
      controlledVersionId: _renderNullableString(
        map['controlled_version_id'],
      ),
      sourceDocumentName: _renderNullableString(
        map['source_document_name'],
      ),
      storageBucket: _renderNullableString(
        map['storage_bucket'],
      ),
      storagePath: _renderNullableString(
        map['storage_path'],
      ),
      masterSha256: _renderNullableString(
        map['master_sha256'],
      ),
      fields: fields,
    );
  }
}

// ============================================================
// CONTROLLED PDF RENDER MANIFEST FIELD
// ============================================================

class ControlledFormRenderManifestField {
  const ControlledFormRenderManifestField({
    required this.mappingKey,
    required this.pageNumber,
    required this.sourceScope,
    required this.widgetType,
    required this.xPoints,
    required this.yPoints,
    required this.fontSizePoints,
    required this.fontName,
    required this.textAlign,
    required this.maxLines,
    required this.allowWrap,
    required this.requiredForRender,
    required this.checkboxTrueValue,
    required this.checkboxMark,
    required this.dateFormat,
    required this.metadata,
    this.label,
    this.sourceKey,
    this.staticValue,
    this.widthPoints,
    this.heightPoints,
    this.prefixText,
    this.suffixText,
  });

  final String mappingKey;
  final String? label;

  final int pageNumber;

  final String sourceScope;
  final String? sourceKey;
  final String? staticValue;

  final String widgetType;

  final double xPoints;
  final double yPoints;

  final double? widthPoints;
  final double? heightPoints;

  final double fontSizePoints;
  final String fontName;

  final String textAlign;

  final int maxLines;
  final bool allowWrap;

  final bool requiredForRender;

  final String checkboxTrueValue;
  final String checkboxMark;

  final String? prefixText;
  final String? suffixText;

  final String dateFormat;

  final Map<String, dynamic> metadata;

  factory ControlledFormRenderManifestField.fromMap(
    Map<String, dynamic> map,
  ) {
    final rawMetadata = map['metadata'];

    return ControlledFormRenderManifestField(
      mappingKey: _renderString(
        map['mapping_key'],
      ),
      label: _renderNullableString(
        map['label'],
      ),
      pageNumber: _renderInt(
        map['page_number'],
        fallback: 1,
      ),
      sourceScope: _renderString(
        map['source_scope'],
        fallback: 'form_value',
      ),
      sourceKey: _renderNullableString(
        map['source_key'],
      ),
      staticValue: _renderNullableString(
        map['static_value'],
      ),
      widgetType: _renderString(
        map['widget_type'],
        fallback: 'text',
      ),
      xPoints: _renderDouble(
        map['x_points'],
      ),
      yPoints: _renderDouble(
        map['y_points'],
      ),
      widthPoints: _renderNullableDouble(
        map['width_points'],
      ),
      heightPoints: _renderNullableDouble(
        map['height_points'],
      ),
      fontSizePoints: _renderDouble(
        map['font_size_points'],
        fallback: 9,
      ),
      fontName: _renderString(
        map['font_name'],
        fallback: 'Helvetica',
      ),
      textAlign: _renderString(
        map['text_align'],
        fallback: 'left',
      ),
      maxLines: _renderInt(
        map['max_lines'],
        fallback: 1,
      ),
      allowWrap: _renderBool(
        map['allow_wrap'],
      ),
      requiredForRender: _renderBool(
        map['required_for_render'],
      ),
      checkboxTrueValue: _renderString(
        map['checkbox_true_value'],
        fallback: 'true',
      ),
      checkboxMark: _renderString(
        map['checkbox_mark'],
        fallback: 'X',
      ),
      prefixText: _renderNullableString(
        map['prefix_text'],
      ),
      suffixText: _renderNullableString(
        map['suffix_text'],
      ),
      dateFormat: _renderString(
        map['date_format'],
        fallback: 'dd/MM/yyyy',
      ),
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(
              rawMetadata,
            )
          : const {},
    );
  }
}

// ============================================================
// RENDER MODEL HELPERS
// ============================================================

String _renderString(
  dynamic value, {
  String fallback = '',
}) {
  final text = value?.toString().trim();

  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return fallback;
  }

  return text;
}

String? _renderNullableString(
  dynamic value,
) {
  final text = _renderString(
    value,
  );

  return text.isEmpty ? null : text;
}

int _renderInt(
  dynamic value, {
  int fallback = 0,
}) {
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

double _renderDouble(
  dynamic value, {
  double fallback = 0,
}) {
  if (value is double) {
    return value;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(
        value?.toString() ?? '',
      ) ??
      fallback;
}

double? _renderNullableDouble(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(
    value.toString(),
  );
}

bool _renderBool(
  dynamic value,
) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final text = value?.toString().trim().toLowerCase();

  return text == 'true' || text == '1' || text == 'yes' || text == 'y';
}

DateTime? _renderDate(
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

// ============================================================
// EXCEPTION
// ============================================================

class ControlledFormException implements Exception {
  const ControlledFormException(
    this.message, [
    this.cause,
  ]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return message;
    }

    return '$message\n$cause';
  }
}
