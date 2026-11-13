import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/models/emergency_contact.dart';
import 'package:mycorvia/services/validation_service.dart';

void main() {
  group('ValidationService.validatePhone', () {
    test('accepts a plain local number', () {
      expect(ValidationService.validatePhone('0821234567'), isNull);
    });

    test('accepts a number written with spaces, hyphens and brackets', () {
      expect(ValidationService.validatePhone('+27 82 123 4567'), isNull);
      expect(ValidationService.validatePhone('+27 82-123-4567'), isNull);
      expect(ValidationService.validatePhone('(021) 555-1234'), isNull);
    });

    test('is optional by default: empty and null pass', () {
      expect(ValidationService.validatePhone(''), isNull);
      expect(ValidationService.validatePhone('   '), isNull);
      expect(ValidationService.validatePhone(null), isNull);
    });

    test('is required when asked, and says so', () {
      expect(ValidationService.validatePhone('', required: true),
          'Phone number is required');
      expect(ValidationService.validatePhone(null, required: true),
          'Phone number is required');
    });

    test('rejects letters as bad characters rather than as a length problem',
        () {
      expect(ValidationService.validatePhone('08212345AB'), contains('digits'));
    });

    test('counts digits, not characters, at each bound', () {
      // Six digits is short whatever the separators dress it up as.
      expect(ValidationService.validatePhone('12-34-56'), 'Phone number is too short');
      expect(ValidationService.validatePhone('1234567'), isNull);
      expect(ValidationService.validatePhone('123456789012345'), isNull);
      expect(ValidationService.validatePhone('1234567890123456'),
          'Phone number is too long');
    });

    test('a formatted number is judged on its digits, not its width', () {
      // 15 digits is the limit; the separators must not push it over.
      expect(ValidationService.validatePhone('+27 (82) 123 4567 890'), isNull);
    });
  });

  // These pin the behaviour a stale branch tried to overwrite. Both directions
  // matter: loosening the email rule and tightening the password rule are each
  // regressions, and nothing else in the suite currently catches them.
  group('ValidationService regression guards', () {
    test('a six character password is still accepted', () {
      expect(ValidationService.validatePassword('abc123'), isNull);
      expect(ValidationService.minPasswordLength, 6);
    });

    test('a long TLD such as .health is still accepted', () {
      expect(ValidationService.validateEmail('nurse@clinic.health'), isNull);
    });

    test('an email containing a space is still rejected', () {
      expect(ValidationService.validateEmail('a b@c.d'), isNotNull);
    });
  });

  group('EmergencyContactValidators.phoneNumber delegates', () {
    test('keeps its required semantics', () {
      expect(EmergencyContactValidators.phoneNumber(''), isNotNull);
      expect(EmergencyContactValidators.phoneNumber(null), isNotNull);
    });

    test('agrees with the shared validator on a valid number', () {
      expect(EmergencyContactValidators.phoneNumber('0821234567'), isNull);
      expect(EmergencyContactValidators.phoneNumber('+27 82-123-4567'), isNull);
    });
  });
}
