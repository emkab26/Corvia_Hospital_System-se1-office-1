import 'package:supabase_flutter/supabase_flutter.dart';

class VisitorRequestService {
  VisitorRequestService({
    SupabaseClient? supabase,
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List && value.isNotEmpty) {
      return _mapValue(value.first);
    }

    return {};
  }

  String? _nullableText(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  bool _boolValue(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    return value?.toString().toLowerCase() == 'true';
  }

  String? _scalarString(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      return value;
    }

    if (value is List && value.isNotEmpty) {
      return _scalarString(
        value.first,
      );
    }

    if (value is Map && value.isNotEmpty) {
      return _scalarString(
        value.values.first,
      );
    }

    return value.toString();
  }

  // ============================================================
  // VISITOR ACCOUNT LINK
  // ============================================================

  Future<int> linkCurrentVisitorAccount() async {
    final response = await _supabase.rpc(
      'corvia_link_my_visitor_account',
    );

    if (response is int) {
      return response;
    }

    if (response is num) {
      return response.toInt();
    }

    return int.tryParse(
          response?.toString() ?? '',
        ) ??
        0;
  }

  Future<List<Map<String, dynamic>>>
      getMyVisitorAccessPasses() async {
    // Safe self-link before loading.
    await linkCurrentVisitorAccount();

    final response = await _supabase.rpc(
      'corvia_my_visitor_access_passes',
    );

    return _mapList(response);
  }

  // ============================================================
  // PATIENT -> REQUEST A VISITOR
  // ============================================================

  Future<String> createPatientVisitorRequest({
    required String firstName,
    required String surname,
    required String relationship,
    required DateTime requestedVisitAt,
    String? phone,
    String? email,
    String? visitPurpose,
  }) async {
    final cleanFirstName = firstName.trim();
    final cleanSurname = surname.trim();
    final cleanRelationship = relationship.trim();

    if (cleanFirstName.isEmpty) {
      throw Exception(
        'Visitor first name is required.',
      );
    }

    if (cleanSurname.isEmpty) {
      throw Exception(
        'Visitor surname is required.',
      );
    }

    if (cleanRelationship.isEmpty) {
      throw Exception(
        'Relationship to patient is required.',
      );
    }

    if (requestedVisitAt.isBefore(
      DateTime.now().subtract(
        const Duration(minutes: 5),
      ),
    )) {
      throw Exception(
        'Visit time cannot be in the past.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_patient_request_visitor',
      params: {
        'p_first_name': cleanFirstName,
        'p_surname': cleanSurname,
        'p_relationship': cleanRelationship,
        'p_requested_visit_at':
            requestedVisitAt.toUtc().toIso8601String(),
        'p_phone': _nullableText(phone),
        'p_email': _nullableText(email),
        'p_visit_purpose': _nullableText(
          visitPurpose,
        ),
      },
    );

    final requestId =
        _scalarString(response)?.trim() ?? '';

    if (requestId.isEmpty) {
      throw Exception(
        'Visitor request was created without a valid ID.',
      );
    }

    return requestId;
  }

  Future<List<Map<String, dynamic>>>
      getMyVisitorRequests() async {
    final response = await _supabase.rpc(
      'corvia_patient_my_visitor_requests',
    );

    return _mapList(response);
  }

  Future<void> cancelMyVisitorRequest(
    String requestId,
  ) async {
    final response = await _supabase.rpc(
      'corvia_patient_cancel_visitor_request',
      params: {
        'p_request_id': requestId,
      },
    );

    if (!_boolValue(response)) {
      throw Exception(
        'Visitor request could not be cancelled.',
      );
    }
  }

  // ============================================================
  // PEOPLE VISITING CURRENT PATIENT
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getMyVisitorPasses() async {
    final response = await _supabase.rpc(
      'corvia_patient_my_visitor_passes',
    );

    return _mapList(response);
  }

  Future<List<Map<String, dynamic>>>
      getMyVisitorRestrictions() async {
    final response = await _supabase.rpc(
      'corvia_patient_my_visitor_restrictions',
    );

    return _mapList(response);
  }

  // ============================================================
  // HOSPITAL REQUEST MANAGEMENT
  // ============================================================

  Future<List<Map<String, dynamic>>> getHospitalRequests({
    required String hospitalId,
    String? status,
  }) async {
    final response = await _supabase.rpc(
      'corvia_mh_visitor_requests',
      params: {
        'p_hospital_id': hospitalId,
        'p_status': _nullableText(status),
      },
    );

    return _mapList(response);
  }

  Future<Map<String, dynamic>> approveRequest({
    required String requestId,
    bool requiresIdentityVerification = true,
  }) async {
    final response = await _supabase.rpc(
      'corvia_mh_approve_visitor_request',
      params: {
        'p_request_id': requestId,
        'p_requires_identity_verification':
            requiresIdentityVerification,
      },
    );

    final result = _mapValue(response);

    if (result['success'] != true &&
        result['success']?.toString() != 'true') {
      throw Exception(
        'Visitor request could not be approved.',
      );
    }

    return result;
  }

  Future<void> denyRequest({
    required String requestId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();

    if (cleanReason.isEmpty) {
      throw Exception(
        'A denial reason is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_deny_visitor_request',
      params: {
        'p_request_id': requestId,
        'p_reason': cleanReason,
      },
    );

    if (!_boolValue(response)) {
      throw Exception(
        'Visitor request could not be denied.',
      );
    }
  }
}