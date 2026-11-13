import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class PatientTransferStatusService {
  PatientTransferStatusService({
    SupabaseClient? supabase,
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<PatientTransferStatusRecord> loadTransferStatus(
    String transferId,
  ) async {
    if (_supabase.auth.currentUser == null) {
      throw StateError(
        'You must be signed in to view a transfer.',
      );
    }

    if (transferId.trim().isEmpty) {
      throw ArgumentError(
        'Transfer ID is required.',
      );
    }

    final response = await _supabase.rpc(
      'corvia_mh_patient_transfer_status',
      params: {
        'p_transfer_id': transferId.trim(),
      },
    );

    final data = _map(response);

    if (data.isEmpty) {
      throw Exception(
        'Transfer information could not be loaded.',
      );
    }

    return PatientTransferStatusRecord.fromMap(data);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List && value.isNotEmpty) {
      return _map(value.first);
    }

    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);

        return _map(decoded);
      } catch (_) {
        return {};
      }
    }

    return {};
  }
}

class PatientTransferStatusRecord {
  const PatientTransferStatusRecord({
    required this.transferId,
    required this.transferNumber,
    required this.status,
    required this.priority,
    required this.sourceHospitalId,
    required this.sourceHospitalName,
    required this.destinationHospitalId,
    required this.destinationHospitalName,
    required this.destinationWardName,
    required this.destinationRoomLabel,
    required this.destinationBedLabel,
    required this.requestedAt,
    required this.acceptedAt,
    required this.preparedAt,
    required this.estimatedDepartureAt,
    required this.actualDepartureAt,
    required this.estimatedArrivalAt,
    required this.actualArrivalAt,
    required this.completedAt,
    required this.rejectedAt,
    required this.cancelledAt,
    required this.updatedAt,
  });

  final String transferId;
  final String transferNumber;

  final String status;
  final String priority;

  final String sourceHospitalId;
  final String sourceHospitalName;

  final String destinationHospitalId;
  final String destinationHospitalName;

  final String? destinationWardName;
  final String? destinationRoomLabel;
  final String? destinationBedLabel;

  final DateTime? requestedAt;
  final DateTime? acceptedAt;
  final DateTime? preparedAt;

  final DateTime? estimatedDepartureAt;
  final DateTime? actualDepartureAt;

  final DateTime? estimatedArrivalAt;
  final DateTime? actualArrivalAt;

  final DateTime? completedAt;
  final DateTime? rejectedAt;
  final DateTime? cancelledAt;
  final DateTime? updatedAt;

  factory PatientTransferStatusRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    DateTime? readDate(dynamic value) {
      if (value == null) {
        return null;
      }

      return DateTime.tryParse(
        value.toString(),
      )?.toLocal();
    }

    return PatientTransferStatusRecord(
      transferId: map['transfer_id']?.toString() ?? '',
      transferNumber: map['transfer_number']?.toString() ??
          map['transfer_id']?.toString() ??
          'Transfer',
      status: map['status']?.toString() ?? 'requested',
      priority: map['priority']?.toString() ?? 'routine',
      sourceHospitalId: map['source_hospital_id']?.toString() ?? '',
      sourceHospitalName:
          map['source_hospital_name']?.toString() ?? 'Source hospital',
      destinationHospitalId: map['destination_hospital_id']?.toString() ?? '',
      destinationHospitalName: map['destination_hospital_name']?.toString() ??
          'Destination hospital',
      destinationWardName: map['destination_ward_name']?.toString(),
      destinationRoomLabel: map['destination_room_label']?.toString(),
      destinationBedLabel: map['destination_bed_label']?.toString(),
      requestedAt: readDate(map['requested_at']),
      acceptedAt: readDate(map['accepted_at']),
      preparedAt: readDate(map['prepared_at']),
      estimatedDepartureAt: readDate(map['estimated_departure_at']),
      actualDepartureAt: readDate(map['actual_departure_at']),
      estimatedArrivalAt: readDate(map['estimated_arrival_at']),
      actualArrivalAt: readDate(map['actual_arrival_at']),
      completedAt: readDate(map['completed_at']),
      rejectedAt: readDate(map['rejected_at']),
      cancelledAt: readDate(map['cancelled_at']),
      updatedAt: readDate(map['updated_at']),
    );
  }

  bool get isCompleted {
    return status == 'completed';
  }

  bool get isCancelled {
    return status == 'cancelled';
  }

  bool get isRejected {
    return status == 'rejected';
  }

  bool get isTerminal {
    return isCompleted || isCancelled || isRejected;
  }

  String get displayStatus {
    return _humanize(status);
  }

  String get displayPriority {
    return _humanize(priority);
  }

  String get destinationLocation {
    final values = <String>[
      if (destinationWardName != null && destinationWardName!.trim().isNotEmpty)
        destinationWardName!,
      if (destinationRoomLabel != null &&
          destinationRoomLabel!.trim().isNotEmpty)
        'Room $destinationRoomLabel',
      if (destinationBedLabel != null && destinationBedLabel!.trim().isNotEmpty)
        'Bed $destinationBedLabel',
    ];

    if (values.isEmpty) {
      return 'Not allocated yet';
    }

    return values.join(' • ');
  }

  String get statusMessage {
    switch (status) {
      case 'requested':
        return 'The transfer request was sent to the receiving hospital.';

      case 'accepted':
        return 'The receiving hospital accepted the transfer request.';

      case 'ready_for_transfer':
        return 'The patient is being prepared for departure.';

      case 'in_transit':
        return 'The patient is travelling to the receiving hospital.';

      case 'received':
        return 'The receiving hospital confirmed the patient’s arrival.';

      case 'completed':
        return 'The hospital transfer has been completed.';

      case 'rejected':
        return 'The receiving hospital could not accept the transfer request.';

      case 'cancelled':
        return 'The hospital transfer was cancelled.';

      default:
        return 'The hospital transfer status was updated.';
    }
  }

  List<PatientTransferMilestone> get milestones {
    final output = <PatientTransferMilestone>[
      PatientTransferMilestone(
        label: 'Transfer requested',
        date: requestedAt,
        completed: requestedAt != null,
        current: status == 'requested',
      ),
      PatientTransferMilestone(
        label: 'Receiving hospital accepted',
        date: acceptedAt,
        completed: acceptedAt != null,
        current: status == 'accepted',
      ),
      PatientTransferMilestone(
        label: 'Ready for departure',
        date: preparedAt,
        completed: preparedAt != null,
        current: status == 'ready_for_transfer',
      ),
      PatientTransferMilestone(
        label: 'Departed source hospital',
        date: actualDepartureAt,
        completed: actualDepartureAt != null,
        current: status == 'in_transit',
      ),
      PatientTransferMilestone(
        label: 'Arrived at destination hospital',
        date: actualArrivalAt,
        completed: actualArrivalAt != null,
        current: status == 'received',
      ),
      PatientTransferMilestone(
        label: 'Transfer completed',
        date: completedAt,
        completed: completedAt != null,
        current: status == 'completed',
      ),
    ];

    if (isRejected) {
      output.add(
        PatientTransferMilestone(
          label: 'Transfer request declined',
          date: rejectedAt,
          completed: true,
          current: true,
          negative: true,
        ),
      );
    }

    if (isCancelled) {
      output.add(
        PatientTransferMilestone(
          label: 'Transfer cancelled',
          date: cancelledAt,
          completed: true,
          current: true,
          negative: true,
        ),
      );
    }

    return output;
  }

  static String _humanize(String value) {
    final words = value.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));

    return words.map((word) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    }).join(' ');
  }
}

class PatientTransferMilestone {
  const PatientTransferMilestone({
    required this.label,
    required this.date,
    required this.completed,
    required this.current,
    this.negative = false,
  });

  final String label;
  final DateTime? date;

  final bool completed;
  final bool current;
  final bool negative;
}
