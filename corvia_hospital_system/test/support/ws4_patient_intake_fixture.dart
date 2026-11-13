import 'package:mycorvia/models/dispatch/patient_emergency_intake.dart';
import 'ws4_http_fixture.dart';

const intakeOperation = '00000000-0000-4000-8000-000000000042';
const nextIntakeOperation = '00000000-0000-4000-8000-000000000043';
Map<String, dynamic> intakeResponse(
    {String operation = intakeOperation,
    String userId = fixtureActor,
    String status = 'pending',
    String version = '1',
    PatientEmergencyIntakeRequest? input}) {
  final request = input ?? PatientEmergencyIntakeRequest();
  return {
    'operation_id': operation,
    'incident_id': '9007199254740993',
    'user_id': userId,
    'status': status,
    'version': version,
    'created_at': '2026-10-07T12:00:00Z',
    'latitude': request.latitude,
    'longitude': request.longitude,
    'location_source': request.locationSource,
    'location_accuracy': request.accuracy,
    'location_captured_at': request.capturedAt?.toIso8601String(),
    'address': request.address,
    'details': request.details,
  };
}

PatientEmergencyIncident intakeIncident(
        {String operation = intakeOperation,
        String userId = fixtureActor,
        String status = 'pending',
        String version = '1',
        PatientEmergencyIntakeRequest? input}) =>
    PatientEmergencyIncident.fromMap(
        intakeResponse(
            operation: operation,
            userId: userId,
            status: status,
            version: version,
            input: input),
        expectedUserId: userId,
        expectedOperationId: operation);
