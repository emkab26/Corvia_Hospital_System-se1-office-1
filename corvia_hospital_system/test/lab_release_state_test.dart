import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/models/lab_release_state.dart';

void main() {
  test('sample collected cannot bypass verification', () {
    final state = LabReleaseState.fromMap(
        {'status': 'sample_collected', 'result_release_status': 'pending'});
    expect(state.blocksCompletion, isTrue);
    expect(state.title, 'Awaiting laboratory verification');
  });
  test('doctor review and released amendments do not use direct completion',
      () {
    for (final status in ['awaiting_doctor_review', 'released', 'amended']) {
      expect(
          LabReleaseState.fromMap({
            'result_release_status': status,
            'result_verified_at': '2026-10-08T08:00:00Z'
          }).blocksCompletion,
          isTrue);
    }
    expect(
        LabReleaseState.fromMap({
          'result_release_status': 'pending',
          'result_verified_at': '2026-10-08T08:00:00Z',
          'doctor_release_managed': true
        }).blocksCompletion,
        isTrue);
  });
  test('completed status does not imply verification; return reason is visible',
      () {
    final state = LabReleaseState.fromMap({
      'status': 'completed',
      'result_release_status': 'pending',
      'verification_return_reason': 'Correct sample reference'
    });
    expect(state.blocksCompletion, isTrue);
    expect(state.guidance, contains('Correct sample reference'));
  });
  test('legacy metadata remains unknown and verified records defer to server',
      () {
    final legacy = LabReleaseState.fromMap({'status': 'completed'});
    expect(legacy.known, isFalse);
    expect(legacy.title, 'Release status unavailable');
    final verified = LabReleaseState.fromMap({
      'result_release_status': 'pending',
      'result_verified_at': '2026-10-08T08:00:00Z'
    });
    expect(verified.blocksCompletion, isFalse);
    expect(verified.guidance, contains('backend'));
  });
}
