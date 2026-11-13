import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CorviaAiContext {
  const CorviaAiContext({
    required this.fromCache,
    required this.userId,
    required this.profile,
    required this.patient,
    required this.emergencyProfile,
    required this.activePrescriptions,
    required this.upcomingAppointments,
    required this.medicationReminders,
    required this.symptomIntakes,
    required this.labExplanations,
    required this.timelineItems,
  });

  final bool fromCache;
  final String? userId;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? patient;
  final Map<String, dynamic>? emergencyProfile;
  final List<Map<String, dynamic>> activePrescriptions;
  final List<Map<String, dynamic>> upcomingAppointments;
  final List<Map<String, dynamic>> medicationReminders;
  final List<Map<String, dynamic>> symptomIntakes;
  final List<Map<String, dynamic>> labExplanations;
  final List<Map<String, dynamic>> timelineItems;

  String? get patientId => patient?['id']?.toString();

  String get patientName {
    final emergencyName =
        emergencyProfile?['patient_name']?.toString().trim() ?? '';

    if (emergencyName.isNotEmpty && emergencyName.toLowerCase() != 'null') {
      return emergencyName;
    }

    final firstName = profile?['first_name']?.toString().trim() ?? '';
    final surname = profile?['surname']?.toString().trim() ?? '';

    final fullName = '$firstName $surname'.trim();

    if (fullName.isNotEmpty) return fullName;

    return 'Patient';
  }

  String get allergies {
    final emergencyValue =
        emergencyProfile?['allergies']?.toString().trim() ?? '';

    if (_hasValue(emergencyValue)) return emergencyValue;

    final patientValue = patient?['allergies']?.toString().trim() ?? '';

    if (_hasValue(patientValue)) return patientValue;

    return 'Not provided';
  }

  String get bloodType {
    final emergencyValue =
        emergencyProfile?['blood_type']?.toString().trim() ?? '';

    if (_hasValue(emergencyValue)) return emergencyValue;

    final patientValue = patient?['blood_type']?.toString().trim() ?? '';

    if (_hasValue(patientValue)) return patientValue;

    return 'Not provided';
  }

  String get medicalConditions {
    final emergencyValue =
        emergencyProfile?['medical_conditions']?.toString().trim() ?? '';

    if (_hasValue(emergencyValue)) return emergencyValue;

    final patientValue =
        patient?['medical_conditions']?.toString().trim() ?? '';

    if (_hasValue(patientValue)) return patientValue;

    return 'Not provided';
  }

  String get currentMedications {
    final emergencyValue =
        emergencyProfile?['current_medications']?.toString().trim() ?? '';

    if (_hasValue(emergencyValue)) return emergencyValue;

    if (activePrescriptions.isNotEmpty) {
      return activePrescriptions.map((p) {
        final name = p['medication_name']?.toString().trim() ?? 'Medication';
        final dose = p['dosage']?.toString().trim() ?? '';
        return dose.isEmpty ? name : '$name - $dose';
      }).join(', ');
    }

    return 'Not provided';
  }

  String get emergencyContact {
    final name =
        emergencyProfile?['emergency_contact_name']?.toString().trim() ?? '';
    final phone =
        emergencyProfile?['emergency_contact_phone']?.toString().trim() ?? '';

    if (name.isNotEmpty && phone.isNotEmpty) return '$name - $phone';
    if (phone.isNotEmpty) return phone;

    final patientPhone =
        patient?['emergency_contact_phone']?.toString().trim() ?? '';

    if (patientPhone.isNotEmpty) return patientPhone;

    return 'Not provided';
  }

  String get medicalAid {
    final provider =
        emergencyProfile?['medical_aid_provider']?.toString().trim() ??
            patient?['medical_aid_provider']?.toString().trim() ??
            '';

    final number =
        emergencyProfile?['medical_aid_member_number']?.toString().trim() ??
            patient?['medical_aid_member_number']?.toString().trim() ??
            '';

    if (provider.isEmpty && number.isEmpty) return 'Not provided';
    if (provider.isNotEmpty && number.isNotEmpty) return '$provider - $number';
    return provider.isNotEmpty ? provider : number;
  }

  String toPromptContext() {
    final prescriptionsText = activePrescriptions.isEmpty
        ? 'None listed'
        : activePrescriptions.take(6).map((p) {
            final name = p['medication_name']?.toString() ?? 'Medication';
            final dose = p['dosage']?.toString() ?? '';
            final instructions = p['instructions']?.toString() ?? '';
            return '- $name ${dose.isEmpty ? '' : '($dose)'} ${instructions.isEmpty ? '' : '- $instructions'}';
          }).join('\n');

    final appointmentsText = upcomingAppointments.isEmpty
        ? 'None listed'
        : upcomingAppointments.take(6).map((a) {
            final date = a['appointment_date']?.toString() ?? 'Date unknown';
            final reason = a['reason']?.toString() ?? 'No reason listed';
            final status = a['status']?.toString() ?? 'scheduled';
            return '- $date | $reason | $status';
          }).join('\n');

    final remindersText = medicationReminders.isEmpty
        ? 'None listed'
        : medicationReminders.take(6).map((r) {
            final name = r['medication_name']?.toString() ?? 'Medication';
            final time = r['time_of_day']?.toString() ?? 'Time not set';
            return '- $name | $time';
          }).join('\n');

    final symptomsText = symptomIntakes.isEmpty
        ? 'None listed'
        : symptomIntakes.take(5).map((s) {
            final symptoms = s['symptoms']?.toString() ?? '';
            final duration = s['duration']?.toString() ?? '';
            return '- ${_shorten(symptoms, 140)} ${duration.isEmpty ? '' : '| Duration: $duration'}';
          }).join('\n');

    final labsText = labExplanations.isEmpty
        ? 'None listed'
        : labExplanations.take(4).map((l) {
            final text = l['lab_result_text']?.toString() ?? '';
            final explanation = l['ai_explanation']?.toString() ?? '';
            return '- Result: ${_shorten(text, 120)} | Explanation: ${_shorten(explanation, 160)}';
          }).join('\n');

    return '''
Corvia patient context:
Source: ${fromCache ? 'Cached offline phone data' : 'Live Supabase data'}
Patient: $patientName
Blood type: $bloodType
Allergies: $allergies
Medical conditions: $medicalConditions
Current medication: $currentMedications
Emergency contact: $emergencyContact
Medical aid: $medicalAid

Active prescriptions:
$prescriptionsText

Upcoming appointments:
$appointmentsText

Medication reminders:
$remindersText

Recent symptom intakes:
$symptomsText

Recent lab explanations:
$labsText
''';
  }

  Map<String, dynamic> toJson() {
    return {
      'fromCache': fromCache,
      'userId': userId,
      'profile': profile,
      'patient': patient,
      'emergencyProfile': emergencyProfile,
      'activePrescriptions': activePrescriptions,
      'upcomingAppointments': upcomingAppointments,
      'medicationReminders': medicationReminders,
      'symptomIntakes': symptomIntakes,
      'labExplanations': labExplanations,
      'timelineItems': timelineItems,
    };
  }

  factory CorviaAiContext.fromJson(
    Map<String, dynamic> json, {
    bool forceCache = false,
  }) {
    return CorviaAiContext(
      fromCache: forceCache || json['fromCache'] == true,
      userId: json['userId']?.toString(),
      profile: _mapOrNull(json['profile']),
      patient: _mapOrNull(json['patient']),
      emergencyProfile: _mapOrNull(json['emergencyProfile']),
      activePrescriptions: _listOfMaps(json['activePrescriptions']),
      upcomingAppointments: _listOfMaps(json['upcomingAppointments']),
      medicationReminders: _listOfMaps(json['medicationReminders']),
      symptomIntakes: _listOfMaps(json['symptomIntakes']),
      labExplanations: _listOfMaps(json['labExplanations']),
      timelineItems: _listOfMaps(json['timelineItems']),
    );
  }

  factory CorviaAiContext.empty({
    String? userId,
    bool fromCache = false,
  }) {
    return CorviaAiContext(
      fromCache: fromCache,
      userId: userId,
      profile: null,
      patient: null,
      emergencyProfile: null,
      activePrescriptions: const [],
      upcomingAppointments: const [],
      medicationReminders: const [],
      symptomIntakes: const [],
      labExplanations: const [],
      timelineItems: const [],
    );
  }

  static bool _hasValue(String value) {
    final clean = value.trim().toLowerCase();
    return clean.isNotEmpty && clean != 'null' && clean != 'not provided';
  }

  static Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _shorten(String text, int max) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (clean.length <= max) return clean;

    return '${clean.substring(0, max)}...';
  }
}

class CorviaAiContextService {
  CorviaAiContextService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static Future<CorviaAiContext> load() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return CorviaAiContext.empty();
    }

    try {
      final fresh = await _loadFresh(user.id);
      await _cache(fresh);
      return fresh;
    } catch (_) {
      final cached = await _loadCached(user.id);

      if (cached != null) {
        return cached;
      }

      return CorviaAiContext.empty(userId: user.id, fromCache: true);
    }
  }

  static Future<CorviaAiContext> _loadFresh(String userId) async {
    final dynamic profileRes = await _client
        .from('profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    final Map<String, dynamic>? profile =
        profileRes == null ? null : Map<String, dynamic>.from(profileRes);

    Map<String, dynamic>? patient;
    Map<String, dynamic>? emergencyProfile;

    List<Map<String, dynamic>> activePrescriptions = [];
    List<Map<String, dynamic>> upcomingAppointments = [];
    List<Map<String, dynamic>> medicationReminders = [];
    List<Map<String, dynamic>> symptomIntakes = [];
    List<Map<String, dynamic>> labExplanations = [];
    List<Map<String, dynamic>> timelineItems = [];

    final profileId = profile?['id']?.toString();

    if (profileId != null && profileId.isNotEmpty) {
      final dynamic patientRes = await _client
          .from('patients')
          .select()
          .eq('profile_id', profileId)
          .maybeSingle();

      patient =
          patientRes == null ? null : Map<String, dynamic>.from(patientRes);
    }

    final patientId = patient?['id']?.toString();

    if (patientId != null && patientId.isNotEmpty) {
      final dynamic emergencyRes = await _client
          .from('emergency_profiles')
          .select()
          .eq('patient_id', patientId)
          .maybeSingle();

      emergencyProfile =
          emergencyRes == null ? null : Map<String, dynamic>.from(emergencyRes);

      final dynamic prescriptionsRes = await _client
          .from('prescriptions')
          .select()
          .eq('patient_id', patientId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(10);

      activePrescriptions = _asList(prescriptionsRes);

      final dynamic appointmentsRes = await _client
          .from('appointments')
          .select()
          .eq('patient_id', patientId)
          .inFilter('status', ['scheduled', 'confirmed', 'checked_in'])
          .gte('appointment_date', DateTime.now().toUtc().toIso8601String())
          .order('appointment_date', ascending: true)
          .limit(10);

      upcomingAppointments = _asList(appointmentsRes);

      final dynamic remindersRes = await _client
          .from('medication_reminders')
          .select()
          .eq('patient_id', patientId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(10);

      medicationReminders = _asList(remindersRes);

      final dynamic symptomsRes = await _client
          .from('ai_symptom_intakes')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false)
          .limit(5);

      symptomIntakes = _asList(symptomsRes);

      final dynamic labsRes = await _client
          .from('lab_result_explanations')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false)
          .limit(5);

      labExplanations = _asList(labsRes);

      final dynamic timelineRes = await _client
          .from('patient_timeline_items')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false)
          .limit(12);

      timelineItems = _asList(timelineRes);
    }

    return CorviaAiContext(
      fromCache: false,
      userId: userId,
      profile: profile,
      patient: patient,
      emergencyProfile: emergencyProfile,
      activePrescriptions: activePrescriptions,
      upcomingAppointments: upcomingAppointments,
      medicationReminders: medicationReminders,
      symptomIntakes: symptomIntakes,
      labExplanations: labExplanations,
      timelineItems: timelineItems,
    );
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> _cache(CorviaAiContext context) async {
    final userId = context.userId;

    if (userId == null || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _cacheKey(userId),
      jsonEncode(context.toJson()),
    );
  }

  static Future<CorviaAiContext?> _loadCached(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(userId));

    if (raw == null || raw.trim().isEmpty) return null;

    final decoded = jsonDecode(raw);

    if (decoded is! Map<String, dynamic>) return null;

    return CorviaAiContext.fromJson(decoded, forceCache: true);
  }

  static String _cacheKey(String userId) {
    return 'corvia_ai_context_cache_$userId';
  }
}
