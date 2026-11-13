import 'package:supabase_flutter/supabase_flutter.dart';

import 'qr_scanner_service.dart';

class ReceptionWalkInQr {
  const ReceptionWalkInQr({
    required this.exists,
    required this.hospitalId,
    required this.hospitalName,
    this.token,
    this.generatedAt,
  });

  final bool exists;
  final String hospitalId;
  final String hospitalName;
  final String? token;
  final DateTime? generatedAt;

  String? get payload {
    final value = token?.trim();
    if (value == null || value.isEmpty) return null;
    return QrPayload.build(QrPayload.walkIn, {'token': value});
  }

  factory ReceptionWalkInQr.fromJson(Map<String, dynamic> json) {
    return ReceptionWalkInQr(
      exists: json['exists'] == true,
      hospitalId: json['hospital_id']?.toString() ?? '',
      hospitalName: json['hospital_name']?.toString() ?? 'Hospital Reception',
      token: json['token']?.toString(),
      generatedAt: DateTime.tryParse(json['generated_at']?.toString() ?? ''),
    );
  }
}

class WalkInDepartment {
  const WalkInDepartment({
    required this.id,
    required this.name,
    this.locationName,
  });

  final String id;
  final String name;
  final String? locationName;

  factory WalkInDepartment.fromJson(Map<String, dynamic> json) {
    return WalkInDepartment(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Department',
      locationName: json['location_name']?.toString(),
    );
  }
}

class WalkInDoctor {
  const WalkInDoctor({
    required this.id,
    required this.departmentId,
    required this.name,
    required this.queueLength,
  });

  final String id;
  final String departmentId;
  final String name;
  final int queueLength;

  factory WalkInDoctor.fromJson(Map<String, dynamic> json) {
    final rawQueueLength = json['queue_length'];
    return WalkInDoctor(
      id: json['id']?.toString() ?? '',
      departmentId: json['department_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Doctor',
      queueLength: rawQueueLength is num
          ? rawQueueLength.toInt()
          : int.tryParse(rawQueueLength?.toString() ?? '') ?? 0,
    );
  }
}

class WalkInQrDestination {
  const WalkInQrDestination({
    required this.token,
    required this.hospitalId,
    required this.hospitalName,
    required this.departments,
    required this.doctors,
  });

  final String token;
  final String hospitalId;
  final String hospitalName;
  final List<WalkInDepartment> departments;
  final List<WalkInDoctor> doctors;

  factory WalkInQrDestination.fromJson(Map<String, dynamic> json) {
    final rawDepartments = json['departments'];
    final departments = rawDepartments is List
        ? rawDepartments
            .whereType<Map>()
            .map((item) => WalkInDepartment.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .where((item) => item.id.isNotEmpty)
            .toList()
        : <WalkInDepartment>[];

    final rawDoctors = json['doctors'];
    final doctors = rawDoctors is List
        ? rawDoctors
            .whereType<Map>()
            .map((item) => WalkInDoctor.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .where((item) => item.id.isNotEmpty)
            .toList()
        : <WalkInDoctor>[];

    return WalkInQrDestination(
      token: json['token']?.toString() ?? '',
      hospitalId: json['hospital_id']?.toString() ?? '',
      hospitalName: json['hospital_name']?.toString() ?? 'Hospital Reception',
      departments: departments,
      doctors: doctors,
    );
  }
}

class WalkInQueueReceipt {
  const WalkInQueueReceipt({
    required this.checkInId,
    required this.hospitalName,
    required this.departmentName,
    required this.doctorName,
    required this.queueStatus,
    required this.queuePosition,
    this.checkedInAt,
  });

  final String checkInId;
  final String hospitalName;
  final String departmentName;
  final String doctorName;
  final String queueStatus;
  final int queuePosition;
  final DateTime? checkedInAt;

  factory WalkInQueueReceipt.fromJson(Map<String, dynamic> json) {
    final rawPosition = json['queue_position'];
    return WalkInQueueReceipt(
      checkInId: json['checkin_id']?.toString() ?? '',
      hospitalName: json['hospital_name']?.toString() ?? 'Hospital Reception',
      departmentName: json['department_name']?.toString() ?? 'Department',
      doctorName: json['doctor_name']?.toString() ?? 'Assigned doctor',
      queueStatus: json['queue_status']?.toString() ?? 'waiting',
      queuePosition: rawPosition is num
          ? rawPosition.toInt()
          : int.tryParse(rawPosition?.toString() ?? '') ?? 0,
      checkedInAt: DateTime.tryParse(json['checked_in_at']?.toString() ?? ''),
    );
  }
}

class WalkInQrService {
  WalkInQrService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ReceptionWalkInQr> loadReceptionQr() async {
    final response = await _client.rpc('reception_get_walkin_qr');
    return ReceptionWalkInQr.fromJson(_map(response, 'Reception QR'));
  }

  Future<ReceptionWalkInQr> generateReceptionQr() async {
    final response = await _client.rpc('reception_regenerate_walkin_qr');
    return ReceptionWalkInQr.fromJson(_map(response, 'Reception QR'));
  }

  Future<WalkInQrDestination> validatePayload(String payload) async {
    final token = tokenFromPayload(payload);
    if (token == null) {
      throw Exception('This is not a valid Corvia reception walk-in QR code.');
    }

    final response = await _client.rpc(
      'patient_validate_walkin_qr',
      params: {'p_token': token},
    );
    final json = _map(response, 'Walk-in QR');
    json['token'] = token;
    return WalkInQrDestination.fromJson(json);
  }

  Future<WalkInQueueReceipt> joinQueue({
    required String token,
    required String departmentId,
    String? doctorId,
    required String reason,
  }) async {
    final response = await _client.rpc(
      'patient_join_walkin_queue_with_doctor',
      params: {
        'p_token': token,
        'p_department_id': departmentId,
        'p_doctor_id': doctorId,
        'p_reason': reason.trim(),
      },
    );
    return WalkInQueueReceipt.fromJson(_map(response, 'Walk-in check-in'));
  }

  static String? tokenFromPayload(String raw) {
    final parts = raw.trim().split('|');
    if (parts.isEmpty || parts.first.trim() != QrPayload.walkIn) return null;

    final params = <String, String>{};
    for (final part in parts.skip(1)) {
      final separator = part.indexOf('=');
      if (separator <= 0 || separator == part.length - 1) continue;
      params[part.substring(0, separator).trim()] =
          part.substring(separator + 1).trim();
    }

    if (params['v'] != QrPayload.version) return null;
    final token = params['token'];
    return token == null || token.isEmpty ? null : token;
  }

  Map<String, dynamic> _map(dynamic response, String label) {
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    throw Exception('$label returned invalid data.');
  }
}
