import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class HospitalFormPdfService {
  HospitalFormPdfService({
    SupabaseClient? supabase,
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  // ==========================================================================
  // PUBLIC API
  // ==========================================================================

  Future<HospitalFormPdfDocumentData> loadDocument({
    required String instanceId,
    bool patientVisibleOnly = false,
    bool requireReleasedToPatient = false,
  }) async {
    final cleanInstanceId = instanceId.trim();

    if (cleanInstanceId.isEmpty) {
      throw const HospitalFormPdfException(
        'A hospital form instance ID is required.',
      );
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw const HospitalFormPdfException(
        'No signed-in Corvia account was found.',
      );
    }

    /*
     * PATIENT SAFE MODE
     *
     * Both flags are intentionally required.
     *
     * Released patient PDFs use:
     *
     * patientVisibleOnly = true
     * requireReleasedToPatient = true
     *
     * This ensures that asking for patient-visible fields in another
     * staff workflow does not automatically expose patient-safe RPC
     * behaviour or downgrade controlled-form governance information.
     */
    final patientSafeMode = patientVisibleOnly && requireReleasedToPatient;

    try {
      final instanceResponse = await _supabase
          .from('hospital_form_instances')
          .select()
          .eq('id', cleanInstanceId)
          .maybeSingle();

      if (instanceResponse == null) {
        throw const HospitalFormPdfException(
          'The selected hospital form could not be found.',
        );
      }

      final instance = Map<String, dynamic>.from(
        instanceResponse,
      );

      final patientId = _cleanId(
        instance['patient_id'],
      );

      final hospitalId = _cleanId(
        instance['hospital_id'],
      );

      final admissionId = _cleanId(
        instance['admission_id'],
      );

      final templateId = _cleanId(
        instance['template_id'],
      );

      final templateVersionId = _cleanId(
        instance['template_version_id'],
      );

      if (patientId == null) {
        throw const HospitalFormPdfException(
          'The hospital form is not linked to a patient.',
        );
      }

      if (templateId == null) {
        throw const HospitalFormPdfException(
          'The hospital form is not linked to a form template.',
        );
      }

      if (templateVersionId == null) {
        throw const HospitalFormPdfException(
          'The hospital form is not linked to a template version.',
        );
      }

      if (requireReleasedToPatient) {
        _validatePatientRelease(
          instance,
        );
      }

      final results = await Future.wait<dynamic>(
        [
          _loadTemplate(
            templateId,
          ),
          _loadTemplateVersion(
            templateVersionId,
          ),
          _loadTemplateFields(
            templateVersionId,
            patientVisibleOnly: patientVisibleOnly,
          ),
          _loadInstanceValues(
            cleanInstanceId,
            patientSafeMode: patientSafeMode,
          ),
          _loadSignatures(
            cleanInstanceId,
            patientSafeMode: patientSafeMode,
          ),
          _loadAttachments(
            cleanInstanceId,
            patientSafeMode: patientSafeMode,
          ),
          _loadHospital(
            hospitalId,
          ),
          _loadPatient(
            patientId,
          ),
          _loadAdmission(
            admissionId,
          ),
          _loadControlledBindingEvidence(
            cleanInstanceId,
            patientSafeMode: patientSafeMode,
          ),
        ],
      );

      final template = results[0] as Map<String, dynamic>?;

      final version = results[1] as Map<String, dynamic>?;

      final fields = results[2] as List<Map<String, dynamic>>;

      final values = results[3] as List<Map<String, dynamic>>;

      final signatures = results[4] as List<Map<String, dynamic>>;

      final attachments = results[5] as List<Map<String, dynamic>>;

      final hospital = results[6] as Map<String, dynamic>?;

      final patient = results[7] as Map<String, dynamic>?;

      final admission = results[8] as Map<String, dynamic>?;

      final controlledBindingEvidence =
          results[9] as HospitalFormPdfControlledBindingEvidence?;

      final patientProfile = await _loadPatientProfile(
        patient,
      );

      final answers = _buildAnswers(
        fields: fields,
        values: values,
        patientVisibleOnly: patientVisibleOnly,
      );

      final signatureRecords = signatures
          .map(
            HospitalFormPdfSignature.fromMap,
          )
          .toList();

      signatureRecords.sort(
        (
          first,
          second,
        ) {
          final firstDate = first.signedAt ?? DateTime(1970);

          final secondDate = second.signedAt ?? DateTime(1970);

          return firstDate.compareTo(
            secondDate,
          );
        },
      );

      final attachmentRecords = attachments
          .map(
            HospitalFormPdfAttachment.fromMap,
          )
          .toList();

      attachmentRecords.sort(
        (
          first,
          second,
        ) {
          final firstDate = first.uploadedAt ?? DateTime(1970);

          final secondDate = second.uploadedAt ?? DateTime(1970);

          return firstDate.compareTo(
            secondDate,
          );
        },
      );

      final formTitle = _firstText(
        [
          template?['display_name'],
          template?['title'],
          template?['name'],
          template?['template_name'],
          instance['title'],
          instance['form_name'],
          template?['code'],
        ],
        fallback: 'Hospital Form',
      );

      final formCode = _firstText(
        [
          template?['code'],
          template?['slug'],
          template?['template_code'],
        ],
        fallback: '',
      );

      final category = _firstText(
        [
          template?['category'],
          template?['document_category'],
          template?['form_category'],
          instance['category'],
        ],
        fallback: 'Clinical Document',
      );

      final description = _firstText(
        [
          template?['description'],
          template?['summary'],
          version?['description'],
        ],
        fallback: 'Corvia digital hospital form.',
      );

      final documentClassification = _firstText(
        [
          template?['document_classification'],
          template?['classification'],
          version?['document_classification'],
          instance['document_classification'],
        ],
        fallback: 'Clinical',
      );

      final versionLabel = _firstText(
        [
          version?['version_label'],
          version?['version_number'],
          version?['version'],
          version?['revision_number'],
        ],
        fallback: '1',
      );

      final languageCode = _firstText(
        [
          version?['language_code'],
          version?['language'],
          template?['language_code'],
        ],
        fallback: 'en',
      );

      final demoOnly = _firstBool(
        [
          version?['demo_only'],
          version?['is_demo_only'],
          template?['demo_only'],
          template?['is_demo_only'],
        ],
        fallback: false,
      );

      final productionApproved = _firstBool(
        [
          version?['production_approved'],
          version?['is_production_approved'],
          template?['production_approved'],
          template?['is_production_approved'],
        ],
        fallback: false,
      );

      final officialLayoutRequired = _firstBool(
        [
          version?['official_layout_required'],
          version?['requires_official_layout'],
          template?['official_layout_required'],
          template?['requires_official_layout'],
          template?['preserve_official_layout'],
        ],
        fallback: false,
      );

      final patientName = _patientDisplayName(
        patient: patient,
        profile: patientProfile,
      );

      final patientNumber = _firstText(
        [
          patient?['patient_number'],
          patient?['patient_no'],
          patient?['record_number'],
          patient?['medical_record_number'],
          patient?['mrn'],
        ],
        fallback: _shortId(
          patientId,
        ),
      );

      final patientIdNumber = _firstText(
        [
          patient?['id_number'],
          patient?['identity_number'],
          patient?['national_id'],
          patientProfile?['id_number'],
          patientProfile?['identity_number'],
        ],
        fallback: '',
      );

      final patientDateOfBirth = _firstDate(
        patient ?? <String, dynamic>{},
        const [
          'date_of_birth',
          'dob',
          'birth_date',
        ],
      );

      final hospitalName = _firstText(
        [
          hospital?['name'],
          hospital?['hospital_name'],
        ],
        fallback: 'Hospital',
      );

      final status = _firstText(
        [
          instance['status'],
        ],
        fallback: 'draft',
      );

      return HospitalFormPdfDocumentData(
        instanceId: cleanInstanceId,
        hospitalId: hospitalId,
        patientId: patientId,
        admissionId: admissionId,
        templateId: templateId,
        templateVersionId: templateVersionId,
        formTitle: formTitle,
        formCode: formCode,
        category: category,
        description: description,
        documentClassification: documentClassification,
        versionLabel: versionLabel,
        languageCode: languageCode,
        status: status,
        demoOnly: demoOnly,
        productionApproved: productionApproved,
        officialLayoutRequired: officialLayoutRequired,
        patientSafeMode: patientSafeMode,
        hospitalName: hospitalName,
        patientName: patientName,
        patientNumber: patientNumber,
        patientIdNumber: patientIdNumber,
        patientDateOfBirth: patientDateOfBirth,
        admissionNumber: _firstText(
          [
            admission?['admission_number'],
            admission?['reference_number'],
            admission?['admission_reference'],
          ],
          fallback: '',
        ),
        wardName: _firstText(
          [
            admission?['ward_name'],
            admission?['ward'],
          ],
          fallback: '',
        ),
        roomName: _firstText(
          [
            admission?['room_name'],
            admission?['room_number'],
            admission?['room'],
          ],
          fallback: '',
        ),
        bedName: _firstText(
          [
            admission?['bed_name'],
            admission?['bed_number'],
            admission?['bed'],
          ],
          fallback: '',
        ),
        createdAt: _firstDate(
          instance,
          const [
            'created_at',
          ],
        ),
        submittedAt: _firstDate(
          instance,
          const [
            'submitted_at',
          ],
        ),
        finalizedAt: _firstDate(
          instance,
          const [
            'finalized_at',
            'finalised_at',
            'completed_at',
          ],
        ),
        releasedToPatientAt: _firstDate(
          instance,
          const [
            'released_to_patient_at',
            'patient_released_at',
            'released_at',
          ],
        ),
        answers: answers,
        signatures: signatureRecords,
        attachments: attachmentRecords,
        rawInstance: instance,
        rawTemplate: template,
        rawVersion: version,
        controlledBindingEvidence: controlledBindingEvidence,
        generatedAt: DateTime.now(),
      );
    } on HospitalFormPdfException {
      rethrow;
    } on PostgrestException catch (error) {
      throw HospitalFormPdfException(
        _cleanPostgrestError(
          error,
        ),
      );
    } catch (error) {
      throw HospitalFormPdfException(
        error.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    }
  }

  Future<Uint8List> buildPdfBytes({
    required String instanceId,
    bool patientVisibleOnly = false,
    bool requireReleasedToPatient = false,
  }) async {
    final data = await loadDocument(
      instanceId: instanceId,
      patientVisibleOnly: patientVisibleOnly,
      requireReleasedToPatient: requireReleasedToPatient,
    );

    return buildPdfFromData(
      data,
    );
  }

  Future<Uint8List> buildPdfFromData(
    HospitalFormPdfDocumentData data,
  ) async {
    final pdf = pw.Document(
      title: data.formTitle,
      author: 'Corvia Medical',
      subject: '${data.category} - ${data.patientName}',
      creator: 'Corvia Medical Digital Hospital Form Engine',
      keywords: 'Corvia Medical, Hospital Form, ${data.category}',
    );

    final groupedAnswers = _groupAnswersBySection(
      data.answers,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(
          34,
          38,
          34,
          42,
        ),
        header: (
          context,
        ) {
          return _buildPdfHeader(
            data,
          );
        },
        footer: (
          context,
        ) {
          return _buildPdfFooter(
            context,
            data,
          );
        },
        build: (
          context,
        ) {
          final widgets = <pw.Widget>[];

          if (data.demoOnly || !data.productionApproved) {
            widgets.add(
              _buildApprovalWarning(
                data,
              ),
            );

            widgets.add(
              pw.SizedBox(
                height: 8,
              ),
            );
          }

          if (data.officialLayoutRequired) {
            widgets.add(
              _buildOfficialLayoutWarning(),
            );

            widgets.add(
              pw.SizedBox(
                height: 8,
              ),
            );
          }

          final controlledEvidence = data.controlledBindingEvidence;

          if (controlledEvidence != null &&
              controlledEvidence.isControlledForm &&
              !controlledEvidence.isBound) {
            widgets.add(
              data.patientSafeMode
                  ? _buildPatientControlledVerificationWarning(
                      controlledEvidence,
                    )
                  : _buildControlledMasterWarning(
                      controlledEvidence,
                    ),
            );

            widgets.add(
              pw.SizedBox(
                height: 8,
              ),
            );
          }

          widgets.add(
            _buildDocumentIdentity(
              data,
            ),
          );

          if (controlledEvidence != null &&
              controlledEvidence.isControlledForm) {
            widgets.add(
              pw.SizedBox(
                height: 14,
              ),
            );

            widgets.add(
              _buildControlledMasterEvidenceSection(
                controlledEvidence,
                patientSafeMode: data.patientSafeMode,
              ),
            );
          }

          widgets.add(
            pw.SizedBox(
              height: 14,
            ),
          );

          widgets.add(
            _buildPatientSection(
              data,
            ),
          );

          if (_hasAdmissionContext(
            data,
          )) {
            widgets.add(
              pw.SizedBox(
                height: 14,
              ),
            );

            widgets.add(
              _buildAdmissionSection(
                data,
              ),
            );
          }

          widgets.add(
            pw.SizedBox(
              height: 16,
            ),
          );

          if (groupedAnswers.isEmpty) {
            widgets.add(
              _buildNoAnswers(),
            );
          } else {
            for (final entry in groupedAnswers.entries) {
              widgets.add(
                _buildAnswerSection(
                  entry.key,
                  entry.value,
                ),
              );

              widgets.add(
                pw.SizedBox(
                  height: 12,
                ),
              );
            }
          }

          if (data.signatures.isNotEmpty) {
            widgets.add(
              pw.SizedBox(
                height: 8,
              ),
            );

            widgets.add(
              _buildSignaturesSection(
                data.signatures,
              ),
            );
          }

          if (data.attachments.isNotEmpty) {
            widgets.add(
              pw.SizedBox(
                height: 12,
              ),
            );

            widgets.add(
              _buildAttachmentsSection(
                data.attachments,
              ),
            );
          }

          widgets.add(
            pw.SizedBox(
              height: 16,
            ),
          );

          widgets.add(
            _buildRecordIntegritySection(
              data,
            ),
          );

          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  String buildFileName(
    HospitalFormPdfDocumentData data,
  ) {
    final date = data.finalizedAt ??
        data.submittedAt ??
        data.createdAt ??
        data.generatedAt;

    final dateText = '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';

    final formPart = _safeFilePart(
      data.formCode.isNotEmpty ? data.formCode : data.formTitle,
    );

    final patientPart = _safeFilePart(
      data.patientNumber.isNotEmpty ? data.patientNumber : data.patientName,
    );

    return 'Corvia_'
        '${formPart}_'
        '${patientPart}_'
        '$dateText.pdf';
  }

  Future<bool> logExport({
    required HospitalFormPdfDocumentData data,
    required String action,
    String? fileName,
    int? byteSize,
    String? reason,
    String? destination,
    String? storageBucket,
    String? storagePath,
    bool strict = false,
  }) async {
    final cleanAction = action.trim();

    final exportAction = cleanAction.isEmpty ? 'export' : cleanAction;

    final resolvedFileName = fileName == null || fileName.trim().isEmpty
        ? buildFileName(
            data,
          )
        : fileName.trim();

    final auditParts = <String>[];

    final cleanReason = reason?.trim();

    if (cleanReason != null && cleanReason.isNotEmpty) {
      auditParts.add(
        cleanReason,
      );
    }

    auditParts.add(
      'Generated file: $resolvedFileName',
    );

    if (byteSize != null && byteSize >= 0) {
      auditParts.add(
        'File size: $byteSize bytes',
      );
    }

    final controlled = data.controlledBindingEvidence;

    if (controlled != null && controlled.isControlledForm) {
      auditParts.add(
        'Controlled form: yes',
      );

      auditParts.add(
        'Official master bound: '
        '${controlled.isBound ? 'yes' : 'no'}',
      );

      auditParts.add(
        'Official verification: '
        '${controlled.verified ? 'verified' : 'unavailable'}',
      );

      /*
       * These internal identifiers only exist in staff/admin mode.
       *
       * The patient-safe controlled verification RPC deliberately
       * does not expose these values.
       */
      if (controlled.bindingId.isNotEmpty) {
        auditParts.add(
          'Binding ID: ${controlled.bindingId}',
        );
      }

      if (controlled.controlledVersionId.isNotEmpty) {
        auditParts.add(
          'Controlled version ID: '
          '${controlled.controlledVersionId}',
        );
      }

      if (controlled.sha256.isNotEmpty) {
        auditParts.add(
          'Master SHA-256: ${controlled.sha256}',
        );
      }
    }

    final auditReason = auditParts.isEmpty
        ? null
        : auditParts.join(
            ' | ',
          );

    try {
      await _supabase.rpc(
        'corvia_form_log_export',
        params: {
          'p_instance_id': data.instanceId,
          'p_export_type': exportAction,
          'p_storage_bucket': _emptyToNull(
            storageBucket,
          ),
          'p_storage_path': _emptyToNull(
            storagePath,
          ),
          'p_destination': _emptyToNull(
            destination,
          ),
          'p_reason': _emptyToNull(
            auditReason,
          ),
        },
      );

      return true;
    } on PostgrestException catch (error) {
      final message = _cleanPostgrestError(
        error,
      );

      debugPrint(
        'corvia_form_log_export failed: $message',
      );

      if (strict) {
        throw HospitalFormPdfException(
          'The PDF export could not be audit-logged. '
          'The export was blocked to protect the '
          'medical-record audit trail. '
          '$message',
        );
      }

      return false;
    } catch (error) {
      final message = error
          .toString()
          .replaceFirst(
            'Exception: ',
            '',
          )
          .trim();

      debugPrint(
        'corvia_form_log_export failed: $message',
      );

      if (strict) {
        throw HospitalFormPdfException(
          'The PDF export could not be audit-logged. '
          'The export was blocked to protect the '
          'medical-record audit trail. '
          '$message',
        );
      }

      return false;
    }
  }

  // ==========================================================================
  // PDF HEADER / FOOTER
  // ==========================================================================

  pw.Widget _buildPdfHeader(
    HospitalFormPdfDocumentData data,
  ) {
    final controlled = data.controlledBindingEvidence;

    return pw.Container(
      padding: pw.EdgeInsets.only(
        bottom: 9,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: PdfColors.grey,
            width: 0.5,
          ),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 34,
            height: 34,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.teal,
              borderRadius: pw.BorderRadius.circular(
                5,
              ),
            ),
            child: pw.Text(
              'C',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(
            width: 10,
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CORVIA MEDICAL',
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(
                  height: 2,
                ),
                pw.Text(
                  data.hospitalName,
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(
                  height: 1,
                ),
                pw.Text(
                  data.patientSafeMode
                      ? 'Released Patient Hospital Record'
                      : 'Digital Hospital Form',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(
            width: 10,
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                data.formCode.isEmpty ? 'FORM' : data.formCode,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Version ${data.versionLabel}',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
              if (controlled != null && controlled.isControlledForm)
                pw.Text(
                  data.patientSafeMode
                      ? controlled.verified
                          ? 'OFFICIAL DOCUMENT VERIFIED'
                          : 'VERIFICATION UNAVAILABLE'
                      : controlled.isBound
                          ? 'CONTROLLED MASTER BOUND'
                          : 'MASTER NOT BOUND',
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    color:
                        controlled.verified ? PdfColors.green : PdfColors.red,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfFooter(
    pw.Context context,
    HospitalFormPdfDocumentData data,
  ) {
    return pw.Container(
      padding: pw.EdgeInsets.only(
        top: 7,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColors.grey,
            width: 0.4,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              data.patientSafeMode
                  ? 'Corvia Medical | Confidential Patient Record'
                  : 'Corvia Medical | Confidential Clinical Record',
              style: pw.TextStyle(
                fontSize: 7,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Text(
            'Page ${context.pageNumber} '
            'of ${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // WARNINGS
  // ==========================================================================

  pw.Widget _buildApprovalWarning(
    HospitalFormPdfDocumentData data,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(
        10,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.orange100,
        border: pw.Border.all(
          color: PdfColors.orange,
          width: 0.7,
        ),
        borderRadius: pw.BorderRadius.circular(
          5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DEMO / NOT PRODUCTION APPROVED',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
          pw.SizedBox(
            height: 3,
          ),
          pw.Text(
            data.demoOnly
                ? 'This template is marked as demo-only '
                    'and must not be treated as an approved '
                    'statutory or hospital production document.'
                : 'This template has not been marked as '
                    'production-approved.',
            style: pw.TextStyle(
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildOfficialLayoutWarning() {
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(
        10,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.red100,
        border: pw.Border.all(
          color: PdfColors.red,
          width: 0.7,
        ),
        borderRadius: pw.BorderRadius.circular(
          5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'OFFICIAL PRINT LAYOUT REQUIRED',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
          pw.SizedBox(
            height: 3,
          ),
          pw.Text(
            'This generic Corvia PDF is a clinical record summary. '
            'The approved statutory or hospital-specific print '
            'layout must be used where an official external form '
            'is required.',
            style: pw.TextStyle(
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildControlledMasterWarning(
    HospitalFormPdfControlledBindingEvidence evidence,
  ) {
    final approvedAvailable = evidence.registryProductionApproved &&
        evidence.currentControlledVersionId != null;

    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(
        10,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.red100,
        border: pw.Border.all(
          color: PdfColors.red,
          width: 0.7,
        ),
        borderRadius: pw.BorderRadius.circular(
          5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CONTROLLED OFFICIAL MASTER NOT BOUND',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
          pw.SizedBox(
            height: 3,
          ),
          pw.Text(
            evidence.officialFormName.isNotEmpty
                ? evidence.officialFormName
                : evidence.formCode,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(
            height: 3,
          ),
          pw.Text(
            approvedAvailable
                ? 'A production-approved master is configured, '
                    'but this record does not currently contain an '
                    'immutable master binding.'
                : 'No production-approved official master is '
                    'currently available for this controlled form.',
            style: pw.TextStyle(
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPatientControlledVerificationWarning(
    HospitalFormPdfControlledBindingEvidence evidence,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(
        10,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.orange100,
        border: pw.Border.all(
          color: PdfColors.orange,
          width: 0.7,
        ),
        borderRadius: pw.BorderRadius.circular(
          5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'OFFICIAL DOCUMENT VERIFICATION UNAVAILABLE',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
          pw.SizedBox(
            height: 3,
          ),
          pw.Text(
            evidence.officialFormName.isNotEmpty
                ? evidence.officialFormName
                : evidence.formCode,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(
            height: 3,
          ),
          pw.Text(
            'Corvia could not confirm the approved official document '
            'master for this released record. Contact the hospital if '
            'you require an official statutory copy.',
            style: pw.TextStyle(
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // PDF SECTIONS
  // ==========================================================================

  pw.Widget _buildDocumentIdentity(
    HospitalFormPdfDocumentData data,
  ) {
    return _sectionBox(
      title: 'Document Information',
      children: [
        _metaRow(
          'Form',
          data.formTitle,
        ),
        _metaRow(
          'Category',
          data.category,
        ),
        _metaRow(
          'Classification',
          data.documentClassification,
        ),
        _metaRow(
          'Version',
          data.versionLabel,
        ),
        _metaRow(
          'Language',
          data.languageCode,
        ),
        _metaRow(
          'Status',
          _prettyStatus(
            data.status,
          ),
        ),
        if (data.formCode.isNotEmpty)
          _metaRow(
            'Form Code',
            data.formCode,
          ),
        if (data.description.isNotEmpty)
          _metaRow(
            'Description',
            data.description,
          ),
      ],
    );
  }

  pw.Widget _buildControlledMasterEvidenceSection(
    HospitalFormPdfControlledBindingEvidence evidence, {
    required bool patientSafeMode,
  }) {
    if (patientSafeMode) {
      return _buildPatientOfficialVerificationSection(
        evidence,
      );
    }

    if (!evidence.isBound) {
      return _sectionBox(
        title: 'Controlled Official Master Evidence',
        children: [
          _metaRow(
            'Controlled Form',
            'Yes',
          ),
          _metaRow(
            'Official Form',
            evidence.officialFormName.isEmpty
                ? evidence.formCode
                : evidence.officialFormName,
          ),
          _metaRow(
            'Master Bound',
            'No',
          ),
          _metaRow(
            'Registry Status',
            _prettyStatus(
              evidence.registryProductionStatus,
            ),
          ),
          _metaRow(
            'Production Approved',
            evidence.registryProductionApproved ? 'Yes' : 'No',
          ),
        ],
      );
    }

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.green,
          width: 0.7,
        ),
        borderRadius: pw.BorderRadius.circular(
          6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
            ),
            child: pw.Text(
              'Controlled Official Master Evidence',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green,
              ),
            ),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.all(
              11,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _metaRow(
                  'Official Form',
                  evidence.officialFormName.isEmpty
                      ? evidence.formCode
                      : evidence.officialFormName,
                ),
                if (evidence.formCode.isNotEmpty)
                  _metaRow(
                    'Corvia Form Code',
                    evidence.formCode,
                  ),
                if (evidence.officialFormNumber.isNotEmpty)
                  _metaRow(
                    'Official Form No.',
                    evidence.officialFormNumber,
                  ),
                _metaRow(
                  'Master Version',
                  '${evidence.versionNumber ?? '-'}'
                      '${evidence.versionLabel.isEmpty ? '' : ' - ${evidence.versionLabel}'}',
                ),
                if (evidence.officialVersionReference.isNotEmpty)
                  _metaRow(
                    'Official Version',
                    evidence.officialVersionReference,
                  ),
                if (evidence.officialRevisionReference.isNotEmpty)
                  _metaRow(
                    'Official Revision',
                    evidence.officialRevisionReference,
                  ),
                _metaRow(
                  'Master Status',
                  _prettyStatus(
                    evidence.approvalStatus,
                  ),
                ),
                _metaRow(
                  'Master Production Approved',
                  evidence.productionApproved ? 'Yes' : 'No',
                ),
                if (evidence.effectiveOn != null)
                  _metaRow(
                    'Effective Date',
                    _formatDateOnly(
                      evidence.effectiveOn!,
                    ),
                  ),
                if (evidence.approvedAt != null)
                  _metaRow(
                    'Approved At',
                    _formatDateTime(
                      evidence.approvedAt!,
                    ),
                  ),
                if (evidence.boundAt != null)
                  _metaRow(
                    'Bound At',
                    _formatDateTime(
                      evidence.boundAt!,
                    ),
                  ),
                if (evidence.bindingId.isNotEmpty)
                  _metaRow(
                    'Binding ID',
                    evidence.bindingId,
                  ),
                if (evidence.controlledVersionId.isNotEmpty)
                  _metaRow(
                    'Controlled Version ID',
                    evidence.controlledVersionId,
                  ),
                if (evidence.sourceDocumentName.isNotEmpty)
                  _metaRow(
                    'Source Master',
                    evidence.sourceDocumentName,
                  ),
                if (evidence.sha256.isNotEmpty) ...[
                  pw.SizedBox(
                    height: 4,
                  ),
                  pw.Text(
                    'Master SHA-256',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(
                    height: 3,
                  ),
                  pw.Container(
                    width: double.infinity,
                    padding: pw.EdgeInsets.all(
                      7,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(
                        4,
                      ),
                    ),
                    child: pw.Text(
                      evidence.sha256,
                      style: pw.TextStyle(
                        fontSize: 7,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPatientOfficialVerificationSection(
    HospitalFormPdfControlledBindingEvidence evidence,
  ) {
    final verified =
        evidence.verified && evidence.isBound && evidence.productionApproved;

    final borderColor = verified ? PdfColors.green : PdfColors.orange;

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: borderColor,
          width: 0.7,
        ),
        borderRadius: pw.BorderRadius.circular(
          6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
            ),
            child: pw.Text(
              verified
                  ? 'Official Document Verification'
                  : 'Official Document Verification Unavailable',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: borderColor,
              ),
            ),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.all(
              11,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _metaRow(
                  'Verification',
                  verified
                      ? 'Verified Official Hospital Document'
                      : 'Verification unavailable',
                ),
                _metaRow(
                  'Official Form',
                  evidence.officialFormName.isEmpty
                      ? evidence.formCode
                      : evidence.officialFormName,
                ),
                if (evidence.officialFormNumber.isNotEmpty)
                  _metaRow(
                    'Official Form No.',
                    evidence.officialFormNumber,
                  ),
                if (evidence.versionNumber != null ||
                    evidence.versionLabel.isNotEmpty)
                  _metaRow(
                    'Version',
                    '${evidence.versionNumber ?? '-'}'
                        '${evidence.versionLabel.isEmpty ? '' : ' - ${evidence.versionLabel}'}',
                  ),
                if (evidence.officialVersionReference.isNotEmpty)
                  _metaRow(
                    'Official Version',
                    evidence.officialVersionReference,
                  ),
                if (evidence.officialRevisionReference.isNotEmpty)
                  _metaRow(
                    'Official Revision',
                    evidence.officialRevisionReference,
                  ),
                if (evidence.effectiveOn != null)
                  _metaRow(
                    'Effective Date',
                    _formatDateOnly(
                      evidence.effectiveOn!,
                    ),
                  ),
                pw.SizedBox(
                  height: 4,
                ),
                pw.Text(
                  verified
                      ? 'This released record was verified against the '
                          'production-approved official hospital master.'
                      : 'The internal verification evidence for this '
                          'document is not available to confirm.',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPatientSection(
    HospitalFormPdfDocumentData data,
  ) {
    return _sectionBox(
      title: 'Patient',
      children: [
        _metaRow(
          'Patient Name',
          data.patientName,
        ),
        _metaRow(
          'Patient Number',
          data.patientNumber,
        ),
        if (data.patientIdNumber.isNotEmpty)
          _metaRow(
            'ID Number',
            data.patientIdNumber,
          ),
        if (data.patientDateOfBirth != null)
          _metaRow(
            'Date of Birth',
            _formatDateOnly(
              data.patientDateOfBirth!,
            ),
          ),
        if (!data.patientSafeMode)
          _metaRow(
            'Patient Record ID',
            data.patientId,
          ),
      ],
    );
  }

  pw.Widget _buildAdmissionSection(
    HospitalFormPdfDocumentData data,
  ) {
    return _sectionBox(
      title: 'Admission Context',
      children: [
        if (data.admissionNumber.isNotEmpty)
          _metaRow(
            'Admission Number',
            data.admissionNumber,
          ),
        if (data.wardName.isNotEmpty)
          _metaRow(
            'Ward',
            data.wardName,
          ),
        if (data.roomName.isNotEmpty)
          _metaRow(
            'Room',
            data.roomName,
          ),
        if (data.bedName.isNotEmpty)
          _metaRow(
            'Bed',
            data.bedName,
          ),
        if (!data.patientSafeMode && data.admissionId != null)
          _metaRow(
            'Admission ID',
            data.admissionId!,
          ),
      ],
    );
  }

  pw.Widget _buildAnswerSection(
    String section,
    List<HospitalFormPdfAnswer> answers,
  ) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.5,
        ),
        borderRadius: pw.BorderRadius.circular(
          6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
            ),
            child: pw.Text(
              section,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          ...answers.map(
            (
              answer,
            ) {
              return pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(
                      color: PdfColors.grey300,
                      width: 0.3,
                    ),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      answer.label,
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(
                      height: 3,
                    ),
                    pw.Text(
                      answer.displayValue,
                      style: pw.TextStyle(
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSignaturesSection(
    List<HospitalFormPdfSignature> signatures,
  ) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.5,
        ),
        borderRadius: pw.BorderRadius.circular(
          6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
            ),
            child: pw.Text(
              'Electronic Signatures',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          ...signatures.map(
            (
              signature,
            ) {
              return pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.all(
                  11,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(
                      color: PdfColors.grey300,
                      width: 0.3,
                    ),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            signature.signerName,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Text(
                          _prettyStatus(
                            signature.signerRole,
                          ),
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(
                      height: 4,
                    ),
                    if (signature.signerIdentifier.isNotEmpty)
                      pw.Text(
                        'Identifier: '
                        '${signature.signerIdentifier}',
                        style: pw.TextStyle(
                          fontSize: 8,
                        ),
                      ),
                    pw.Text(
                      'Method: '
                      '${_prettyStatus(signature.signatureMethod)}',
                      style: pw.TextStyle(
                        fontSize: 8,
                      ),
                    ),
                    pw.Text(
                      'Signed: '
                      '${_formatNullableDateTime(signature.signedAt)}',
                      style: pw.TextStyle(
                        fontSize: 8,
                      ),
                    ),
                    pw.Text(
                      'Status: '
                      '${signature.isValid && signature.revokedAt == null ? 'Valid' : 'Revoked / Invalid'}',
                      style: pw.TextStyle(
                        fontSize: 8,
                      ),
                    ),
                    if (signature.revokedAt != null)
                      pw.Text(
                        'Revoked: '
                        '${_formatDateTime(signature.revokedAt!)}',
                        style: pw.TextStyle(
                          fontSize: 8,
                        ),
                      ),
                    if (signature.witnessName.isNotEmpty)
                      pw.Text(
                        'Witness: '
                        '${signature.witnessName}',
                        style: pw.TextStyle(
                          fontSize: 8,
                        ),
                      ),
                    if (signature.declarationText.isNotEmpty) ...[
                      pw.SizedBox(
                        height: 4,
                      ),
                      pw.Text(
                        signature.declarationText,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAttachmentsSection(
    List<HospitalFormPdfAttachment> attachments,
  ) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.5,
        ),
        borderRadius: pw.BorderRadius.circular(
          6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
            ),
            child: pw.Text(
              'Released Supporting Documents',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          ...attachments.map(
            (
              attachment,
            ) {
              return pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.all(
                  11,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(
                      color: PdfColors.grey300,
                      width: 0.3,
                    ),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      attachment.fileName.isEmpty
                          ? 'Supporting Document'
                          : attachment.fileName,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(
                      height: 4,
                    ),
                    _metaRow(
                      'Type',
                      _prettyStatus(
                        attachment.attachmentType,
                      ),
                    ),
                    if (attachment.mimeType.isNotEmpty)
                      _metaRow(
                        'File Type',
                        attachment.mimeType,
                      ),
                    if (attachment.fileSizeBytes != null)
                      _metaRow(
                        'File Size',
                        '${attachment.fileSizeBytes} bytes',
                      ),
                    if (attachment.documentClassification.isNotEmpty)
                      _metaRow(
                        'Classification',
                        _prettyStatus(
                          attachment.documentClassification,
                        ),
                      ),
                    if (attachment.uploadedAt != null)
                      _metaRow(
                        'Added',
                        _formatDateTime(
                          attachment.uploadedAt!,
                        ),
                      ),
                    if (attachment.description.isNotEmpty)
                      _metaRow(
                        'Description',
                        attachment.description,
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  pw.Widget _buildRecordIntegritySection(
    HospitalFormPdfDocumentData data,
  ) {
    final controlled = data.controlledBindingEvidence;

    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(
        10,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.4,
        ),
        borderRadius: pw.BorderRadius.circular(
          5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Record Integrity',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(
            height: 4,
          ),
          if (!data.patientSafeMode) ...[
            pw.Text(
              'Instance ID: ${data.instanceId}',
              style: pw.TextStyle(
                fontSize: 7,
              ),
            ),
            pw.Text(
              'Template Version ID: '
              '${data.templateVersionId}',
              style: pw.TextStyle(
                fontSize: 7,
              ),
            ),
          ],
          pw.Text(
            'Created: '
            '${_formatNullableDateTime(data.createdAt)}',
            style: pw.TextStyle(
              fontSize: 7,
            ),
          ),
          pw.Text(
            'Submitted: '
            '${_formatNullableDateTime(data.submittedAt)}',
            style: pw.TextStyle(
              fontSize: 7,
            ),
          ),
          pw.Text(
            'Finalized: '
            '${_formatNullableDateTime(data.finalizedAt)}',
            style: pw.TextStyle(
              fontSize: 7,
            ),
          ),
          pw.Text(
            'Released to Patient: '
            '${_formatNullableDateTime(data.releasedToPatientAt)}',
            style: pw.TextStyle(
              fontSize: 7,
            ),
          ),
          if (controlled != null && controlled.isControlledForm) ...[
            pw.Text(
              data.patientSafeMode
                  ? 'Official Document Verification: '
                      '${controlled.verified ? 'Verified' : 'Unavailable'}'
                  : 'Controlled Form: Yes',
              style: pw.TextStyle(
                fontSize: 7,
              ),
            ),
            if (!data.patientSafeMode) ...[
              pw.Text(
                'Controlled Master Bound: '
                '${controlled.isBound ? 'Yes' : 'No'}',
                style: pw.TextStyle(
                  fontSize: 7,
                ),
              ),
              if (controlled.bindingId.isNotEmpty)
                pw.Text(
                  'Controlled Binding ID: '
                  '${controlled.bindingId}',
                  style: pw.TextStyle(
                    fontSize: 7,
                  ),
                ),
              if (controlled.controlledVersionId.isNotEmpty)
                pw.Text(
                  'Controlled Version ID: '
                  '${controlled.controlledVersionId}',
                  style: pw.TextStyle(
                    fontSize: 7,
                  ),
                ),
              if (controlled.sha256.isNotEmpty)
                pw.Text(
                  'Controlled Master SHA-256: '
                  '${controlled.sha256}',
                  style: pw.TextStyle(
                    fontSize: 6,
                  ),
                ),
            ],
          ],
          pw.Text(
            'PDF Generated: '
            '${_formatDateTime(data.generatedAt)}',
            style: pw.TextStyle(
              fontSize: 7,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildNoAnswers() {
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(
        18,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey300,
        ),
        borderRadius: pw.BorderRadius.circular(
          6,
        ),
      ),
      child: pw.Text(
        'No form answers are available for this document.',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 9,
          color: PdfColors.grey700,
        ),
      ),
    );
  }

  pw.Widget _sectionBox({
    required String title,
    required List<pw.Widget> children,
  }) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.5,
        ),
        borderRadius: pw.BorderRadius.circular(
          6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.all(
              11,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _metaRow(
    String label,
    String value,
  ) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(
        bottom: 5,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(
            width: 8,
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '-' : value,
              style: pw.TextStyle(
                fontSize: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // DATABASE LOADERS
  // ==========================================================================

  Future<Map<String, dynamic>?> _loadTemplate(
    String templateId,
  ) async {
    try {
      final response = await _supabase
          .from('hospital_form_templates')
          .select()
          .eq('id', templateId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Map<String, dynamic>.from(
        response,
      );
    } catch (error) {
      debugPrint(
        'PDF template lookup failed: $error',
      );

      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadTemplateVersion(
    String versionId,
  ) async {
    try {
      final response = await _supabase
          .from('hospital_form_template_versions')
          .select()
          .eq('id', versionId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Map<String, dynamic>.from(
        response,
      );
    } catch (error) {
      debugPrint(
        'PDF template version lookup failed: $error',
      );

      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadTemplateFields(
    String versionId, {
    required bool patientVisibleOnly,
  }) async {
    try {
      /*
       * IMPORTANT:
       *
       * The actual Corvia schema uses:
       *
       * hospital_form_template_fields.version_id
       *
       * NOT template_version_id.
       */
      if (patientVisibleOnly) {
        final response = await _supabase
            .from('hospital_form_template_fields')
            .select()
            .eq('version_id', versionId)
            .eq('is_patient_visible', true);

        return _rows(
          response,
        );
      }

      final response = await _supabase
          .from('hospital_form_template_fields')
          .select()
          .eq('version_id', versionId);

      return _rows(
        response,
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'PDF template field lookup failed: $error',
      );

      if (patientVisibleOnly) {
        throw HospitalFormPdfException(
          'The patient-visible form definition could not be loaded securely. '
          '${_cleanPostgrestError(error)}',
        );
      }

      return [];
    } catch (error) {
      debugPrint(
        'PDF template field lookup failed: $error',
      );

      if (patientVisibleOnly) {
        throw HospitalFormPdfException(
          'The patient-visible form definition could not be loaded securely. '
          '${error.toString().replaceFirst('Exception: ', '').trim()}',
        );
      }

      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadInstanceValues(
    String instanceId, {
    required bool patientSafeMode,
  }) async {
    try {
      /*
       * RLS now protects this table using:
       *
       * corvia_form_can_read_value(id)
       *
       * For a patient, the database only returns values whose linked
       * hospital_form_template_fields.is_patient_visible is TRUE.
       */
      final response = await _supabase
          .from('hospital_form_instance_values')
          .select()
          .eq('instance_id', instanceId);

      return _rows(
        response,
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'PDF form-value lookup failed: $error',
      );

      if (patientSafeMode) {
        throw HospitalFormPdfException(
          'The released form values could not be loaded securely. '
          '${_cleanPostgrestError(error)}',
        );
      }

      return [];
    } catch (error) {
      debugPrint(
        'PDF form-value lookup failed: $error',
      );

      if (patientSafeMode) {
        throw HospitalFormPdfException(
          'The released form values could not be loaded securely. '
          '${error.toString().replaceFirst('Exception: ', '').trim()}',
        );
      }

      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadSignatures(
    String instanceId, {
    required bool patientSafeMode,
  }) async {
    try {
      if (patientSafeMode) {
        /*
         * PATIENT SAFE RPC
         *
         * Deliberately does NOT return:
         *
         * signer_profile_id
         * signer_identifier
         * signature_evidence
         * witness_profile_id
         * source_device_id
         * revoked_by
         */
        final response = await _supabase.rpc(
          'corvia_form_patient_safe_signatures',
          params: {
            'p_instance_id': instanceId,
          },
        );

        return _rows(
          response,
        );
      }

      /*
       * Staff/admin path.
       *
       * Base-table RLS now blocks normal patient SELECT access and
       * only permits authorised hospital staff/admin users.
       */
      final response = await _supabase
          .from('hospital_form_signatures')
          .select()
          .eq('instance_id', instanceId);

      return _rows(
        response,
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'PDF signature lookup failed: $error',
      );

      if (patientSafeMode) {
        throw HospitalFormPdfException(
          'The released form signatures could not be loaded securely. '
          '${_cleanPostgrestError(error)}',
        );
      }

      return [];
    } catch (error) {
      debugPrint(
        'PDF signature lookup failed: $error',
      );

      if (patientSafeMode) {
        throw HospitalFormPdfException(
          'The released form signatures could not be loaded securely. '
          '${error.toString().replaceFirst('Exception: ', '').trim()}',
        );
      }

      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadAttachments(
    String instanceId, {
    required bool patientSafeMode,
  }) async {
    try {
      if (patientSafeMode) {
        /*
         * PATIENT SAFE RPC
         *
         * Deliberately does NOT return:
         *
         * storage_bucket
         * storage_path
         * checksum_sha256
         * uploaded_by
         * deactivation actor metadata
         */
        final response = await _supabase.rpc(
          'corvia_form_patient_safe_attachments',
          params: {
            'p_instance_id': instanceId,
          },
        );

        return _rows(
          response,
        );
      }

      /*
       * Staff/admin base-table access.
       */
      final response = await _supabase
          .from('hospital_form_attachments')
          .select()
          .eq('instance_id', instanceId)
          .eq('is_active', true);

      return _rows(
        response,
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'PDF attachment lookup failed: $error',
      );

      if (patientSafeMode) {
        throw HospitalFormPdfException(
          'The released form attachments could not be loaded securely. '
          '${_cleanPostgrestError(error)}',
        );
      }

      return [];
    } catch (error) {
      debugPrint(
        'PDF attachment lookup failed: $error',
      );

      if (patientSafeMode) {
        throw HospitalFormPdfException(
          'The released form attachments could not be loaded securely. '
          '${error.toString().replaceFirst('Exception: ', '').trim()}',
        );
      }

      return [];
    }
  }

  Future<Map<String, dynamic>?> _loadHospital(
    String? hospitalId,
  ) async {
    if (hospitalId == null) {
      return null;
    }

    try {
      final response = await _supabase
          .from('hospitals')
          .select()
          .eq('id', hospitalId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Map<String, dynamic>.from(
        response,
      );
    } catch (error) {
      debugPrint(
        'PDF hospital lookup failed: $error',
      );

      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadPatient(
    String patientId,
  ) async {
    try {
      final response = await _supabase
          .from('patients')
          .select()
          .eq('id', patientId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Map<String, dynamic>.from(
        response,
      );
    } catch (error) {
      debugPrint(
        'PDF patient lookup failed: $error',
      );

      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadPatientProfile(
    Map<String, dynamic>? patient,
  ) async {
    if (patient == null) {
      return null;
    }

    final profileId = _cleanId(
      patient['profile_id'],
    );

    final userId = _cleanId(
      patient['user_id'],
    );

    final identifiers = <String>{
      if (profileId != null) profileId,
      if (userId != null) userId,
    };

    for (final identifier in identifiers) {
      try {
        final response = await _supabase
            .from('profiles')
            .select()
            .eq('id', identifier)
            .maybeSingle();

        if (response != null) {
          return Map<String, dynamic>.from(
            response,
          );
        }
      } catch (_) {}
    }

    for (final identifier in identifiers) {
      try {
        final response = await _supabase
            .from('profiles')
            .select()
            .eq('user_id', identifier)
            .maybeSingle();

        if (response != null) {
          return Map<String, dynamic>.from(
            response,
          );
        }
      } catch (_) {}
    }

    return null;
  }

  Future<Map<String, dynamic>?> _loadAdmission(
    String? admissionId,
  ) async {
    if (admissionId == null) {
      return null;
    }

    try {
      final response = await _supabase
          .from('hospital_admissions')
          .select()
          .eq('id', admissionId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Map<String, dynamic>.from(
        response,
      );
    } catch (error) {
      debugPrint(
        'PDF admission lookup failed: $error',
      );

      return null;
    }
  }

  Future<HospitalFormPdfControlledBindingEvidence?>
      _loadControlledBindingEvidence(
    String instanceId, {
    required bool patientSafeMode,
  }) async {
    final rpcName = patientSafeMode
        ? 'corvia_controlled_patient_instance_verification'
        : 'corvia_controlled_instance_binding_status';

    try {
      final response = await _supabase.rpc(
        rpcName,
        params: {
          'p_instance_id': instanceId,
        },
      );

      if (response == null) {
        return null;
      }

      Map<String, dynamic>? map;

      if (response is Map<String, dynamic>) {
        map = response;
      } else if (response is Map) {
        map = Map<String, dynamic>.from(
          response,
        );
      } else if (response is List &&
          response.isNotEmpty &&
          response.first is Map) {
        map = Map<String, dynamic>.from(
          response.first as Map,
        );
      }

      if (map == null) {
        if (patientSafeMode) {
          throw const HospitalFormPdfException(
            'The released hospital form could not be securely verified.',
          );
        }

        return null;
      }

      return HospitalFormPdfControlledBindingEvidence.fromMap(
        map,
      );
    } on HospitalFormPdfException {
      rethrow;
    } on PostgrestException catch (error) {
      debugPrint(
        'Controlled master PDF evidence lookup failed '
        'using $rpcName: $error',
      );

      /*
       * Patient-safe mode is fail-closed.
       *
       * It must never silently fall back to:
       *
       * corvia_controlled_instance_binding_status
       *
       * because that is the staff/internal evidence endpoint.
       */
      if (patientSafeMode) {
        throw HospitalFormPdfException(
          'The released hospital form could not be securely verified. '
          '${_cleanPostgrestError(error)}',
        );
      }

      return null;
    } catch (error) {
      debugPrint(
        'Controlled master PDF evidence lookup failed '
        'using $rpcName: $error',
      );

      if (patientSafeMode) {
        throw HospitalFormPdfException(
          'The released hospital form could not be securely verified. '
          '${error.toString().replaceFirst('Exception: ', '').trim()}',
        );
      }

      return null;
    }
  }

  // ==========================================================================
  // ANSWER PROCESSING
  // ==========================================================================

  List<HospitalFormPdfAnswer> _buildAnswers({
    required List<Map<String, dynamic>> fields,
    required List<Map<String, dynamic>> values,
    required bool patientVisibleOnly,
  }) {
    /*
     * The real Corvia relationship is:
     *
     * hospital_form_instance_values.field_id
     *        ↓
     * hospital_form_template_fields.id
     *
     * field_key remains as a compatibility fallback.
     */
    final fieldsById = <String, Map<String, dynamic>>{};

    final fieldsByKey = <String, Map<String, dynamic>>{};

    for (final field in fields) {
      final fieldId = _cleanId(
        field['id'],
      );

      final fieldKey = _cleanId(
        field['field_key'],
      );

      if (fieldId != null) {
        fieldsById[fieldId] = field;
      }

      if (fieldKey != null) {
        fieldsByKey[fieldKey] = field;
      }
    }

    final sortedValues = List<Map<String, dynamic>>.from(
      values,
    );

    sortedValues.sort(
      (
        first,
        second,
      ) {
        final firstDate = _rowDate(first) ?? DateTime(1970);

        final secondDate = _rowDate(second) ?? DateTime(1970);

        return firstDate.compareTo(
          secondDate,
        );
      },
    );

    final latestByField = <String, Map<String, dynamic>>{};

    for (final value in sortedValues) {
      final fieldId = _cleanId(
        value['field_id'],
      );

      final fieldKey = _cleanId(
        value['field_key'],
      );

      final identity = fieldId ?? fieldKey;

      if (identity == null) {
        continue;
      }

      latestByField[identity] = value;
    }

    final answers = <HospitalFormPdfAnswer>[];

    for (final entry in latestByField.entries) {
      final value = entry.value;

      final valueFieldId = _cleanId(
        value['field_id'],
      );

      final valueFieldKey = _cleanId(
        value['field_key'],
      );

      final Map<String, dynamic>? field;

      if (valueFieldId != null) {
        field = fieldsById[valueFieldId];
      } else if (valueFieldKey != null) {
        field = fieldsByKey[valueFieldKey];
      } else {
        field = null;
      }

      final resolvedFieldKey = _cleanId(
            field?['field_key'],
          ) ??
          valueFieldKey ??
          valueFieldId ??
          entry.key;

      /*
       * Defence in depth.
       *
       * Patient-safe database RLS already filters instance values
       * through corvia_form_can_read_value(id).
       *
       * Flutter independently enforces the field visibility flag.
       *
       * Missing field definitions are NEVER patient-visible.
       */
      if (patientVisibleOnly &&
          !_isPatientVisible(
            field,
          )) {
        continue;
      }

      if (_isInformationField(
        field,
      )) {
        continue;
      }

      final displayValue = _displayFormValue(
        value,
      );

      if (displayValue.trim().isEmpty) {
        continue;
      }

      answers.add(
        HospitalFormPdfAnswer(
          fieldKey: resolvedFieldKey,
          label: _firstText(
            [
              field?['field_label'],
              field?['label'],
              field?['title'],
              field?['name'],
              resolvedFieldKey,
            ],
            fallback: _prettyStatus(
              resolvedFieldKey,
            ),
          ),
          section: _firstText(
            [
              field?['section_title'],
              field?['section'],
              field?['section_label'],
              field?['section_key'],
            ],
            fallback: 'Form Details',
          ),
          fieldType: _firstText(
            [
              field?['field_type'],
              field?['type'],
            ],
            fallback: 'text',
          ),
          displayValue: displayValue,
          order: _fieldOrder(
            field,
          ),
          patientVisible: _isPatientVisible(
            field,
          ),
          updatedAt: _rowDate(
            value,
          ),
        ),
      );
    }

    answers.sort(
      (
        first,
        second,
      ) {
        final sectionCompare = first.section.toLowerCase().compareTo(
              second.section.toLowerCase(),
            );

        if (sectionCompare != 0) {
          return sectionCompare;
        }

        final orderCompare = first.order.compareTo(
          second.order,
        );

        if (orderCompare != 0) {
          return orderCompare;
        }

        return first.label.toLowerCase().compareTo(
              second.label.toLowerCase(),
            );
      },
    );

    return answers;
  }

  Map<String, List<HospitalFormPdfAnswer>> _groupAnswersBySection(
    List<HospitalFormPdfAnswer> answers,
  ) {
    final result = <String, List<HospitalFormPdfAnswer>>{};

    for (final answer in answers) {
      final section = answer.section.trim().isEmpty
          ? 'Form Details'
          : answer.section.trim();

      result
          .putIfAbsent(
            section,
            () => [],
          )
          .add(
            answer,
          );
    }

    return result;
  }

  bool _isPatientVisible(
    Map<String, dynamic>? field,
  ) {
    /*
     * Confirmed database schema:
     *
     * is_patient_visible BOOLEAN
     * NOT NULL
     * DEFAULT FALSE
     *
     * Therefore this must fail closed.
     */
    if (field == null) {
      return false;
    }

    return _asBool(
      field['is_patient_visible'],
      fallback: false,
    );
  }

  bool _isInformationField(
    Map<String, dynamic>? field,
  ) {
    if (field == null) {
      return false;
    }

    final explicit = field['is_information'];

    if (explicit != null) {
      return _asBool(
        explicit,
        fallback: false,
      );
    }

    final type = _firstText(
      [
        field['field_type'],
        field['type'],
      ],
      fallback: '',
    ).toLowerCase();

    return type == 'information' ||
        type == 'info' ||
        type == 'heading' ||
        type == 'section' ||
        type == 'divider';
  }

  int _fieldOrder(
    Map<String, dynamic>? field,
  ) {
    if (field == null) {
      return 999999;
    }

    for (final key in const [
      'sort_order',
      'display_order',
      'field_order',
      'position',
      'order_index',
    ]) {
      final value = field[key];

      if (value == null) {
        continue;
      }

      if (value is int) {
        return value;
      }

      final parsed = int.tryParse(
        value.toString(),
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return 999999;
  }

  String _displayFormValue(
    Map<String, dynamic> row,
  ) {
    final directText = _firstText(
      [
        row['value_text'],
        row['display_value'],
      ],
      fallback: '',
    );

    if (directText.isNotEmpty) {
      return directText;
    }

    final value = row['value'];

    if (value == null) {
      return '';
    }

    return _displayDynamicValue(
      value,
    );
  }

  String _displayDynamicValue(
    dynamic value,
  ) {
    if (value == null) {
      return '';
    }

    if (value is bool) {
      return value ? 'Yes' : 'No';
    }

    if (value is num) {
      return value.toString();
    }

    if (value is String) {
      final clean = value.trim();

      if (clean.isEmpty) {
        return '';
      }

      if ((clean.startsWith('{') && clean.endsWith('}')) ||
          (clean.startsWith('[') && clean.endsWith(']'))) {
        try {
          final decoded = jsonDecode(
            clean,
          );

          return _displayDynamicValue(
            decoded,
          );
        } catch (_) {}
      }

      return clean;
    }

    if (value is List) {
      if (value.isEmpty) {
        return '';
      }

      return value
          .map(
            (
              item,
            ) =>
                _displayDynamicValue(
              item,
            ),
          )
          .where(
            (
              item,
            ) =>
                item.trim().isNotEmpty,
          )
          .join(
            ', ',
          );
    }

    if (value is Map) {
      if (value.isEmpty) {
        return '';
      }

      final lines = <String>[];

      value.forEach(
        (
          key,
          nestedValue,
        ) {
          final display = _displayDynamicValue(
            nestedValue,
          );

          if (display.trim().isEmpty) {
            return;
          }

          lines.add(
            '${_prettyStatus(key.toString())}: '
            '$display',
          );
        },
      );

      return lines.join(
        '\n',
      );
    }

    return value.toString();
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  void _validatePatientRelease(
    Map<String, dynamic> instance,
  ) {
    final status = _normalise(
      instance['status'],
    );

    final finalized = status == 'finalized' ||
        status == 'finalised' ||
        status == 'completed' ||
        instance['finalized_at'] != null ||
        instance['finalised_at'] != null ||
        instance['completed_at'] != null;

    final released = _firstBool(
          [
            instance['released_to_patient'],
            instance['patient_released'],
            instance['is_released_to_patient'],
          ],
          fallback: false,
        ) ||
        instance['released_to_patient_at'] != null ||
        instance['patient_released_at'] != null ||
        instance['released_at'] != null;

    if (!finalized) {
      throw const HospitalFormPdfException(
        'This hospital form has not been finalized.',
      );
    }

    if (!released) {
      throw const HospitalFormPdfException(
        'This hospital form has not been released to the patient.',
      );
    }
  }

  bool _hasAdmissionContext(
    HospitalFormPdfDocumentData data,
  ) {
    return data.admissionId != null ||
        data.admissionNumber.isNotEmpty ||
        data.wardName.isNotEmpty ||
        data.roomName.isNotEmpty ||
        data.bedName.isNotEmpty;
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  List<Map<String, dynamic>> _rows(
    dynamic response,
  ) {
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map(
          (
            row,
          ) =>
              Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  String? _cleanId(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return fallback;
  }

  bool _firstBool(
    List<dynamic> values, {
    required bool fallback,
  }) {
    for (final value in values) {
      if (value == null) {
        continue;
      }

      return _asBool(
        value,
        fallback: fallback,
      );
    }

    return fallback;
  }

  bool _asBool(
    dynamic value, {
    required bool fallback,
  }) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase();

    if (text == null || text.isEmpty) {
      return fallback;
    }

    if (text == 'true' || text == '1' || text == 'yes' || text == 'y') {
      return true;
    }

    if (text == 'false' || text == '0' || text == 'no' || text == 'n') {
      return false;
    }

    return fallback;
  }

  DateTime? _firstDate(
    Map<String, dynamic> row,
    List<String> candidates,
  ) {
    for (final candidate in candidates) {
      final value = row[candidate];

      if (value == null) {
        continue;
      }

      if (value is DateTime) {
        return value.toLocal();
      }

      final parsed = DateTime.tryParse(
        value.toString(),
      );

      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    return null;
  }

  DateTime? _rowDate(
    Map<String, dynamic> row,
  ) {
    return _firstDate(
      row,
      const [
        'updated_at',
        'created_at',
        'recorded_at',
        'saved_at',
        'amended_at',
      ],
    );
  }

  String _patientDisplayName({
    required Map<String, dynamic>? patient,
    required Map<String, dynamic>? profile,
  }) {
    final direct = _firstText(
      [
        profile?['full_name'],
        profile?['display_name'],
        profile?['name'],
        patient?['full_name'],
        patient?['display_name'],
        patient?['name'],
      ],
      fallback: '',
    );

    if (direct.isNotEmpty) {
      return direct;
    }

    final firstName = _firstText(
      [
        profile?['first_name'],
        profile?['firstname'],
        patient?['first_name'],
        patient?['firstname'],
      ],
      fallback: '',
    );

    final surname = _firstText(
      [
        profile?['surname'],
        profile?['last_name'],
        patient?['surname'],
        patient?['last_name'],
      ],
      fallback: '',
    );

    final combined = '$firstName $surname'.trim();

    if (combined.isNotEmpty) {
      return combined;
    }

    return _firstText(
      [
        profile?['email'],
        patient?['email'],
      ],
      fallback: 'Patient',
    );
  }

  String _normalise(
    dynamic value,
  ) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll(
              '-',
              '_',
            )
            .replaceAll(
              ' ',
              '_',
            ) ??
        '';
  }

  String _prettyStatus(
    String value,
  ) {
    final cleaned = value
        .trim()
        .replaceAll(
          '_',
          ' ',
        )
        .replaceAll(
          '-',
          ' ',
        );

    if (cleaned.isEmpty) {
      return 'Unknown';
    }

    return cleaned
        .split(
          RegExp(
            r'\s+',
          ),
        )
        .where(
          (
            word,
          ) =>
              word.isNotEmpty,
        )
        .map(
      (
        word,
      ) {
        if (word.length == 1) {
          return word.toUpperCase();
        }

        return '${word[0].toUpperCase()}'
            '${word.substring(1).toLowerCase()}';
      },
    ).join(
      ' ',
    );
  }

  String _safeFilePart(
    String value,
  ) {
    var result = value.trim();

    if (result.isEmpty) {
      return 'Form';
    }

    result = result.replaceAll(
      RegExp(
        r'[<>:"/\\|?*]',
      ),
      '_',
    );

    result = result.replaceAll(
      RegExp(
        r'\s+',
      ),
      '_',
    );

    result = result.replaceAll(
      RegExp(
        r'_+',
      ),
      '_',
    );

    if (result.length > 60) {
      result = result.substring(
        0,
        60,
      );
    }

    return result;
  }

  String _shortId(
    String value,
  ) {
    final clean = value.trim();

    if (clean.length <= 8) {
      return clean;
    }

    return clean.substring(
      0,
      8,
    );
  }

  String _formatDateOnly(
    DateTime date,
  ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatDateTime(
    DateTime date,
  ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatNullableDateTime(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Not recorded';
    }

    return _formatDateTime(
      date,
    );
  }

  String? _emptyToNull(
    String? value,
  ) {
    final clean = value?.trim();

    if (clean == null || clean.isEmpty) {
      return null;
    }

    return clean;
  }

  String _cleanPostgrestError(
    PostgrestException error,
  ) {
    final details = error.details?.toString().trim() ?? '';

    if (details.isNotEmpty &&
        details.toLowerCase() != 'null' &&
        details != error.message) {
      return '${error.message} $details';
    }

    return error.message;
  }
}

// ============================================================================
// DOCUMENT DATA MODEL
// ============================================================================

class HospitalFormPdfDocumentData {
  const HospitalFormPdfDocumentData({
    required this.instanceId,
    required this.patientId,
    required this.templateId,
    required this.templateVersionId,
    required this.formTitle,
    required this.formCode,
    required this.category,
    required this.description,
    required this.documentClassification,
    required this.versionLabel,
    required this.languageCode,
    required this.status,
    required this.demoOnly,
    required this.productionApproved,
    required this.officialLayoutRequired,
    required this.patientSafeMode,
    required this.hospitalName,
    required this.patientName,
    required this.patientNumber,
    required this.patientIdNumber,
    required this.admissionNumber,
    required this.wardName,
    required this.roomName,
    required this.bedName,
    required this.answers,
    required this.signatures,
    required this.rawInstance,
    required this.generatedAt,
    this.attachments = const [],
    this.hospitalId,
    this.admissionId,
    this.patientDateOfBirth,
    this.createdAt,
    this.submittedAt,
    this.finalizedAt,
    this.releasedToPatientAt,
    this.rawTemplate,
    this.rawVersion,
    this.controlledBindingEvidence,
  });

  final String instanceId;
  final String? hospitalId;
  final String patientId;
  final String? admissionId;

  final String templateId;
  final String templateVersionId;

  final String formTitle;
  final String formCode;
  final String category;
  final String description;
  final String documentClassification;

  final String versionLabel;
  final String languageCode;
  final String status;

  final bool demoOnly;
  final bool productionApproved;
  final bool officialLayoutRequired;

  /*
   * True only when Corvia is generating the released
   * patient-safe document path.
   */
  final bool patientSafeMode;

  final String hospitalName;

  final String patientName;
  final String patientNumber;
  final String patientIdNumber;
  final DateTime? patientDateOfBirth;

  final String admissionNumber;
  final String wardName;
  final String roomName;
  final String bedName;

  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? finalizedAt;
  final DateTime? releasedToPatientAt;

  final List<HospitalFormPdfAnswer> answers;

  final List<HospitalFormPdfSignature> signatures;

  final List<HospitalFormPdfAttachment> attachments;

  final Map<String, dynamic> rawInstance;
  final Map<String, dynamic>? rawTemplate;
  final Map<String, dynamic>? rawVersion;

  final HospitalFormPdfControlledBindingEvidence? controlledBindingEvidence;

  final DateTime generatedAt;

  bool get isFinalized {
    final normalized = status
        .trim()
        .toLowerCase()
        .replaceAll(
          '-',
          '_',
        )
        .replaceAll(
          ' ',
          '_',
        );

    return normalized == 'finalized' ||
        normalized == 'finalised' ||
        normalized == 'completed' ||
        finalizedAt != null;
  }

  bool get isReleasedToPatient {
    return releasedToPatientAt != null;
  }

  bool get isControlledForm {
    return controlledBindingEvidence?.isControlledForm ?? false;
  }

  bool get hasControlledMasterBinding {
    return controlledBindingEvidence?.isBound ?? false;
  }

  bool get hasVerifiedOfficialMaster {
    final controlled = controlledBindingEvidence;

    if (controlled == null || !controlled.isControlledForm) {
      return true;
    }

    return controlled.verified &&
        controlled.isBound &&
        controlled.productionApproved;
  }

  bool get isProductionReady {
    if (!productionApproved || demoOnly) {
      return false;
    }

    final controlled = controlledBindingEvidence;

    if (controlled == null || !controlled.isControlledForm) {
      return true;
    }

    return controlled.isBound &&
        controlled.productionApproved &&
        controlled.verified;
  }
}

// ============================================================================
// CONTROLLED MASTER EVIDENCE MODEL
// ============================================================================

class HospitalFormPdfControlledBindingEvidence {
  const HospitalFormPdfControlledBindingEvidence({
    required this.instanceId,
    required this.isControlledForm,
    required this.bindingRequired,
    required this.isBound,
    required this.verified,
    required this.registryProductionApproved,
    required this.productionApproved,
    this.hospitalId,
    this.templateId,
    this.bindingId = '',
    this.boundAt,
    this.boundBy = '',
    this.registryId = '',
    this.formCode = '',
    this.officialFormName = '',
    this.registryProductionStatus = '',
    this.currentControlledVersionId,
    this.controlledVersionId = '',
    this.versionNumber,
    this.versionLabel = '',
    this.officialFormNumber = '',
    this.officialVersionReference = '',
    this.officialRevisionReference = '',
    this.effectiveOn,
    this.retiredOn,
    this.approvedAt,
    this.approvalStatus = '',
    this.sourceDocumentName = '',
    this.storageBucket = '',
    this.storagePath = '',
    this.sha256 = '',
    this.bindingMetadata = const {},
  });

  final String instanceId;

  final String? hospitalId;
  final String? templateId;

  final bool isControlledForm;
  final bool bindingRequired;
  final bool isBound;

  /*
   * Safe high-level verification state.
   *
   * For staff/admin data this may be derived from the exact
   * production-approved bound master.
   *
   * For patient data this comes from:
   *
   * corvia_controlled_patient_instance_verification
   */
  final bool verified;

  final String bindingId;
  final DateTime? boundAt;
  final String boundBy;

  final Map<String, dynamic> bindingMetadata;

  final String registryId;
  final String formCode;
  final String officialFormName;

  final String registryProductionStatus;
  final bool registryProductionApproved;

  final String? currentControlledVersionId;

  final String controlledVersionId;

  final int? versionNumber;
  final String versionLabel;

  final String officialFormNumber;
  final String officialVersionReference;
  final String officialRevisionReference;

  final DateTime? effectiveOn;
  final DateTime? retiredOn;
  final DateTime? approvedAt;

  final String approvalStatus;
  final bool productionApproved;

  final String sourceDocumentName;

  final String storageBucket;
  final String storagePath;

  final String sha256;

  factory HospitalFormPdfControlledBindingEvidence.fromMap(
    Map<String, dynamic> map,
  ) {
    final isControlledForm = _modelBool(
      map['is_controlled_form'],
    );

    final isBound = _modelBool(
      map['is_bound'],
    );

    final productionApproved = _modelBool(
      map['production_approved'],
    );

    final explicitVerified = _modelBool(
      map['verified'],
    );

    /*
     * Staff RPCs may not expose a dedicated verified property.
     *
     * In staff/admin mode, an approved exact immutable binding
     * is enough for the current PDF UI to regard the master as
     * verified.
     *
     * Patient mode gets an explicit safe verified property from
     * its dedicated patient-safe RPC.
     */
    final verified = explicitVerified ||
        (isControlledForm && isBound && productionApproved) ||
        !isControlledForm;

    return HospitalFormPdfControlledBindingEvidence(
      instanceId: _modelString(
        map['instance_id'],
      ),
      hospitalId: _modelNullableString(
        map['hospital_id'],
      ),
      templateId: _modelNullableString(
        map['template_id'],
      ),
      isControlledForm: isControlledForm,
      bindingRequired: _modelBool(
        map['binding_required'],
      ),
      isBound: isBound,
      verified: verified,
      bindingId: _modelString(
        map['binding_id'],
      ),
      boundAt: _modelDate(
        map['bound_at'],
      ),
      boundBy: _modelString(
        map['bound_by'],
      ),
      bindingMetadata: map['binding_metadata'] is Map
          ? Map<String, dynamic>.from(
              map['binding_metadata'] as Map,
            )
          : const {},
      registryId: _modelString(
        map['registry_id'],
      ),
      formCode: _modelString(
        map['form_code'],
      ),
      officialFormName: _modelString(
        map['official_form_name'],
      ),
      registryProductionStatus: _modelString(
        map['registry_production_status'],
      ),
      registryProductionApproved: _modelBool(
        map['registry_production_approved'],
      ),
      currentControlledVersionId: _modelNullableString(
        map['current_controlled_version_id'],
      ),
      controlledVersionId: _modelString(
        map['controlled_version_id'],
      ),
      versionNumber: _modelInt(
        map['version_number'],
      ),
      versionLabel: _modelString(
        map['version_label'],
      ),
      officialFormNumber: _modelString(
        map['official_form_number'],
      ),
      officialVersionReference: _modelString(
        map['official_version_reference'],
      ),
      officialRevisionReference: _modelString(
        map['official_revision_reference'],
      ),
      effectiveOn: _modelDate(
        map['effective_on'],
      ),
      retiredOn: _modelDate(
        map['retired_on'],
      ),
      approvedAt: _modelDate(
        map['approved_at'],
      ),
      approvalStatus: _modelString(
        map['approval_status'],
      ),
      productionApproved: productionApproved,
      sourceDocumentName: _modelString(
        map['source_document_name'],
      ),
      storageBucket: _modelString(
        map['storage_bucket'],
      ),
      storagePath: _modelString(
        map['storage_path'],
      ),
      sha256: _modelString(
        map['sha256'],
      ),
    );
  }

  static String _modelString(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return '';
    }

    return text;
  }

  static String? _modelNullableString(
    dynamic value,
  ) {
    final text = _modelString(
      value,
    );

    return text.isEmpty ? null : text;
  }

  static bool _modelBool(
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

  static int? _modelInt(
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

  static DateTime? _modelDate(
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
}

// ============================================================================
// ANSWER MODEL
// ============================================================================

class HospitalFormPdfAnswer {
  const HospitalFormPdfAnswer({
    required this.fieldKey,
    required this.label,
    required this.section,
    required this.fieldType,
    required this.displayValue,
    required this.order,
    required this.patientVisible,
    this.updatedAt,
  });

  final String fieldKey;
  final String label;
  final String section;
  final String fieldType;
  final String displayValue;
  final int order;
  final bool patientVisible;
  final DateTime? updatedAt;
}

// ============================================================================
// SIGNATURE MODEL
// ============================================================================

class HospitalFormPdfSignature {
  const HospitalFormPdfSignature({
    required this.id,
    required this.signerName,
    required this.signerRole,
    required this.signerIdentifier,
    required this.signatureMethod,
    required this.declarationText,
    this.witnessName = '',
    this.isValid = true,
    this.signedAt,
    this.revokedAt,
  });

  factory HospitalFormPdfSignature.fromMap(
    Map<String, dynamic> row,
  ) {
    String firstText(
      List<dynamic> values, {
      required String fallback,
    }) {
      for (final value in values) {
        final text = value?.toString().trim();

        if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
          return text;
        }
      }

      return fallback;
    }

    DateTime? firstDate(
      List<dynamic> values,
    ) {
      for (final value in values) {
        if (value == null) {
          continue;
        }

        if (value is DateTime) {
          return value.toLocal();
        }

        final parsed = DateTime.tryParse(
          value.toString(),
        );

        if (parsed != null) {
          return parsed.toLocal();
        }
      }

      return null;
    }

    bool asBool(
      dynamic value, {
      required bool fallback,
    }) {
      if (value is bool) {
        return value;
      }

      if (value is num) {
        return value != 0;
      }

      final text = value?.toString().trim().toLowerCase();

      if (text == 'true' || text == '1' || text == 'yes' || text == 'y') {
        return true;
      }

      if (text == 'false' || text == '0' || text == 'no' || text == 'n') {
        return false;
      }

      return fallback;
    }

    return HospitalFormPdfSignature(
      id: firstText(
        [
          row['id'],
        ],
        fallback: '',
      ),
      signerName: firstText(
        [
          row['signer_name'],
          row['signed_by_name'],
          row['name'],
        ],
        fallback: 'Electronic Signer',
      ),
      signerRole: firstText(
        [
          row['signer_role'],
          row['role'],
        ],
        fallback: 'signer',
      ),
      /*
       * Patient-safe RPC does not return signer_identifier.
       *
       * Therefore this remains empty in patient-safe mode but
       * remains available for authorised staff/admin PDFs.
       */
      signerIdentifier: firstText(
        [
          row['signer_identifier'],
          row['professional_number'],
          row['identifier'],
        ],
        fallback: '',
      ),
      signatureMethod: firstText(
        [
          row['signature_method'],
          row['method'],
        ],
        fallback: 'electronic',
      ),
      declarationText: firstText(
        [
          row['declaration_text'],
          row['declaration'],
        ],
        fallback: '',
      ),
      witnessName: firstText(
        [
          row['witness_name'],
        ],
        fallback: '',
      ),
      isValid: asBool(
        row['is_valid'],
        fallback: true,
      ),
      signedAt: firstDate(
        [
          row['signed_at'],
          row['created_at'],
        ],
      ),
      revokedAt: firstDate(
        [
          row['revoked_at'],
        ],
      ),
    );
  }

  final String id;
  final String signerName;
  final String signerRole;
  final String signerIdentifier;
  final String signatureMethod;
  final String declarationText;

  final String witnessName;
  final bool isValid;

  final DateTime? signedAt;
  final DateTime? revokedAt;
}

// ============================================================================
// ATTACHMENT MODEL
// ============================================================================

class HospitalFormPdfAttachment {
  const HospitalFormPdfAttachment({
    required this.attachmentType,
    required this.fileName,
    required this.mimeType,
    required this.description,
    required this.documentClassification,
    this.fileSizeBytes,
    this.uploadedAt,
  });

  factory HospitalFormPdfAttachment.fromMap(
    Map<String, dynamic> row,
  ) {
    String firstText(
      List<dynamic> values, {
      required String fallback,
    }) {
      for (final value in values) {
        final text = value?.toString().trim();

        if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
          return text;
        }
      }

      return fallback;
    }

    int? firstInt(
      List<dynamic> values,
    ) {
      for (final value in values) {
        if (value == null) {
          continue;
        }

        if (value is int) {
          return value;
        }

        final parsed = int.tryParse(
          value.toString(),
        );

        if (parsed != null) {
          return parsed;
        }
      }

      return null;
    }

    DateTime? firstDate(
      List<dynamic> values,
    ) {
      for (final value in values) {
        if (value == null) {
          continue;
        }

        if (value is DateTime) {
          return value.toLocal();
        }

        final parsed = DateTime.tryParse(
          value.toString(),
        );

        if (parsed != null) {
          return parsed.toLocal();
        }
      }

      return null;
    }

    return HospitalFormPdfAttachment(
      attachmentType: firstText(
        [
          row['attachment_type'],
        ],
        fallback: 'supporting_document',
      ),
      fileName: firstText(
        [
          row['file_name'],
        ],
        fallback: '',
      ),
      mimeType: firstText(
        [
          row['mime_type'],
        ],
        fallback: '',
      ),
      fileSizeBytes: firstInt(
        [
          row['file_size_bytes'],
        ],
      ),
      description: firstText(
        [
          row['description'],
        ],
        fallback: '',
      ),
      documentClassification: firstText(
        [
          row['document_classification'],
        ],
        fallback: '',
      ),
      uploadedAt: firstDate(
        [
          row['uploaded_at'],
        ],
      ),
    );
  }

  final String attachmentType;
  final String fileName;
  final String mimeType;

  final int? fileSizeBytes;

  final String description;
  final String documentClassification;

  final DateTime? uploadedAt;
}

// ============================================================================
// EXCEPTION
// ============================================================================

class HospitalFormPdfException implements Exception {
  const HospitalFormPdfException(
    this.message,
  );

  final String message;

  @override
  String toString() {
    return message;
  }
}
