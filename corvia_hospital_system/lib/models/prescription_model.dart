import 'dart:convert';

/// One medication line item stored inside prescriptions.medicines.
class MedicineItem {
  const MedicineItem({
    required this.name,
    this.dosage = '',
    this.frequency = '',
    this.duration = '',
  });

  factory MedicineItem.fromMap(
    Map<String, dynamic> map,
  ) {
    return MedicineItem(
      name: _text(
        map['name'],
      ),
      dosage: _text(
        map['dosage'],
      ),
      frequency: _text(
        map['frequency'],
      ),
      duration: _text(
        map['duration'],
      ),
    );
  }

  final String name;
  final String dosage;
  final String frequency;
  final String duration;

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'dosage': dosage.trim(),
      'frequency': frequency.trim(),
      'duration': duration.trim(),
    };
  }

  MedicineItem copyWith({
    String? name,
    String? dosage,
    String? frequency,
    String? duration,
  }) {
    return MedicineItem(
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      duration: duration ?? this.duration,
    );
  }

  static String _text(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return '';
    }

    return text;
  }
}

/// Represents a medical prescription issued by a doctor.
///
/// Database identifiers:
/// - patientId = patients.id
/// - doctorId = doctors.id
/// - hospitalId = hospitals.id
/// - createdBy = profiles.user_id / auth.users.id
class Prescription {
  const Prescription({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.issuedAt,
    required this.status,
    this.hospitalId,
    this.createdBy,
    this.notes,
    this.qrToken,
    this.refillDate,
    this.imageUrl,
    this.endDate,
    this.refillable = false,
    this.refillsAllowed = 0,
    this.refillsUsed = 0,
    this.refillRequested = false,
    this.refillRequestedAt,
    this.medicines = const [],
  });

  factory Prescription.fromMap(
    Map<String, dynamic> map,
  ) {
    final medicines = _parseMedicines(
      map['medicines'],
    );

    final scalarMedicationName = _text(
      map['medication_name'],
    );

    final medicationName = scalarMedicationName.isNotEmpty
        ? scalarMedicationName
        : medicines.isNotEmpty
            ? medicines.first.name
            : '';

    final scalarDosage = _text(
      map['dosage'],
    );

    final dosage = scalarDosage.isNotEmpty
        ? scalarDosage
        : medicines.isNotEmpty
            ? medicines.first.dosage
            : '';

    final scalarFrequency = _text(
      map['frequency'],
    );

    final frequency = scalarFrequency.isNotEmpty
        ? scalarFrequency
        : medicines.isNotEmpty
            ? medicines.first.frequency
            : '';

    final scalarDuration = _text(
      map['duration'],
    );

    final duration = scalarDuration.isNotEmpty
        ? scalarDuration
        : medicines.isNotEmpty
            ? medicines.first.duration
            : '';

    return Prescription(
      id: _text(
        map['id'],
      ),
      patientId: _text(
        map['patient_id'],
      ),
      doctorId: _text(
        map['doctor_id'],
      ),
      hospitalId: _nullableText(
        map['hospital_id'],
      ),
      createdBy: _nullableText(
        map['created_by'],
      ),
      medicationName: medicationName,
      dosage: dosage,
      frequency: frequency,
      duration: duration,
      notes: _nullableText(
        map['notes'],
      ),
      issuedAt: _date(
            map['issued_at'],
          ) ??
          _date(
            map['created_at'],
          ) ??
          DateTime.now(),
      status: _text(
        map['status'],
        fallback: 'active',
      ).toLowerCase(),
      qrToken: _nullableText(
        map['qr_token'],
      ),
      refillDate: _date(
        map['refill_date'],
      ),
      imageUrl: _nullableText(
        map['image_url'],
      ),
      endDate: _date(
        map['end_date'],
      ),
      refillable: map['refillable'] == true,
      refillsAllowed: _integer(map['refills_allowed']),
      refillsUsed: _integer(map['refills_used']),
      refillRequested: map['refill_requested'] == true,
      refillRequestedAt: _date(
        map['refill_requested_at'],
      ),
      medicines: medicines,
    );
  }

  final String id;
  final String patientId;
  final String doctorId;

  final String? hospitalId;
  final String? createdBy;

  final String medicationName;
  final String dosage;
  final String frequency;
  final String duration;

  final String? notes;

  final DateTime issuedAt;
  final String status;

  final String? qrToken;
  final DateTime? refillDate;
  final String? imageUrl;

  final DateTime? endDate;

  final bool refillable;
  final int refillsAllowed;
  final int refillsUsed;

  final bool refillRequested;
  final DateTime? refillRequestedAt;

  final List<MedicineItem> medicines;

  String get effectiveStatus {
    final cleanStatus = status.trim().toLowerCase();

    if (cleanStatus == 'active' &&
        endDate != null &&
        endDate!.isBefore(DateTime.now())) {
      return 'completed';
    }

    return cleanStatus;
  }

  int get refillsRemaining {
    final remaining = refillsAllowed - refillsUsed;

    return remaining < 0 ? 0 : remaining;
  }

  List<MedicineItem> get allMedicines {
    if (medicines.isNotEmpty) {
      return List<MedicineItem>.unmodifiable(
        medicines,
      );
    }

    if (medicationName.trim().isEmpty) {
      return const [];
    }

    return [
      MedicineItem(
        name: medicationName,
        dosage: dosage,
        frequency: frequency,
        duration: duration,
      ),
    ];
  }

  /// Full insert payload.
  ///
  /// The repository overwrites doctor_id, hospital_id and created_by with
  /// values resolved from the authenticated doctor session.
  Map<String, dynamic> toInsertMap() {
    final medicineItems = allMedicines;

    final firstMedicine = medicineItems.isNotEmpty
        ? medicineItems.first
        : MedicineItem(
            name: medicationName,
            dosage: dosage,
            frequency: frequency,
            duration: duration,
          );

    return {
      'patient_id': patientId.trim(),
      'doctor_id': doctorId.trim(),
      'hospital_id': _nullableTrimmed(
        hospitalId,
      ),
      'created_by': _nullableTrimmed(
        createdBy,
      ),
      'medication_name': firstMedicine.name.trim(),
      'dosage': firstMedicine.dosage.trim(),
      'frequency': firstMedicine.frequency.trim(),
      'duration': firstMedicine.duration.trim(),
      'notes': _nullableTrimmed(notes),
      'issued_at': issuedAt.toUtc().toIso8601String(),
      'status': status.trim().toLowerCase(),
      'qr_token': _nullableTrimmed(qrToken),
      'refill_date': refillDate?.toUtc().toIso8601String(),
      'image_url': _nullableTrimmed(imageUrl),
      'end_date': endDate?.toUtc().toIso8601String(),
      'refillable': refillable,
      'refills_allowed': refillable ? refillsAllowed : 0,
      'refills_used': refillable ? refillsUsed : 0,
      'refill_requested': refillable && refillRequested,
      'refill_requested_at': refillable && refillRequested
          ? refillRequestedAt?.toUtc().toIso8601String()
          : null,
      'medicines': medicineItems
          .map(
            (medicine) => medicine.toMap(),
          )
          .toList(),
    };
  }

  /// Editable update payload.
  ///
  /// Immutable ownership fields are deliberately excluded.
  Map<String, dynamic> toUpdateMap() {
    final medicineItems = allMedicines;

    final firstMedicine = medicineItems.isNotEmpty
        ? medicineItems.first
        : MedicineItem(
            name: medicationName,
            dosage: dosage,
            frequency: frequency,
            duration: duration,
          );

    return {
      'medication_name': firstMedicine.name.trim(),
      'dosage': firstMedicine.dosage.trim(),
      'frequency': firstMedicine.frequency.trim(),
      'duration': firstMedicine.duration.trim(),
      'notes': _nullableTrimmed(notes),
      'status': status.trim().toLowerCase(),
      'qr_token': _nullableTrimmed(qrToken),
      'refill_date': refillDate?.toUtc().toIso8601String(),
      'image_url': _nullableTrimmed(imageUrl),
      'end_date': endDate?.toUtc().toIso8601String(),
      'refillable': refillable,
      'refills_allowed': refillable ? refillsAllowed : 0,
      'refills_used': refillable ? refillsUsed : 0,
      'refill_requested': refillable && refillRequested,
      'refill_requested_at': refillable && refillRequested
          ? refillRequestedAt?.toUtc().toIso8601String()
          : null,
      'medicines': medicineItems
          .map(
            (medicine) => medicine.toMap(),
          )
          .toList(),
    };
  }

  /// Kept for compatibility with older code.
  Map<String, dynamic> toMap() {
    return toInsertMap();
  }

  Prescription copyWith({
    String? id,
    String? patientId,
    String? doctorId,
    String? hospitalId,
    String? createdBy,
    String? medicationName,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
    DateTime? issuedAt,
    String? status,
    String? qrToken,
    DateTime? refillDate,
    String? imageUrl,
    DateTime? endDate,
    bool? refillable,
    int? refillsAllowed,
    int? refillsUsed,
    bool? refillRequested,
    DateTime? refillRequestedAt,
    List<MedicineItem>? medicines,
  }) {
    return Prescription(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      doctorId: doctorId ?? this.doctorId,
      hospitalId: hospitalId ?? this.hospitalId,
      createdBy: createdBy ?? this.createdBy,
      medicationName: medicationName ?? this.medicationName,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      duration: duration ?? this.duration,
      notes: notes ?? this.notes,
      issuedAt: issuedAt ?? this.issuedAt,
      status: status ?? this.status,
      qrToken: qrToken ?? this.qrToken,
      refillDate: refillDate ?? this.refillDate,
      imageUrl: imageUrl ?? this.imageUrl,
      endDate: endDate ?? this.endDate,
      refillable: refillable ?? this.refillable,
      refillsAllowed: refillsAllowed ?? this.refillsAllowed,
      refillsUsed: refillsUsed ?? this.refillsUsed,
      refillRequested: refillRequested ?? this.refillRequested,
      refillRequestedAt: refillRequestedAt ?? this.refillRequestedAt,
      medicines: medicines ?? this.medicines,
    );
  }

  static List<MedicineItem> _parseMedicines(
    dynamic raw,
  ) {
    if (raw == null) {
      return const [];
    }

    dynamic decoded = raw;

    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }

    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map(
          (medicine) => MedicineItem.fromMap(
            Map<String, dynamic>.from(
              medicine,
            ),
          ),
        )
        .where(
          (medicine) => medicine.name.trim().isNotEmpty,
        )
        .toList();
  }

  static String _text(
    dynamic value, {
    String fallback = '',
  }) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }

  static String? _nullableText(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  static String? _nullableTrimmed(
    String? value,
  ) {
    final text = value?.trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }

  static int _integer(
    dynamic value,
  ) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  static DateTime? _date(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text);
  }
}
