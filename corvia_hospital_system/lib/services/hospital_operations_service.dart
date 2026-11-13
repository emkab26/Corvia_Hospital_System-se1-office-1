import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class HospitalOperationsService {
  HospitalOperationsService({
    SupabaseClient? supabase,
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<HospitalOperationsStats> loadStats(
    String hospitalId,
  ) async {
    if (hospitalId.trim().isEmpty) {
      throw Exception('Hospital ID is required.');
    }

    final response = await _supabase.rpc(
      'corvia_mh_dashboard_admission_bed_stats',
      params: {
        'p_hospital_id': hospitalId,
      },
    );

    final data = _asMap(response);

    if (data.isEmpty) {
      throw Exception(
        'Hospital operations statistics returned no data.',
      );
    }

    return HospitalOperationsStats.fromMap(data);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List && value.isNotEmpty) {
      return _asMap(value.first);
    }

    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);

        return _asMap(decoded);
      } catch (_) {
        return {};
      }
    }

    return {};
  }
}

class HospitalOperationsStats {
  const HospitalOperationsStats({
    required this.hospitalId,
    required this.activeAdmissions,
    required this.plannedAdmissions,
    required this.dischargedToday,
    required this.cancelledAdmissions,
    required this.admittedWithoutBed,
    required this.activeAssignments,
    required this.totalBeds,
    required this.activeBeds,
    required this.availableBeds,
    required this.reservedBeds,
    required this.occupiedBeds,
    required this.cleaningBeds,
    required this.maintenanceBeds,
    required this.blockedBeds,
    required this.occupancyPercentage,
    required this.generatedAt,
  });

  final String hospitalId;

  final int activeAdmissions;
  final int plannedAdmissions;
  final int dischargedToday;
  final int cancelledAdmissions;

  final int admittedWithoutBed;
  final int activeAssignments;

  final int totalBeds;
  final int activeBeds;
  final int availableBeds;
  final int reservedBeds;
  final int occupiedBeds;
  final int cleaningBeds;
  final int maintenanceBeds;
  final int blockedBeds;

  final double occupancyPercentage;
  final DateTime? generatedAt;

  factory HospitalOperationsStats.fromMap(
    Map<String, dynamic> map,
  ) {
    return HospitalOperationsStats(
      hospitalId: map['hospital_id']?.toString() ?? '',
      activeAdmissions: _intValue(
        map['active_admissions'],
      ),
      plannedAdmissions: _intValue(
        map['planned_admissions'],
      ),
      dischargedToday: _intValue(
        map['discharged_today'],
      ),
      cancelledAdmissions: _intValue(
        map['cancelled_admissions'],
      ),
      admittedWithoutBed: _intValue(
        map['admitted_without_bed'],
      ),
      activeAssignments: _intValue(
        map['active_assignments'],
      ),
      totalBeds: _intValue(
        map['total_beds'],
      ),
      activeBeds: _intValue(
        map['active_beds'],
      ),
      availableBeds: _intValue(
        map['available_beds'],
      ),
      reservedBeds: _intValue(
        map['reserved_beds'],
      ),
      occupiedBeds: _intValue(
        map['occupied_beds'],
      ),
      cleaningBeds: _intValue(
        map['cleaning_beds'],
      ),
      maintenanceBeds: _intValue(
        map['maintenance_beds'],
      ),
      blockedBeds: _intValue(
        map['blocked_beds'],
      ),
      occupancyPercentage: _doubleValue(
        map['occupancy_percentage'],
      ),
      generatedAt: DateTime.tryParse(
        map['generated_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _doubleValue(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int get unavailableBeds {
    return maintenanceBeds + blockedBeds;
  }

  int get operationalBeds {
    return availableBeds + reservedBeds + occupiedBeds + cleaningBeds;
  }

  bool get hasCapacityWarning {
    return activeBeds > 0 && occupancyPercentage >= 85;
  }

  bool get hasCriticalCapacityWarning {
    return activeBeds > 0 && occupancyPercentage >= 95;
  }

  bool get hasAdmissionWarning {
    return admittedWithoutBed > 0;
  }

  double get occupancyProgress {
    return (occupancyPercentage / 100).clamp(0.0, 1.0);
  }
}
