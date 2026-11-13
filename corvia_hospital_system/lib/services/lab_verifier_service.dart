import 'package:supabase_flutter/supabase_flutter.dart';

class LabVerifierService {
  LabVerifierService(this.client);
  final SupabaseClient client;

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid verifier response.');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> context() async =>
      _map(await client.rpc('corvia_current_lab_verifier_context'));

  Future<List<LabVerificationSubmission>> queue(
      {required bool returned}) async {
    final response = await client
        .rpc('corvia_lab_verifier_queue', params: {'p_returned': returned});
    if (response is! List) {
      throw const FormatException('Invalid verifier queue.');
    }
    return response.map((row) => LabVerificationSubmission(_map(row))).toList();
  }

  Future<String> approve(LabVerificationSubmission submission) async {
    if (!submission.canReview) {
      throw const FormatException('This submission cannot be reviewed by you.');
    }
    final response =
        _map(await client.rpc('corvia_lab_verifier_approve_result', params: {
      'p_lab_result_id': submission.id,
      'p_expected_version': submission.version,
    }));
    final status = response['result_release_status'];
    if (response['lab_result_id'] != submission.id ||
        !{'released', 'awaiting_doctor_review'}.contains(status)) {
      throw const FormatException('Approval was not confirmed by the server.');
    }
    return status as String;
  }

  Future<void> returnForCorrection(
      LabVerificationSubmission submission, String reason) async {
    if (!submission.canReview) {
      throw const FormatException('This submission cannot be reviewed by you.');
    }
    final clean = reason.trim();
    if (clean.length < 3 || clean.length > 2000) {
      throw const FormatException(
          'Enter a correction reason between 3 and 2,000 characters.');
    }
    final response =
        _map(await client.rpc('corvia_lab_verifier_return_result', params: {
      'p_lab_result_id': submission.id,
      'p_expected_version': submission.version,
      'p_reason': clean,
    }));
    if (response['lab_result_id'] != submission.id ||
        response['returned'] != true) {
      throw const FormatException(
          'Return for correction was not confirmed by the server.');
    }
  }
}

class LabVerificationSubmission {
  LabVerificationSubmission(this.data) {
    if (data['lab_result_id'] is! String ||
        (data['lab_result_id'] as String).isEmpty ||
        data['result_submission_version'] is! int ||
        data['draft_result'] is! String) {
      throw const FormatException('Invalid laboratory submission.');
    }
  }
  final Map<String, dynamic> data;
  String get id => data['lab_result_id'] as String;
  int get version => data['result_submission_version'] as int;
  String get testName => data['test_name']?.toString() ?? 'Lab test';
  String get result => data['draft_result'] as String;
  String get technician => data['entered_by_name']?.toString() ?? 'Technician';
  bool get requiresDoctorReview => data['requires_doctor_review'] != false;
  bool get canReview =>
      data['can_review'] == true &&
      data['result_release_status'] == 'awaiting_verification';
}
