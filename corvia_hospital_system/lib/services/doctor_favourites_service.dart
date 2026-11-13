import 'supabase_service.dart';

/// Manages the signed-in patient's favourite doctors.
///
/// Backed by `public.patient_favourite_doctors (patient_id, doctor_id)`, where
/// `patient_id` is `patients.id` and `doctor_id` is `doctors.id` (the same id
/// as `DoctorEntry.doctorId`). Favourites are shown first in doctor lists.
class DoctorFavouritesService {
  static const String _table = 'patient_favourite_doctors';

  /// Looks up the patient row without creating one; favourites are not a
  /// reason to provision a patient record.
  static Future<String?> _patientId() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return null;

    final row = await SupabaseService.client
        .from('patients')
        .select('id')
        .eq('profile_id', userId)
        .maybeSingle();

    return row?['id']?.toString();
  }

  static Future<Set<String>> fetchFavouriteIds() async {
    final patientId = await _patientId();
    if (patientId == null) return {};

    final rows = await SupabaseService.client
        .from(_table)
        .select('doctor_id')
        .eq('patient_id', patientId);

    return (rows as List)
        .map((r) => r['doctor_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Future<void> addFavourite(String doctorId) async {
    final patientId = await _patientId();
    if (patientId == null) {
      throw StateError('No patient record is linked to this account.');
    }

    // The table has no unique (patient_id, doctor_id) constraint, so check
    // first instead of relying on an upsert conflict target.
    final existing = await SupabaseService.client
        .from(_table)
        .select('id')
        .eq('patient_id', patientId)
        .eq('doctor_id', doctorId)
        .limit(1);

    if ((existing as List).isNotEmpty) return;

    await SupabaseService.client.from(_table).insert({
      'patient_id': patientId,
      'doctor_id': doctorId,
    });
  }

  static Future<void> removeFavourite(String doctorId) async {
    final patientId = await _patientId();
    if (patientId == null) return;

    await SupabaseService.client
        .from(_table)
        .delete()
        .eq('patient_id', patientId)
        .eq('doctor_id', doctorId);
  }

  static Future<void> toggleFavourite(
    String doctorId, {
    required bool isFavourite,
  }) {
    return isFavourite ? addFavourite(doctorId) : removeFavourite(doctorId);
  }

  /// Returns [doctors] with favourites first, otherwise keeping their order
  /// (which may already be sorted by distance).
  static List<T> favouritesFirst<T>(
    List<T> doctors,
    Set<String> favouriteIds,
    String Function(T doctor) idOf,
  ) {
    final favourites = <T>[];
    final others = <T>[];
    for (final doctor in doctors) {
      (favouriteIds.contains(idOf(doctor)) ? favourites : others).add(doctor);
    }
    return [...favourites, ...others];
  }
}
