import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/models/emergency_contact.dart';

void main() {
  group('EmergencyContactValidators.name', () {
    test('rejects empty name', () {
      expect(EmergencyContactValidators.name(''), isNotNull);
      expect(EmergencyContactValidators.name(null), isNotNull);
      expect(EmergencyContactValidators.name('   '), isNotNull);
    });

    test('rejects names shorter than 2 characters', () {
      expect(EmergencyContactValidators.name('A'), isNotNull);
    });

    test('rejects names with digits or symbols', () {
      expect(EmergencyContactValidators.name('John3'), isNotNull);
      expect(EmergencyContactValidators.name('John@Doe'), isNotNull);
    });

    test('accepts simple names', () {
      expect(EmergencyContactValidators.name('John Doe'), isNull);
    });

    test('accepts hyphenated and apostrophe names', () {
      expect(EmergencyContactValidators.name("Mary-Jane O'Brien"), isNull);
    });

    test('rejects names longer than 60 characters', () {
      final longName = 'A' * 61;
      expect(EmergencyContactValidators.name(longName), isNotNull);
    });
  });

  group('EmergencyContactValidators.relationship', () {
    test('rejects empty relationship', () {
      expect(EmergencyContactValidators.relationship(''), isNotNull);
      expect(EmergencyContactValidators.relationship(null), isNotNull);
    });

    test('rejects relationship with digits', () {
      expect(EmergencyContactValidators.relationship('Mother2'), isNotNull);
    });

    test('accepts common relationship values', () {
      expect(EmergencyContactValidators.relationship('Mother'), isNull);
      expect(EmergencyContactValidators.relationship('Spouse'), isNull);
      expect(EmergencyContactValidators.relationship('Next-of-kin'), isNull);
    });

    test('rejects relationship longer than 30 characters', () {
      final longRel = 'A' * 31;
      expect(EmergencyContactValidators.relationship(longRel), isNotNull);
    });
  });

  group('EmergencyContactValidators.phoneNumber', () {
    test('rejects empty phone number', () {
      expect(EmergencyContactValidators.phoneNumber(''), isNotNull);
      expect(EmergencyContactValidators.phoneNumber(null), isNotNull);
    });

    test('rejects phone numbers with letters', () {
      expect(EmergencyContactValidators.phoneNumber('08212345AB'), isNotNull);
    });

    test('rejects phone numbers that are too short', () {
      expect(EmergencyContactValidators.phoneNumber('12345'), isNotNull);
    });

    test('rejects phone numbers that are too long', () {
      expect(EmergencyContactValidators.phoneNumber('1234567890123456'),
          isNotNull);
    });

    test('accepts a valid local number', () {
      expect(EmergencyContactValidators.phoneNumber('0821234567'), isNull);
    });

    test('accepts a valid international number with +, spaces, and hyphens',
        () {
      expect(EmergencyContactValidators.phoneNumber('+27 82-123-4567'),
          isNull);
    });
  });

  group('EmergencyContactValidators.validateAll', () {
    test('returns no errors for a fully valid contact', () {
      final errors = EmergencyContactValidators.validateAll(
        name: 'Jane Doe',
        relationship: 'Sister',
        phoneNumber: '+27821234567',
      );
      expect(errors, isEmpty);
    });

    test('returns an error per invalid field', () {
      final errors = EmergencyContactValidators.validateAll(
        name: '',
        relationship: '123',
        phoneNumber: 'abc',
      );
      expect(errors.containsKey('name'), isTrue);
      expect(errors.containsKey('relationship'), isTrue);
      expect(errors.containsKey('phoneNumber'), isTrue);
    });
  });

  group('EmergencyContact model', () {
    test('toMap trims whitespace and includes patientId when provided', () {
      final contact = EmergencyContact(
        name: '  Jane Doe  ',
        relationship: ' Sister ',
        phoneNumber: ' 0821234567 ',
        isPrimary: true,
      );
      final map = contact.toMap(patientId: 'patient-123');

      expect(map['name'], 'Jane Doe');
      expect(map['relationship'], 'Sister');
      expect(map['phone_number'], '0821234567');
      expect(map['is_primary'], true);
      expect(map['patient_id'], 'patient-123');
      expect(map.containsKey('id'), isFalse);
    });

    test('toMap includes id when editing an existing contact', () {
      final contact = EmergencyContact(
        id: 'contact-1',
        name: 'Jane Doe',
        relationship: 'Sister',
        phoneNumber: '0821234567',
      );
      final map = contact.toMap();
      expect(map['id'], 'contact-1');
    });

    test('fromMap parses a database row correctly', () {
      final contact = EmergencyContact.fromMap({
        'id': 'c1',
        'name': 'John Smith',
        'relationship': 'Father',
        'phone_number': '0831112222',
        'is_primary': true,
      });

      expect(contact.id, 'c1');
      expect(contact.name, 'John Smith');
      expect(contact.relationship, 'Father');
      expect(contact.phoneNumber, '0831112222');
      expect(contact.isPrimary, isTrue);
    });

    test('fromMap defaults isPrimary to false when missing', () {
      final contact = EmergencyContact.fromMap({
        'name': 'John Smith',
        'relationship': 'Father',
        'phone_number': '0831112222',
      });
      expect(contact.isPrimary, isFalse);
    });

    test('copyWith overrides only specified fields', () {
      final original = EmergencyContact(
        id: 'c1',
        name: 'John Smith',
        relationship: 'Father',
        phoneNumber: '0831112222',
      );
      final updated = original.copyWith(phoneNumber: '0839998888');

      expect(updated.id, 'c1');
      expect(updated.name, 'John Smith');
      expect(updated.relationship, 'Father');
      expect(updated.phoneNumber, '0839998888');
    });
  });
}
