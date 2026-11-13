import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef BloodBankRow = Map<String, dynamic>;

List<BloodBankRow> bloodBankRows(dynamic data) {
  if (data is! List) throw const FormatException('Invalid blood-bank response');
  return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

/// A command retains its identity AND payload for an uncertain-response retry.
class BloodBankCommand {
  BloodBankCommand(this.hospitalId, this.action, BloodBankRow payload)
      : payload = Map.unmodifiable(payload),
        operationId = _newId();

  final String hospitalId;
  final String action;
  final BloodBankRow payload;
  final String operationId;

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class BloodBankService {
  BloodBankService({SupabaseClient? client})
      : client = client ?? Supabase.instance.client;

  final SupabaseClient client;
  String? get userId => client.auth.currentUser?.id;

  Future<List<BloodBankRow>> access() async =>
      bloodBankRows(await client.rpc('corvia_bb_access'));

  Future<BloodBankRow> dashboard(String hospitalId,
      {String search = '', String status = '', int offset = 0}) async {
    final result = await client.rpc('corvia_bb_dashboard', params: {
      'p_hospital_id': hospitalId,
      'p_search': search,
      'p_status': status,
      'p_offset': offset,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<BloodBankRow>> requests(String hospitalId,
          {int offset = 0}) async =>
      bloodBankRows(await client.rpc('corvia_bb_requests_list', params: {
        'p_hospital_id': hospitalId,
        'p_offset': offset,
      }));

  Future<List<BloodBankRow>> history(String hospitalId, String unitId,
          {int offset = 0}) async =>
      bloodBankRows(await client.rpc('corvia_bb_history', params: {
        'p_hospital_id': hospitalId,
        'p_unit_id': unitId,
        'p_offset': offset,
      }));

  Future<BloodBankRow> execute(BloodBankCommand command) async {
    final result = await client.rpc('corvia_bb_command', params: {
      'p_hospital_id': command.hospitalId,
      'p_operation_id': command.operationId,
      'p_action': command.action,
      'p_payload': command.payload,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<BloodBankRow> receiveDonor(BloodBankCommand command) async =>
      Map<String, dynamic>.from(await client.rpc(
        'corvia_bb_receive_donor_unit',
        params: {
          'p_hospital_id': command.hospitalId,
          'p_operation_id': command.operationId,
          'p_payload': command.payload,
        },
      ).timeout(const Duration(seconds: 20)) as Map);

  Future<List<BloodBankRow>> patientOptions(
          String hospitalId, String search) async =>
      bloodBankRows(await client.rpc('corvia_bb_patient_options', params: {
        'p_hospital_id': hospitalId,
        'p_search': search,
      }).timeout(const Duration(seconds: 20)));

  Future<List<BloodBankRow>> requestOptions(
          String hospitalId, String unitId, String search) async =>
      bloodBankRows(await client.rpc('corvia_bb_request_options', params: {
        'p_hospital_id': hospitalId,
        'p_unit_id': unitId,
        'p_search': search,
      }).timeout(const Duration(seconds: 20)));

  Future<BloodBankRow> lookupScan(BloodBankCommand command) async =>
      Map<String, dynamic>.from(
          await client.rpc('corvia_bb_lookup_scan', params: {
        'p_hospital_id': command.hospitalId,
        'p_operation_id': command.operationId,
        'p_raw_scan': command.payload['raw_scan'],
      }).timeout(const Duration(seconds: 20)) as Map);

  Future<BloodBankRow> prepareLabel(BloodBankCommand command) async =>
      Map<String, dynamic>.from(
          await client.rpc('corvia_bb_prepare_label', params: {
        'p_hospital_id': command.hospitalId,
        'p_operation_id': command.operationId,
        'p_unit_id': command.payload['unit_id'],
        'p_version': command.payload['version'],
        'p_reason': command.payload['reason'],
      }).timeout(const Duration(seconds: 20)) as Map);

  static String message(Object error) {
    if (error is PostgrestException) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        return 'This blood-bank feature is not installed on this backend. Ask the database '
            'administrator to install the latest blood-bank SQL update.';
      }
      if (accessDenied(error)) {
        return 'Blood-bank access denied or session expired. Sign in again or '
            'ask your administrator to check your hospital membership.';
      }
      return error.message;
    }
    return 'The backend could not confirm the result. Check your connection and retry.';
  }

  static bool accessDenied(Object error) =>
      error is PostgrestException &&
      (error.code == '42501' || (error.code?.startsWith('PGRST30') ?? false));

  // SQL errors roll back the entire command. Transport/gateway errors may have
  // lost a committed response and must retain their operation identity.
  static bool definitelyRejected(Object error) =>
      error is PostgrestException &&
      (error.code == 'P0001' ||
          error.code == '40001' ||
          (error.code?.startsWith('22') ?? false) ||
          (error.code?.startsWith('23') ?? false));
}
