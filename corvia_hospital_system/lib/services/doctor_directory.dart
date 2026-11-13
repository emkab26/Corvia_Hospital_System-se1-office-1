import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'location_service.dart';
import 'supabase_service.dart';

class DoctorEntry {
  DoctorEntry({
    required this.doctorId,
    required this.profileId,
    required this.hospitalId,
    required this.firstName,
    required this.surname,
    required this.specialization,
    required this.practiceName,
    required this.location,
    required this.availabilitySummary,
    required this.available,
    required this.isVerified,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    this.fullName = '',
    this.slotDurationMinutes = 30,
    this.workStart = const TimeOfDay(hour: 8, minute: 0),
    this.workEnd = const TimeOfDay(hour: 17, minute: 0),
    this.workingDays = const [1, 2, 3, 4, 5],
  });

  final String doctorId;
  final String? profileId;
  final String? hospitalId;
  final String firstName;
  final String surname;
  final String fullName;
  final String specialization;
  final String practiceName;
  final String location;
  final String availabilitySummary;
  final bool available;
  final bool isVerified;
  final double? latitude;
  final double? longitude;
  final double distanceMeters;
  final int slotDurationMinutes;
  final TimeOfDay workStart;
  final TimeOfDay workEnd;
  final List<int> workingDays;

  String get displayName {
    final nameFromFullName = fullName.trim();
    final nameFromParts = '$firstName $surname'.trim();

    final name = nameFromFullName.isNotEmpty ? nameFromFullName : nameFromParts;

    if (name.isEmpty) return 'Doctor';

    final lower = name.toLowerCase();

    if (lower.startsWith('dr ') ||
        lower.startsWith('dr. ') ||
        lower.startsWith('doctor ')) {
      return name;
    }

    return 'Dr. $name';
  }

  String get distanceLabel {
    if (distanceMeters.isInfinite) return '';
    return LocationService.formatDistance(distanceMeters);
  }
}

TimeOfDay parseTimeString(dynamic raw, TimeOfDay fallback) {
  if (raw == null) return fallback;

  final parts = raw.toString().split(':');
  if (parts.length < 2) return fallback;

  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);

  if (h == null || m == null) return fallback;

  return TimeOfDay(
    hour: h.clamp(0, 23),
    minute: m.clamp(0, 59),
  );
}

bool _boolValue(dynamic raw, {bool defaultValue = false}) {
  if (raw == null) return defaultValue;
  if (raw is bool) return raw;

  final value = raw.toString().trim().toLowerCase();

  if (value == 'true' || value == '1' || value == 'yes') return true;
  if (value == 'false' || value == '0' || value == 'no') return false;

  return defaultValue;
}

int _intValue(dynamic raw, int fallback) {
  if (raw == null) return fallback;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();

  return int.tryParse(raw.toString()) ?? fallback;
}

double? _doubleValue(dynamic raw) {
  if (raw == null) return null;
  if (raw is double) return raw;
  if (raw is int) return raw.toDouble();
  if (raw is num) return raw.toDouble();

  return double.tryParse(raw.toString());
}

String _textValue(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];

    if (value == null) continue;

    final text = value.toString().trim();

    if (text.isNotEmpty && text.toLowerCase() != 'null') {
      return text;
    }
  }

  return '';
}

List<int> _workingDaysValue(dynamic raw) {
  if (raw == null) return const [1, 2, 3, 4, 5];

  final days = <int>[];

  if (raw is List) {
    for (final item in raw) {
      final parsed = int.tryParse(item.toString());
      if (parsed != null && parsed >= 1 && parsed <= 7) {
        days.add(parsed);
      }
    }
  } else {
    final matches = RegExp(r'\d+').allMatches(raw.toString());

    for (final match in matches) {
      final parsed = int.tryParse(match.group(0) ?? '');
      if (parsed != null && parsed >= 1 && parsed <= 7) {
        days.add(parsed);
      }
    }
  }

  if (days.isEmpty) return const [1, 2, 3, 4, 5];

  final unique = days.toSet().toList()..sort();
  return unique;
}

String _titleCaseNameFromEmail(String email) {
  final beforeAt = email.split('@').first.trim();

  if (beforeAt.isEmpty) return '';

  final parts = beforeAt
      .split(RegExp(r'[._\-\s]+'))
      .where((part) => part.trim().isNotEmpty)
      .toList();

  if (parts.isEmpty) return '';

  return parts.map((part) {
    final lower = part.toLowerCase();

    if (lower.isEmpty) return '';

    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }).join(' ');
}

bool _isPlaceholderName(String name) {
  final lower = name.trim().toLowerCase();

  return lower.isEmpty ||
      lower == 'doctor' ||
      lower == 'corvia patient' ||
      lower == 'patient' ||
      lower == 'test patient';
}

Future<Position?> _safeCurrentPosition() async {
  if (kIsWeb) {
    return null;
  }

  try {
    return await LocationService.currentPosition().timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  }
}

class DoctorDirectory {
  static Future<List<DoctorEntry>> load({
    bool requireAvailable = true,
    bool requireVerified = true,
  }) async {
    final client = SupabaseService.client;

    List rawDoctors;

    try {
      rawDoctors = await client
          .from('doctors')
          .select()
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('DoctorDirectory doctors lookup failed: $e');
      rethrow;
    }

    final doctorRows = rawDoctors
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final profileIds = doctorRows
        .map((row) => row['profile_id']?.toString())
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();

    final profilesByUserId = <String, Map<String, dynamic>>{};

    if (profileIds.isNotEmpty) {
      try {
        final rawProfiles = await client
            .from('profiles')
            .select('user_id, first_name, surname, email, user_type, role')
            .inFilter('user_id', profileIds)
            .timeout(const Duration(seconds: 8));

        final profileRows = rawProfiles
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        for (final profile in profileRows) {
          final userId = profile['user_id']?.toString();

          if (userId != null && userId.trim().isNotEmpty) {
            profilesByUserId[userId] = profile;
          }
        }
      } catch (e) {
        debugPrint('DoctorDirectory profile lookup failed: $e');
      }
    }

    final position = await _safeCurrentPosition();

    final entries = <DoctorEntry>[];

    for (final doctor in doctorRows) {
      final isActive = _boolValue(
        doctor['is_active'],
        defaultValue: true,
      );

      final available = _boolValue(
            doctor['available'],
            defaultValue: true,
          ) &&
          _boolValue(
            doctor['is_available'],
            defaultValue: true,
          );

      final isVerified = _boolValue(
        doctor['is_verified'],
        defaultValue: true,
      );

      if (!isActive) continue;
      if (requireAvailable && !available) continue;
      if (requireVerified && !isVerified) continue;

      final profileId = doctor['profile_id']?.toString();
      final profile = profileId == null ? null : profilesByUserId[profileId];

      final profileFirstName = profile?['first_name']?.toString().trim() ?? '';
      final profileSurname = profile?['surname']?.toString().trim() ?? '';
      final profileEmail = profile?['email']?.toString().trim() ?? '';

      final profileFullName = '$profileFirstName $profileSurname'.trim();

      final doctorFullName = _textValue(
        doctor,
        ['full_name', 'display_name', 'doctor_name', 'name'],
      );

      final emailName =
          profileEmail.isEmpty ? '' : _titleCaseNameFromEmail(profileEmail);

      String finalFullName = doctorFullName;

      if (_isPlaceholderName(finalFullName)) {
        finalFullName = profileFullName;
      }

      if (_isPlaceholderName(finalFullName)) {
        finalFullName = emailName;
      }

      final nameParts = finalFullName.split(RegExp(r'\s+'));

      final firstName = profileFirstName.isNotEmpty &&
              !_isPlaceholderName('$profileFirstName $profileSurname')
          ? profileFirstName
          : nameParts.isNotEmpty
              ? nameParts.first
              : '';

      final surname = profileSurname.isNotEmpty &&
              !_isPlaceholderName('$profileFirstName $profileSurname')
          ? profileSurname
          : nameParts.length > 1
              ? nameParts.sublist(1).join(' ')
              : '';

      final lat = _doubleValue(doctor['latitude']);
      final lng = _doubleValue(doctor['longitude']);

      final distance = LocationService.distanceMeters(
        aLat: position?.latitude,
        aLng: position?.longitude,
        bLat: lat,
        bLng: lng,
      );

      entries.add(
        DoctorEntry(
          doctorId: doctor['id'].toString(),
          profileId: profileId,
          hospitalId: doctor['hospital_id']?.toString(),
          fullName: finalFullName,
          firstName: firstName,
          surname: surname,
          specialization: _textValue(
            doctor,
            ['specialization', 'speciality', 'department'],
          ),
          practiceName: _textValue(
            doctor,
            ['practice_name', 'hospital', 'clinic', 'practice'],
          ),
          location: _textValue(
            doctor,
            ['location', 'location_name', 'address'],
          ),
          availabilitySummary: _textValue(
            doctor,
            ['availability', 'availability_summary', 'schedule', 'hours'],
          ),
          available: available,
          isVerified: isVerified,
          latitude: lat,
          longitude: lng,
          distanceMeters: distance,
          slotDurationMinutes: _intValue(
            doctor['slot_duration_minutes'],
            30,
          ),
          workStart: parseTimeString(
            doctor['work_start'],
            const TimeOfDay(hour: 8, minute: 0),
          ),
          workEnd: parseTimeString(
            doctor['work_end'],
            const TimeOfDay(hour: 17, minute: 0),
          ),
          workingDays: _workingDaysValue(
            doctor['working_days'],
          ),
        ),
      );
    }

    entries.sort((a, b) {
      if (position != null) {
        final ad = a.distanceMeters;
        final bd = b.distanceMeters;

        if (ad != bd) return ad.compareTo(bd);
      }

      return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
    });

    return entries;
  }

  static Future<bool> userLocationAvailable() async {
    final p = await _safeCurrentPosition();
    return p != null;
  }
}

typedef UserPosition = Position;
