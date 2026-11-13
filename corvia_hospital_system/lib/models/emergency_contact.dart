library;

import '../services/validation_service.dart';

class EmergencyContact {
  EmergencyContact({
    this.id,
    required this.name,
    required this.relationship,
    required this.phoneNumber,
    this.isPrimary = false,
  });

  final String? id;

  final String name;
  final String relationship;
  final String phoneNumber;

  final bool isPrimary;

  EmergencyContact copyWith({
    String? id,
    String? name,
    String? relationship,
    String? phoneNumber,
    bool? isPrimary,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  Map<String, dynamic> toMap({String? patientId}) => {
        if (id != null) 'id': id,
        if (patientId != null) 'patient_id': patientId,
        'name': name.trim(),
        'relationship': relationship.trim(),
        'phone_number': phoneNumber.trim(),
        'is_primary': isPrimary,
      };

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      id: map['id']?.toString(),
      name: map['name']?.toString() ?? '',
      relationship: map['relationship']?.toString() ?? '',
      phoneNumber: map['phone_number']?.toString() ?? '',
      isPrimary: map['is_primary'] == true,
    );
  }
}

class EmergencyContactValidators {
  EmergencyContactValidators._();

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name is required';
    if (v.length < 2) return 'Name is too short';
    if (v.length > 60) return 'Name is too long';
    final pattern = RegExp(r"^[A-Za-z\s\-']+$");
    if (!pattern.hasMatch(v)) {
      return 'Name can only contain letters, spaces, hyphens, and apostrophes';
    }
    return null;
  }

  static String? relationship(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Relationship is required';
    if (v.length < 2) return 'Relationship is too short';
    if (v.length > 30) return 'Relationship is too long';
    final pattern = RegExp(r"^[A-Za-z\s\-]+$");
    if (!pattern.hasMatch(v)) {
      return 'Relationship can only contain letters, spaces, and hyphens';
    }
    return null;
  }

  static String? phoneNumber(String? value) =>
      ValidationService.validateSouthAfricanPhone(value, required: true);

  static Map<String, String> validateAll({
    required String name,
    required String relationship,
    required String phoneNumber,
  }) {
    final errors = <String, String>{};
    final nameError = EmergencyContactValidators.name(name);
    final relError = EmergencyContactValidators.relationship(relationship);
    final phoneError = EmergencyContactValidators.phoneNumber(phoneNumber);

    if (nameError != null) errors['name'] = nameError;
    if (relError != null) errors['relationship'] = relError;
    if (phoneError != null) errors['phoneNumber'] = phoneError;

    return errors;
  }
}
