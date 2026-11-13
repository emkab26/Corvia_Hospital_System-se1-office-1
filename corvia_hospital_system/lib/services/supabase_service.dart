import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String _patientRegistrationType = 'patient_self_registration';

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;
  static String? get currentUserId => currentUser?.id;
  static bool get isSignedIn => currentUser != null;

  static Future<void> signOut() => client.auth.signOut();

  static Map<String, dynamic> _withoutNulls(Map<String, dynamic> value) {
    final cleaned = <String, dynamic>{};

    value.forEach((key, item) {
      if (item == null) return;
      if (item is String && item.trim().isEmpty) return;
      cleaned[key] = item;
    });

    return cleaned;
  }

  static bool _isStaffRole(String userType) {
    final role = userType.toLowerCase().trim();

    return role == 'doctor' ||
        role == 'specialist' ||
        role == 'admin' ||
        role == 'hospital_admin' ||
        role == 'reception' ||
        role == 'receptionist' ||
        role == 'nurse' ||
        role == 'dispatch' ||
        role == 'paramedic' ||
        role == 'lab_technician' ||
        role == 'lab_worker' ||
        role == 'pharmacy' ||
        role == 'pharmacist';
  }

  static bool isPatientSelfRegistrationMetadata(
    Map<String, dynamic>? metadata,
  ) {
    final registrationType =
        metadata?['corvia_registration_type']?.toString().trim().toLowerCase();

    return registrationType == _patientRegistrationType;
  }

  static bool isPatientSelfRegistration(User user) {
    return isPatientSelfRegistrationMetadata(user.userMetadata);
  }

  static String? _metadataText(
    Map<String, dynamic> metadata,
    String key,
  ) {
    final value = metadata[key]?.toString().trim();

    if (value == null || value.isEmpty || value.toLowerCase() == 'null') {
      return null;
    }

    return value;
  }

  static Future<void> ensureUserMedicalRecords({
    bool createPatientRow = true,
  }) async {
    final user = currentUser;
    final userId = user?.id;

    if (user == null || userId == null) {
      return;
    }

    final email = user.email;
    final now = DateTime.now().toIso8601String();
    final metadata = Map<String, dynamic>.from(
      user.userMetadata ?? const <String, dynamic>{},
    );

    Map<String, dynamic>? profile = await client
        .from('profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (profile == null) {
      // Only patient self-registration is allowed to bootstrap a missing
      // profile from client-controlled metadata. Staff access always requires
      // an administrator-created database profile and relationship row.
      if (!isPatientSelfRegistration(user)) {
        return;
      }

      await client.from('profiles').insert(
            _withoutNulls({
              'user_id': userId,
              'email': email,
              'first_name': _metadataText(metadata, 'first_name'),
              'surname': _metadataText(metadata, 'surname'),
              'id_number': _metadataText(metadata, 'id_number'),
              'address': _metadataText(metadata, 'address'),
              'phone': _metadataText(metadata, 'phone'),
              'phone_number': _metadataText(metadata, 'phone'),
              'date_of_birth': _metadataText(metadata, 'date_of_birth'),
              'profile_complete': false,
            }),
          );

      profile = await client
          .from('profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
    } else {
      final updateData = _withoutNulls({
        'email': profile['email'] ?? email,
        'profile_complete': profile['profile_complete'] ?? false,
      });

      if (updateData.isNotEmpty) {
        await client.from('profiles').update(updateData).eq('user_id', userId);
      }
    }

    final userType = (profile?['user_type'] ?? profile?['role'] ?? 'patient')
        .toString()
        .toLowerCase()
        .trim();

    if (_isStaffRole(userType)) {
      return;
    }

    if (!createPatientRow) {
      return;
    }

    final existingPatient = await client
        .from('patients')
        .select('id')
        .eq('profile_id', userId)
        .maybeSingle();

    if (existingPatient != null) {
      return;
    }

    final hospitalId = await _singleActiveHospitalId();
    final dateOfBirth = _metadataText(metadata, 'date_of_birth');
    final phone = _metadataText(metadata, 'phone');

    await client.from('patients').upsert(
          _withoutNulls({
            'profile_id': userId,
            'hospital_id': hospitalId,
            'email': email,
            'date_of_birth': dateOfBirth,
            'emergency_contact_phone': phone,
            'is_active': true,
            'created_by': userId,
            'updated_by': userId,
            'updated_at': now,
          }),
          onConflict: 'profile_id',
        );

    await _ensureInitialEmergencyProfile(
      userId: userId,
      firstName: _metadataText(metadata, 'first_name'),
      surname: _metadataText(metadata, 'surname'),
      phone: phone,
    );
  }

  static Future<void> _ensureInitialEmergencyProfile({
    required String userId,
    required String? firstName,
    required String? surname,
    required String? phone,
  }) async {
    try {
      final patient = await client
          .from('patients')
          .select('id')
          .eq('profile_id', userId)
          .maybeSingle();

      final patientId = patient?['id']?.toString().trim();

      if (patientId == null || patientId.isEmpty) {
        return;
      }

      final patientName = [firstName, surname]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join(' ')
          .trim();

      await client.from('emergency_profiles').upsert(
            _withoutNulls({
              'patient_id': patientId,
              'created_by': userId,
              'patient_name': patientName,
              'emergency_contact_phone': phone,
              'allergies': 'Not provided',
              'current_medications': 'Not provided',
              'medical_conditions': 'Not provided',
              'notes': 'Created during registration.',
            }),
            onConflict: 'patient_id',
          );
    } catch (error, stackTrace) {
      // Emergency details are optional at first login and can be completed
      // later. A failure here must not strand a newly verified account.
      debugPrint(
        'Initial emergency profile bootstrap skipped: $error\n$stackTrace',
      );
    }
  }

  static Future<String?> _singleActiveHospitalId() async {
    try {
      final hospitals = await client
          .from('hospitals')
          .select('id')
          .eq('is_active', true)
          .limit(2);

      if (hospitals.length == 1) {
        return hospitals.first['id']?.toString();
      }

      if (hospitals.isNotEmpty) {
        return hospitals.first['id']?.toString();
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> currentProfile() async {
    final id = currentUserId;
    if (id == null) return null;

    return await client
        .from('profiles')
        .select()
        .eq('user_id', id)
        .maybeSingle();
  }

  static Future<String?> currentUserType() async {
    final id = currentUserId;
    if (id == null) return null;

    var profile = await currentProfile();

    if (profile == null) {
      await ensureUserMedicalRecords(createPatientRow: false);
      profile = await currentProfile();
    }

    final userType = profile?['user_type']?.toString();
    final role = profile?['role']?.toString();

    if (userType != null && userType.trim().isNotEmpty) {
      return userType;
    }

    if (role != null && role.trim().isNotEmpty) {
      return role;
    }

    return 'patient';
  }

  static Future<List<Map<String, dynamic>>> getDoctors() async {
    final res = await client.from('doctors').select('id, full_name, location');

    return List<Map<String, dynamic>>.from(res);
  }

  static Future<bool> isDoctor() async {
    final id = currentUserId;
    if (id == null) return false;

    final rows = await client
        .from('doctors')
        .select('id, is_active')
        .eq('profile_id', id);

    return rows.any(
      (record) => record['is_active'] != false,
    );
  }

  static Future<String?> currentDoctorId() async {
    final id = currentUserId;
    if (id == null) return null;

    final rows = await client
        .from('doctors')
        .select('id, is_active')
        .eq('profile_id', id);

    for (final record in rows) {
      if (record['is_active'] != false) {
        return record['id']?.toString();
      }
    }

    return null;
  }

  static Future<bool> hasActiveSubscription() async {
    final id = currentUserId;
    if (id == null) return false;

    try {
      final res = await client
          .from('subscriptions')
          .select('status')
          .eq('user_id', id)
          .maybeSingle();

      if (res == null) return false;

      return (res['status']?.toString().toLowerCase()) == 'active';
    } catch (_) {
      return false;
    }
  }

  // Registration stores patients.profile_id as profiles.id (not auth.uid),
  // so we first resolve the profile row, then look up the patient.
  static Future<String?> currentPatientId() async {
    final id = currentUserId; // auth.uid()
    if (id == null) return null;

    // patients.profile_id FKs to profiles(user_id), i.e. it stores the auth
    // uid directly - same pattern as currentDoctorId(). Do NOT indirect through
    // profiles.id (a separate gen_random_uuid column), which never matches.
    var res = await client
        .from('patients')
        .select('id')
        .eq('profile_id', id)
        .maybeSingle();

    if (res != null) {
      return res['id']?.toString();
    }

    await ensureUserMedicalRecords(createPatientRow: true);

    res = await client
        .from('patients')
        .select('id')
        .eq('profile_id', id)
        .maybeSingle();

    return res?['id']?.toString();
  }
}
