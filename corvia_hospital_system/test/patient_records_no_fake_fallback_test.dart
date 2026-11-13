import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('patient records never substitute hard-coded medical data', () {
    final source = File(
      'lib/pages/patient/patient_records.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('_fallbackRecords')));
    expect(source, isNot(contains("'demo-001'")));
    expect(source, contains("We couldn't load your medical records."));
    expect(source, contains('No medical records yet'));
  });
}
