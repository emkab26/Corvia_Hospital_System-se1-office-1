import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/utils/phone_number_format.dart';

void main() {
  test('formats South African mobile numbers', () {
    expect(formatPhoneNumber('0821234567'), '082 123 4567');
    expect(formatPhoneNumber('+27821234567'), '+27 82 123 4567');
    expect(formatPhoneNumber('082 123 4567'), '082 123 4567');
  });

  test('leaves international and incomplete numbers unchanged', () {
    expect(formatPhoneNumber('+441234567890'), '+441234567890');
    expect(formatPhoneNumber('082123'), '082123');
  });

  test('input formatter applies the same format', () {
    const formatter = SouthAfricanPhoneInputFormatter();
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '0821234567'),
    );
    expect(result.text, '082 123 4567');
  });
}
