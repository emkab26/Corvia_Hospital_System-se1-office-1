/// UI guidance only. Publication permissions remain enforced by the backend.
class LabReleaseState {
  LabReleaseState.fromMap(Map<String, dynamic> row)
      : known = row.containsKey('result_release_status'),
        status = row['result_release_status']?.toString() ?? '',
        verified =
            DateTime.tryParse(row['result_verified_at']?.toString() ?? '') !=
                null,
        doctorManaged = row['doctor_release_managed'] == true ||
            row['requires_doctor_review'] == true,
        returnReason =
            row['verification_return_reason']?.toString().trim() ?? '';

  final bool known, verified, doctorManaged;
  final String status, returnReason;

  bool get released => status == 'released' || status == 'amended';
  bool get blocksCompletion =>
      known &&
      (!verified ||
          doctorManaged ||
          released ||
          status == 'awaiting_verification' ||
          status == 'awaiting_doctor_review');

  String get title {
    if (!known) return 'Release status unavailable';
    if (released) return 'Released result';
    if (returnReason.isNotEmpty && !verified) return 'Returned for correction';
    if (!verified || status == 'awaiting_verification') {
      return 'Awaiting laboratory verification';
    }
    if (doctorManaged || status == 'awaiting_doctor_review') {
      return 'Awaiting doctor release';
    }
    return 'Laboratory verification recorded';
  }

  String get guidance {
    if (!known) {
      return 'The backend will check verification and release permissions before completing this result.';
    }
    if (released) {
      return 'This result has been released. Changes require the authorised amendment workflow.';
    }
    if (!verified || status == 'awaiting_verification') {
      return 'An authorised laboratory verifier must verify the submitted result before it can be published.'
          '${returnReason.isEmpty ? '' : ' Correction requested: $returnReason'}';
    }
    if (doctorManaged || status == 'awaiting_doctor_review') {
      return 'The responsible doctor must review and release this result through the authorised doctor workflow.';
    }
    return 'The backend must confirm release permission. Changed content may require verification again.';
  }
}
