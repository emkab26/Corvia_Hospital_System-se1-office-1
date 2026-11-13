import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prescription_model.dart';

/// Handles prescription CRUD operations and related business rules.
///
/// Important ID rules:
/// - prescriptions.doctor_id references doctors.id
/// - prescriptions.patient_id references patients.id
/// - prescriptions.created_by references profiles.user_id / auth.users.id
/// - prescriptions.hospital_id is resolved from the signed-in doctor
class PrescriptionRepository {
  PrescriptionRepository({
    SupabaseClient? supabase,
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const Set<String> _allowedStatuses = {
    'active',
    'completed',
    'cancelled',
  };

  /// Creates a prescription and lets the database trigger create the
  /// corresponding prescription_dispenses pharmacy queue record.
  Future<String> createPrescription(
    Prescription prescription,
  ) async {
    try {
      _validatePrescription(
        prescription,
        creating: true,
      );

      final doctorContext = await _resolveDoctorContext(
        prescription.doctorId,
      );

      await _validatePatientHospital(
        patientId: prescription.patientId,
        hospitalId: doctorContext.hospitalId,
      );

      final payload = prescription.toInsertMap()
        ..['doctor_id'] = doctorContext.doctorId
        ..['hospital_id'] = doctorContext.hospitalId
        ..['created_by'] = doctorContext.authUserId
        ..['status'] = _normaliseStatus(
          prescription.status,
        );

      final cleanedPayload = _withoutNullValues(
        payload,
      );

      final result = await _supabase
          .from('prescriptions')
          .insert(cleanedPayload)
          .select(
            'id, patient_id, doctor_id, hospital_id, '
            'created_by, status',
          )
          .single();

      final prescriptionId = _requiredText(
        result['id'],
        fieldName: 'Prescription ID',
      );

      await _tryAddPrescriptionLog(
        prescriptionId: prescriptionId,
        action: 'created',
        performedBy: doctorContext.authUserId,
      );

      return prescriptionId;
    } catch (error) {
      throw Exception(
        'Failed to create prescription: ${_cleanError(error)}',
      );
    }
  }

  /// Returns a live stream of prescriptions belonging to one patient.
  Stream<List<Prescription>> getPatientPrescriptions(
    String patientId,
  ) {
    final cleanPatientId = patientId.trim();

    if (cleanPatientId.isEmpty) {
      return Stream<List<Prescription>>.value(
        const [],
      );
    }

    return _supabase
        .from('prescriptions')
        .stream(
          primaryKey: ['id'],
        )
        .eq(
          'patient_id',
          cleanPatientId,
        )
        .order(
          'issued_at',
          ascending: false,
        )
        .map(
          (rows) => rows
              .map(
                (row) => Prescription.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(),
        );
  }

  /// Returns a live stream of prescriptions issued by one doctor.
  Stream<List<Prescription>> getDoctorPrescriptions(
    String doctorId,
  ) {
    final cleanDoctorId = doctorId.trim();

    if (cleanDoctorId.isEmpty) {
      return Stream<List<Prescription>>.value(
        const [],
      );
    }

    return _supabase
        .from('prescriptions')
        .stream(
          primaryKey: ['id'],
        )
        .eq(
          'doctor_id',
          cleanDoctorId,
        )
        .order(
          'issued_at',
          ascending: false,
        )
        .map(
          (rows) => rows
              .map(
                (row) => Prescription.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(),
        );
  }

  /// Updates only editable prescription fields.
  ///
  /// Patient, doctor, hospital, creator and original issue date cannot be
  /// moved through this method.
  Future<void> updatePrescription(
    Prescription prescription,
  ) async {
    try {
      _validatePrescription(
        prescription,
        creating: false,
      );

      final prescriptionId = prescription.id.trim();

      if (prescriptionId.isEmpty) {
        throw Exception(
          'The prescription has no valid ID.',
        );
      }

      final doctorContext = await _resolveDoctorContext(
        prescription.doctorId,
      );

      final existing = await _supabase
          .from('prescriptions')
          .select(
            'id, patient_id, doctor_id, hospital_id, status',
          )
          .eq(
            'id',
            prescriptionId,
          )
          .eq(
            'doctor_id',
            doctorContext.doctorId,
          )
          .maybeSingle();

      if (existing == null) {
        throw Exception(
          'The prescription was not found or does not belong '
          'to the signed-in doctor.',
        );
      }

      final existingPatientId = _requiredText(
        existing['patient_id'],
        fieldName: 'Patient ID',
      );

      if (existingPatientId != prescription.patientId.trim()) {
        throw Exception(
          'A prescription cannot be moved to another patient.',
        );
      }

      final existingHospitalId = _nullableText(
        existing['hospital_id'],
      );

      if (existingHospitalId != null &&
          existingHospitalId != doctorContext.hospitalId) {
        throw Exception(
          'The prescription belongs to another hospital.',
        );
      }

      final payload = prescription.toUpdateMap()
        ..['status'] = _normaliseStatus(
          prescription.status,
        );

      final updated = await _supabase
          .from('prescriptions')
          .update(
            _withoutNullValues(payload),
          )
          .eq(
            'id',
            prescriptionId,
          )
          .eq(
            'doctor_id',
            doctorContext.doctorId,
          )
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception(
          'The prescription update did not change a record.',
        );
      }

      await _tryAddPrescriptionLog(
        prescriptionId: prescriptionId,
        action: 'updated',
        performedBy: doctorContext.authUserId,
      );
    } catch (error) {
      throw Exception(
        'Failed to update prescription: ${_cleanError(error)}',
      );
    }
  }

  /// Marks active prescriptions with expired course dates as completed.
  ///
  /// This remains best-effort because the UI also calculates
  /// [Prescription.effectiveStatus].
  Future<void> autoCompleteExpired(
    String doctorId,
  ) async {
    try {
      final doctorContext = await _resolveDoctorContext(
        doctorId,
      );

      await _supabase
          .from('prescriptions')
          .update({
            'status': 'completed',
          })
          .eq(
            'doctor_id',
            doctorContext.doctorId,
          )
          .eq(
            'hospital_id',
            doctorContext.hospitalId,
          )
          .eq(
            'status',
            'active',
          )
          .not(
            'end_date',
            'is',
            null,
          )
          .lt(
            'end_date',
            DateTime.now().toUtc().toIso8601String(),
          );
    } catch (error) {
      debugPrint(
        'Prescription auto-complete skipped: '
        '${_cleanError(error)}',
      );
    }
  }

  /// Consumes one authorised refill.
  ///
  /// The conditional update prevents two devices from consuming the same
  /// refill count at the same time.
  Future<void> fulfillRefill({
    required String prescriptionId,
  }) async {
    try {
      final cleanPrescriptionId = prescriptionId.trim();

      if (cleanPrescriptionId.isEmpty) {
        throw Exception(
          'The prescription ID is required.',
        );
      }

      final row = await _supabase
          .from('prescriptions')
          .select(
            'id, doctor_id, status, refillable, '
            'refills_used, refills_allowed, refill_requested',
          )
          .eq(
            'id',
            cleanPrescriptionId,
          )
          .maybeSingle();

      if (row == null) {
        throw Exception(
          'The prescription could not be found.',
        );
      }

      final doctorId = _requiredText(
        row['doctor_id'],
        fieldName: 'Doctor ID',
      );

      final doctorContext = await _resolveDoctorContext(
        doctorId,
      );

      final status = _normaliseStatus(
        row['status']?.toString() ?? 'active',
      );

      if (status != 'active') {
        throw Exception(
          'Only active prescriptions can receive a refill.',
        );
      }

      if (row['refillable'] != true) {
        throw Exception(
          'This prescription is not repeatable.',
        );
      }

      if (row['refill_requested'] != true) {
        throw Exception(
          'There is no pending refill request.',
        );
      }

      final used = (row['refills_used'] as num?)?.toInt() ?? 0;

      final allowed = (row['refills_allowed'] as num?)?.toInt() ?? 0;

      if (used >= allowed) {
        throw Exception(
          'No refills remaining.',
        );
      }

      final updated = await _supabase
          .from('prescriptions')
          .update({
            'refills_used': used + 1,
            'refill_requested': false,
            'refill_requested_at': null,
          })
          .eq(
            'id',
            cleanPrescriptionId,
          )
          .eq(
            'doctor_id',
            doctorContext.doctorId,
          )
          .eq(
            'refills_used',
            used,
          )
          .eq(
            'refill_requested',
            true,
          )
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception(
          'The refill changed before it could be completed. '
          'Refresh and try again.',
        );
      }

      await _tryAddPrescriptionLog(
        prescriptionId: cleanPrescriptionId,
        action: 'refill_fulfilled',
        performedBy: doctorContext.authUserId,
      );
    } catch (error) {
      throw Exception(
        'Failed to fulfil refill: ${_cleanError(error)}',
      );
    }
  }

  /// Declines a pending refill without consuming a refill.
  Future<void> declineRefill(
    String prescriptionId,
  ) async {
    try {
      final cleanPrescriptionId = prescriptionId.trim();

      if (cleanPrescriptionId.isEmpty) {
        throw Exception(
          'The prescription ID is required.',
        );
      }

      final row = await _supabase
          .from('prescriptions')
          .select(
            'id, doctor_id, refill_requested',
          )
          .eq(
            'id',
            cleanPrescriptionId,
          )
          .maybeSingle();

      if (row == null) {
        throw Exception(
          'The prescription could not be found.',
        );
      }

      final doctorContext = await _resolveDoctorContext(
        _requiredText(
          row['doctor_id'],
          fieldName: 'Doctor ID',
        ),
      );

      if (row['refill_requested'] != true) {
        throw Exception(
          'There is no pending refill request.',
        );
      }

      final updated = await _supabase
          .from('prescriptions')
          .update({
            'refill_requested': false,
            'refill_requested_at': null,
          })
          .eq(
            'id',
            cleanPrescriptionId,
          )
          .eq(
            'doctor_id',
            doctorContext.doctorId,
          )
          .eq(
            'refill_requested',
            true,
          )
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception(
          'The refill request was already changed.',
        );
      }

      await _tryAddPrescriptionLog(
        prescriptionId: cleanPrescriptionId,
        action: 'refill_declined',
        performedBy: doctorContext.authUserId,
      );
    } catch (error) {
      throw Exception(
        'Failed to decline refill: ${_cleanError(error)}',
      );
    }
  }

  /// Updates a prescription status after validating doctor ownership.
  Future<void> updatePrescriptionStatus({
    required String prescriptionId,
    required String status,
    required String performedBy,
  }) async {
    try {
      final cleanPrescriptionId = prescriptionId.trim();

      if (cleanPrescriptionId.isEmpty) {
        throw Exception(
          'The prescription ID is required.',
        );
      }

      final cleanStatus = _normaliseStatus(
        status,
      );

      final row = await _supabase
          .from('prescriptions')
          .select(
            'id, doctor_id, status',
          )
          .eq(
            'id',
            cleanPrescriptionId,
          )
          .maybeSingle();

      if (row == null) {
        throw Exception(
          'The prescription could not be found.',
        );
      }

      final doctorId = _requiredText(
        row['doctor_id'],
        fieldName: 'Doctor ID',
      );

      final doctorContext = await _resolveDoctorContext(
        doctorId,
      );

      final currentStatus = _normaliseStatus(
        row['status']?.toString() ?? 'active',
      );

      if (currentStatus == cleanStatus) {
        throw Exception(
          'The prescription is already marked as $cleanStatus.',
        );
      }

      final updated = await _supabase
          .from('prescriptions')
          .update({
            'status': cleanStatus,
          })
          .eq(
            'id',
            cleanPrescriptionId,
          )
          .eq(
            'doctor_id',
            doctorContext.doctorId,
          )
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception(
          'The prescription status was not changed.',
        );
      }

      await _tryAddPrescriptionLog(
        prescriptionId: cleanPrescriptionId,
        action: 'status_updated_to_$cleanStatus',
        performedBy: doctorContext.authUserId,
      );
    } catch (error) {
      throw Exception(
        'Failed to update prescription: ${_cleanError(error)}',
      );
    }
  }

  /// Permanently deletes a prescription only when it has not entered the
  /// pharmacy workflow.
  ///
  /// Once a prescription_dispenses record exists, the prescription should be
  /// cancelled rather than deleted so that the medical audit trail remains.
  Future<void> deletePrescription(
    String prescriptionId,
  ) async {
    try {
      final cleanPrescriptionId = prescriptionId.trim();

      if (cleanPrescriptionId.isEmpty) {
        throw Exception(
          'The prescription ID is required.',
        );
      }

      final prescription = await _supabase
          .from('prescriptions')
          .select(
            'id, doctor_id',
          )
          .eq(
            'id',
            cleanPrescriptionId,
          )
          .maybeSingle();

      if (prescription == null) {
        throw Exception(
          'The prescription could not be found.',
        );
      }

      final doctorContext = await _resolveDoctorContext(
        _requiredText(
          prescription['doctor_id'],
          fieldName: 'Doctor ID',
        ),
      );

      final dispense = await _supabase
          .from('prescription_dispenses')
          .select(
            'id, status',
          )
          .eq(
            'prescription_id',
            cleanPrescriptionId,
          )
          .maybeSingle();

      if (dispense != null) {
        final pharmacyStatus = dispense['status']?.toString() ?? 'received';

        throw Exception(
          'This prescription is already in the pharmacy workflow '
          'with status "$pharmacyStatus". Mark the prescription '
          'as cancelled instead of deleting it.',
        );
      }

      final deleted = await _supabase
          .from('prescriptions')
          .delete()
          .eq(
            'id',
            cleanPrescriptionId,
          )
          .eq(
            'doctor_id',
            doctorContext.doctorId,
          )
          .select('id')
          .maybeSingle();

      if (deleted == null) {
        throw Exception(
          'The prescription was not deleted.',
        );
      }

      await _tryAddPrescriptionLog(
        prescriptionId: cleanPrescriptionId,
        action: 'deleted',
        performedBy: doctorContext.authUserId,
      );
    } catch (error) {
      throw Exception(
        'Failed to delete prescription: ${_cleanError(error)}',
      );
    }
  }

  Future<_DoctorContext> _resolveDoctorContext(
    String requestedDoctorId,
  ) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'No active Corvia session was found.',
      );
    }

    final cleanDoctorId = requestedDoctorId.trim();

    if (cleanDoctorId.isEmpty) {
      throw Exception(
        'The doctor ID is required.',
      );
    }

    final doctor = await _supabase
        .from('doctors')
        .select(
          'id, profile_id, hospital_id, is_active',
        )
        .eq(
          'id',
          cleanDoctorId,
        )
        .eq(
          'profile_id',
          user.id,
        )
        .maybeSingle();

    if (doctor == null) {
      throw Exception(
        'The doctor record is not linked to the signed-in account.',
      );
    }

    if (doctor['is_active'] == false) {
      throw Exception(
        'This doctor staff record is inactive.',
      );
    }

    final hospitalId = _requiredText(
      doctor['hospital_id'],
      fieldName: 'Hospital ID',
    );

    return _DoctorContext(
      authUserId: user.id,
      doctorId: _requiredText(
        doctor['id'],
        fieldName: 'Doctor ID',
      ),
      hospitalId: hospitalId,
    );
  }

  Future<void> _validatePatientHospital({
    required String patientId,
    required String hospitalId,
  }) async {
    final cleanPatientId = patientId.trim();

    if (cleanPatientId.isEmpty) {
      throw Exception(
        'The patient ID is required.',
      );
    }

    final patient = await _supabase
        .from('patients')
        .select(
          'id, hospital_id',
        )
        .eq(
          'id',
          cleanPatientId,
        )
        .maybeSingle();

    if (patient == null) {
      throw Exception(
        'The patient record could not be found.',
      );
    }

    final patientHospitalId = _nullableText(
      patient['hospital_id'],
    );

    if (patientHospitalId != null && patientHospitalId != hospitalId) {
      throw Exception(
        'The patient belongs to another hospital.',
      );
    }
  }

  void _validatePrescription(
    Prescription prescription, {
    required bool creating,
  }) {
    if (!creating && prescription.id.trim().isEmpty) {
      throw Exception(
        'The prescription ID is required.',
      );
    }

    if (prescription.patientId.trim().isEmpty) {
      throw Exception(
        'The patient ID is required.',
      );
    }

    if (prescription.doctorId.trim().isEmpty) {
      throw Exception(
        'The doctor ID is required.',
      );
    }

    if (prescription.medicationName.trim().isEmpty) {
      throw Exception(
        'At least one medication is required.',
      );
    }

    final medicines = prescription.allMedicines;

    if (medicines.isEmpty) {
      throw Exception(
        'At least one medication is required.',
      );
    }

    for (final medicine in medicines) {
      if (medicine.name.trim().isEmpty) {
        throw Exception(
          'Every medication requires a name.',
        );
      }
    }

    final cleanStatus = _normaliseStatus(
      prescription.status,
    );

    if (creating && cleanStatus != 'active') {
      throw Exception(
        'A new prescription must start as active.',
      );
    }

    if (prescription.refillable && prescription.refillsAllowed <= 0) {
      throw Exception(
        'A repeatable prescription must allow at least one refill.',
      );
    }

    if (prescription.refillsUsed < 0 || prescription.refillsAllowed < 0) {
      throw Exception(
        'Refill values cannot be negative.',
      );
    }

    if (prescription.refillsUsed > prescription.refillsAllowed) {
      throw Exception(
        'Used refills cannot exceed allowed refills.',
      );
    }
  }

  String _normaliseStatus(
    String status,
  ) {
    final cleaned =
        status.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    if (!_allowedStatuses.contains(cleaned)) {
      throw Exception(
        'Invalid prescription status: $cleaned.',
      );
    }

    return cleaned;
  }

  Future<void> _tryAddPrescriptionLog({
    required String prescriptionId,
    required String action,
    required String performedBy,
  }) async {
    try {
      await _supabase.from('prescription_logs').insert({
        'prescription_id': prescriptionId,
        'action': action,
        'performed_by': performedBy,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (error) {
      // Logging must not make a successful prescription operation appear
      // unsuccessful and cause users to submit duplicates.
      debugPrint(
        'Prescription log skipped '
        '($prescriptionId / $action): '
        '${_cleanError(error)}',
      );
    }
  }

  Map<String, dynamic> _withoutNullValues(
    Map<String, dynamic> source,
  ) {
    final result = <String, dynamic>{};

    source.forEach(
      (key, value) {
        if (value != null) {
          result[key] = value;
        }
      },
    );

    return result;
  }

  String _requiredText(
    dynamic value, {
    required String fieldName,
  }) {
    final text = _nullableText(value);

    if (text == null) {
      throw Exception(
        '$fieldName is missing.',
      );
    }

    return text;
  }

  String? _nullableText(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  String _cleanError(
    Object error,
  ) {
    if (error is PostgrestException) {
      final details = error.details?.toString().trim() ?? '';

      if (details.isNotEmpty &&
          details.toLowerCase() != 'null' &&
          details != error.message) {
        return '${error.message} $details';
      }

      return error.message;
    }

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
  }
}

class _DoctorContext {
  const _DoctorContext({
    required this.authUserId,
    required this.doctorId,
    required this.hospitalId,
  });

  final String authUserId;
  final String doctorId;
  final String hospitalId;
}
