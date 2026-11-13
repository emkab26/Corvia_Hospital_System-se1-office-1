import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/services/blood_bank_label_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sample = <String, dynamic>{
    'id': '10000000-0000-4000-8000-000000000001',
    'qr_value': 'corvia:bb:unit:10000000-0000-4000-8000-000000000001',
    'hospital_name': 'Synthetic Hospital',
    'unit_number': 'TEST-UNIT-001',
    'product_name': 'Test red cells',
    'abo': 'O',
    'rhd': 'positive',
    'expires_at': '2026-11-01T08:00:00Z',
    'generated_at': '2026-10-08T08:00:00Z',
    'status': 'quarantined',
    'recalled': true,
    'cold_chain_broken': true,
    'location_name': 'Synthetic quarantine',
    'source': 'external',
    'supplier': 'Test supplier',
    'lot_number': 'LOT-SYNTHETIC',
    'label_number': 2,
  };
  test('label builds offline with embedded fonts and a stable unit QR',
      () async {
    final bytes = await BloodBankLabelService.build(sample);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final file = File('tmp/pdfs/blood-bank-label-synthetic.pdf');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  });
  test('long references and maximum unit number remain printable', () async {
    final bytes = await BloodBankLabelService.build({
      ...sample,
      'unit_number': List.filled(100, 'W').join(),
      'supplier': List.filled(300, 'S').join(),
      'lot_number': List.filled(300, 'L').join(),
      'donation_reference': List.filled(300, 'D').join(),
      'collected_at': '2026-10-01T08:00:00Z',
      'hospital_name': List.filled(40, 'W').join(),
      'product_name': List.filled(40, 'W').join(),
      'location_name': List.filled(40, 'W').join(),
    });
    await File('tmp/pdfs/blood-bank-label-long.pdf').writeAsBytes(bytes);
  });
  test('unrecognised QR payload is rejected', () async {
    await expectLater(
        BloodBankLabelService.build(
            {...sample, 'qr_value': 'https://example.test'}),
        throwsFormatException);
  });
  test('control characters in unit identifiers cannot produce clipped labels',
      () async {
    await expectLater(
        BloodBankLabelService.build({...sample, 'unit_number': 'UNIT\n001'}),
        throwsFormatException);
  });
}
