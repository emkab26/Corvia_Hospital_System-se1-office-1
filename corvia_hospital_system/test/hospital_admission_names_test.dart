import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mycorvia/services/hospital_admission_service.dart';
import 'package:mycorvia/services/hospital_structure_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Structure extends Mock implements HospitalStructureService {}

void main() {
  const hospital = 'test-hospital';
  const profile = {
    'id': 'different-profile-row-id',
    'user_id': 'auth-user-id',
    'first_name': 'Synthetic',
    'surname': 'Patient',
    'email': 'synthetic@example.test',
  };

  Future<void> checkNames({
    required Map<String, dynamic> patientFields,
    required String expected,
    List<Map<String, dynamic>> profiles = const [profile],
  }) async {
    final patients = [
      {
        'id': 'patient-record-id',
        'profile_id': 'auth-user-id',
        'hospital_id': hospital,
        'patient_number': 'TEST-001',
        'is_active': true,
        ...patientFields,
      }
    ];
    final requests = <Uri>[];
    final client = SupabaseClient('https://example.test', 'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requests.add(request.url);
      final table = request.url.pathSegments.last;
      final query = request.url.queryParameters;
      List<Map<String, dynamic>> rows;
      switch (table) {
        case 'patient_hospital_links':
          expect(query['hospital_id'], 'eq.$hospital');
          rows = [
            {
              'id': 'link',
              'hospital_id': hospital,
              'patient_id': 'patient-record-id'
            }
          ];
        case 'patients':
          rows = patients;
        case 'profiles':
          expect(query.containsKey('id'), isFalse,
              reason: 'patients.profile_id references profiles.user_id');
          expect(query['user_id'], contains('auth-user-id'));
          rows = profiles;
        case 'hospital_admissions':
          expect(query['hospital_id'], 'eq.$hospital');
          rows = [
            {
              'id': 'admission',
              'hospital_id': hospital,
              'patient_id': 'patient-record-id',
              'status': 'admitted'
            }
          ];
        case 'patient_bed_assignments':
          rows = [];
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
      final columns = query['select']!.split(',').map((c) => c.trim()).toSet();
      final projected = rows
          .map((r) =>
              Map.fromEntries(r.entries.where((e) => columns.contains(e.key))))
          .toList();
      return http.Response(jsonEncode(projected), 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    final structure = _Structure();
    when(() => structure.loadSnapshot(hospital)).thenAnswer((_) async =>
        const HospitalStructureSnapshot(
            buildings: [],
            floors: [],
            wards: [],
            visitorRules: [],
            rooms: [],
            beds: []));
    final service =
        HospitalAdmissionService(supabase: client, structureService: structure);
    expect((await service.getHospitalPatients(hospital)).single.patientName,
        expected);
    expect(
        (await service.getAdmissions(hospital)).single.patientName, expected);
    expect(requests.where((r) => r.pathSegments.last == 'profiles').length, 2);
  }

  test('admission picker and cards match profile by auth UUID', () async {
    await checkNames(
        patientFields: {'first_name': null, 'surname': ' '},
        expected: 'Synthetic Patient');
  });
  test('patient names remain usable when profile rows are not visible',
      () async {
    await checkNames(
        patientFields: {'first_name': ' Local ', 'surname': ' Name '},
        profiles: [],
        expected: 'Local Name');
  });
  test('patient record name takes precedence over a generic profile name',
      () async {
    await checkNames(
        patientFields: {'first_name': 'Local', 'surname': 'Name'},
        expected: 'Local Name');
  });
  test('missing names fall back to patient email without inventing a name',
      () async {
    await checkNames(patientFields: {
      'first_name': '',
      'surname': null,
      'email': 'local@example.test'
    }, profiles: [], expected: 'local@example.test');
  });
  test('genuinely missing identity stays explicitly unknown', () async {
    await checkNames(
        patientFields: {}, profiles: [], expected: 'Unknown patient');
  });

  test('reserved beds stay out of the general admission picker', () async {
    HospitalBedBoardEntry bed(String id, String status) {
      return HospitalBedBoardEntry(
        hospitalId: hospital,
        buildingId: 'building',
        buildingName: 'Main Building',
        floorId: 'floor',
        floorName: 'Ground Floor',
        wardId: 'ward',
        wardName: 'General Ward',
        wardType: 'general',
        roomId: 'room',
        roomNumber: '01',
        roomName: null,
        roomType: 'general',
        bedId: id,
        bedNumber: id,
        bedLabel: null,
        bedType: 'standard',
        bedStatus: status,
        bedActive: true,
        reservedUntil: status == 'reserved'
            ? DateTime.now().add(const Duration(hours: 2))
            : null,
        cleaningStartedAt: null,
        cleanedAt: null,
        sanitationNotes: null,
        maintenanceReason: null,
        evsNotifiedAt: null,
        assignmentId: null,
        admissionId: null,
        admissionNumber: null,
        patientId: null,
        patientNumber: null,
        patientName: null,
        assignedAt: null,
      );
    }

    final structure = _Structure();
    when(() => structure.getBedBoard(hospital)).thenAnswer(
      (_) async =>
          [bed('available-bed', 'available'), bed('reserved-bed', 'reserved')],
    );
    final client = SupabaseClient(
      'https://example.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);

    final service = HospitalAdmissionService(
      supabase: client,
      structureService: structure,
    );

    final options = await service.getAvailableBeds(hospital);
    expect(options.map((bed) => bed.bedId), ['available-bed']);
  });
}
