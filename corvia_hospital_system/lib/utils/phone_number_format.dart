import 'package:flutter/services.dart';

/// Formats South African phone numbers for display without changing other
/// international numbers that may be used for emergency contacts.
String formatPhoneNumber(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10 && digits.startsWith('0')) {
    return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
  }
  if (digits.length == 11 && digits.startsWith('27')) {
    return '+27 ${digits.substring(2, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
  }
  return input;
}

class SouthAfricanPhoneInputFormatter extends TextInputFormatter {
  const SouthAfricanPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatPhoneNumber(newValue.text);
    if (formatted == newValue.text) return newValue;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
