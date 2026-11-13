import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'supabase_service.dart';

class CallService {
  final Logger _logger = Logger('CallService');

  Future<String> startCallSession(
      String patientId, String doctorId, String incidentId) async {
    try {
      final existing = await SupabaseService.client
          .from('call_sessions')
          .select()
          .eq('patient_id', patientId)
          .eq('doctor_id', doctorId)
          .eq('status', 'ringing')
          .maybeSingle();

      if (existing != null) {
        _logger.warning('Duplicate active session detected');
        throw StateError(
            'A call is already in progress for this patient/doctor.');
      }

      final response = await SupabaseService.client
          .from('call_sessions')
          .insert({
            'patient_id': patientId,
            'doctor_id': doctorId,
            'incident_id': incidentId,
            'status': 'ringing',
            'started_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 10));

      final incidentCheck = await SupabaseService.client
          .from('incidents')
          .select()
          .eq('id', incidentId)
          .maybeSingle();

      if (incidentCheck == null) {
        _logger.severe('Incident $incidentId not found');
        throw StateError('Incident not found. Cannot start call.');
      }

      await SupabaseService.client
          .from('incidents')
          .update({'status': 'in_progress'}).eq('id', incidentId);

      return response['id'].toString();
    } on SocketException catch (e) {
      _logger.severe('No internet connection', e);
      throw const SocketException(
          'No internet connection. Please check your network.');
    } on TimeoutException catch (e) {
      _logger.severe('Request timed out', e);
      rethrow;
    } catch (e) {
      if (e is StateError) rethrow;
      if (e.toString().contains('permission denied')) {
        _logger.severe('RLS policy blocked insert/update');
        throw Exception('Permission denied. Please check your access rights.');
      }
      _logger.severe('Unexpected error: $e');
      rethrow;
    }
  }

  Future<void> endCallSession(String sessionId, String incidentId) async {
    try {
      final sessionCheck = await SupabaseService.client
          .from('call_sessions')
          .select()
          .eq('id', sessionId)
          .maybeSingle();

      if (sessionCheck == null) {
        _logger.severe('Call session $sessionId not found');
        throw StateError('Call session not found. Unable to end call.');
      }

      await SupabaseService.client
          .from('call_sessions')
          .update({'status': 'ended'}).eq('id', sessionId);

      final incidentCheck = await SupabaseService.client
          .from('incidents')
          .select()
          .eq('id', incidentId)
          .maybeSingle();

      if (incidentCheck == null) {
        _logger.severe('Incident $incidentId not found');
        throw StateError('Incident not found. Unable to resolve.');
      }

      await SupabaseService.client
          .from('incidents')
          .update({'status': 'resolved'}).eq('id', incidentId);

      _logger.info('Call session $sessionId ended.');
    } on SocketException catch (e) {
      _logger.severe('No internet connection', e);
      throw const SocketException(
          'No internet connection. Unable to end call.');
    } on TimeoutException catch (e) {
      _logger.severe('Request timed out', e);
      rethrow;
    } catch (e) {
      if (e is StateError) rethrow;
      if (e.toString().contains('permission denied')) {
        _logger.severe('RLS policy blocked update');
        throw Exception('Permission denied. Unable to update call/incident.');
      }
      _logger.severe('Error ending call session: $e');
      rethrow;
    }
  }

  void dispose() {
    _logger.info('CallService disposed');
  }
}
