import 'package:flutter_test/flutter_test.dart';
 
// Copy these functions from the top of your patient_records.dart

// They are pure functions so they can be tested without Flutter widgets
 
List<Map<String, dynamic>> searchRecords(

  List<Map<String, dynamic>> records,

  String query,

) {

  final q = query.trim().toLowerCase();

  if (q.isEmpty) return records;

  return records.where((r) {

    final title = (r['title'] ?? '').toString().toLowerCase();

    final type = (r['record_type'] ?? '').toString().toLowerCase();

    final desc = (r['description'] ?? '').toString().toLowerCase();

    return title.contains(q) || type.contains(q) || desc.contains(q);

  }).toList();

}
 
List<Map<String, dynamic>> filterByType(

  List<Map<String, dynamic>> records,

  String? type,

) {

  if (type == null || type.trim().isEmpty) return records;

  final t = type.trim().toLowerCase();

  return records

      .where((r) => (r['record_type'] ?? '').toString().toLowerCase() == t)

      .toList();

}
 
List<Map<String, dynamic>> filterByDateRange(

  List<Map<String, dynamic>> records, {

  DateTime? from,

  DateTime? to,

}) {

  if (from == null && to == null) return records;

  return records.where((r) {

    if (r['record_date'] == null) return false;

    final date = DateTime.tryParse(r['record_date'].toString());

    if (date == null) return false;

    if (from != null && date.isBefore(from)) return false;

    if (to != null && date.isAfter(to)) return false;

    return true;

  }).toList();

}
 
List<Map<String, dynamic>> applySearchAndFilter(

  List<Map<String, dynamic>> records, {

  String query = '',

  String? typeFilter,

  DateTime? from,

  DateTime? to,

}) {

  var result = filterByType(records, typeFilter);

  result = filterByDateRange(result, from: from, to: to);

  result = searchRecords(result, query);

  return result;

}
 
List<String> extractImmunizations(List<Map<String, dynamic>> records) {

  return records

      .where((r) {

        final t = (r['record_type'] ?? '').toString().toLowerCase();

        return t == 'immunization' || t == 'vaccine';

      })

      .map((r) => (r['title'] ?? 'Immunization').toString())

      .toList();

}
 
List<String> extractRiskFactors(Map<String, dynamic>? details) {

  if (details == null) return const [];

  final conditions = (details['medical_conditions'] as List?) ?? const [];

  return conditions

      .map((c) => c?.toString() ?? '')

      .where((s) => s.isNotEmpty)

      .toList();

}
 
// ─── Mock data ───────────────────────────────────────────────────────────────
 
final List<Map<String, dynamic>> mockRecords = [

  {

    'id': '1',

    'title': 'Blood Test Results',

    'record_type': 'lab',

    'description': 'Full blood count and cholesterol panel',

    'record_date': '2024-03-15',

  },

  {

    'id': '2',

    'title': 'COVID-19 Vaccine',

    'record_type': 'vaccine',

    'description': 'Pfizer booster dose administered',

    'record_date': '2024-01-10',

  },

  {

    'id': '3',

    'title': 'Flu Immunization',

    'record_type': 'immunization',

    'description': 'Annual flu shot',

    'record_date': '2023-11-05',

  },

  {

    'id': '4',

    'title': 'X-Ray Chest',

    'record_type': 'radiology',

    'description': 'Chest X-ray for suspected pneumonia',

    'record_date': '2024-02-20',

  },

  {

    'id': '5',

    'title': 'Annual Checkup',

    'record_type': 'consultation',

    'description': 'Routine annual physical examination',

    'record_date': '2023-09-01',

  },

  {

    'id': '6',

    'title': 'Prescription Renewal',

    'record_type': 'consultation',

    'description': '',

    'record_date': null,

  },

];
 
// ─── Tests ───────────────────────────────────────────────────────────────────
 
void main() {

  group('searchRecords', () {

    test('returns all records when query is empty', () {

      expect(searchRecords(mockRecords, '').length, equals(mockRecords.length));

    });
 
    test('returns all records when query is only whitespace', () {

      expect(searchRecords(mockRecords, '   ').length, equals(mockRecords.length));

    });
 
    test('matches by title', () {

      final result = searchRecords(mockRecords, 'Blood Test Results');

      expect(result.length, equals(1));

      expect(result.first['id'], equals('1'));

    });
 
    test('matches by partial title', () {

      final result = searchRecords(mockRecords, 'blood');

      expect(result.length, equals(1));

    });
 
    test('is case-insensitive', () {

      expect(

        searchRecords(mockRecords, 'x-ray').length,

        equals(searchRecords(mockRecords, 'X-RAY').length),

      );

    });
 
    test('matches by record_type', () {

      final result = searchRecords(mockRecords, 'radiology');

      expect(result.length, equals(1));

      expect(result.first['id'], equals('4'));

    });
 
    test('matches by description', () {

      final result = searchRecords(mockRecords, 'pneumonia');

      expect(result.length, equals(1));

      expect(result.first['id'], equals('4'));

    });
 
    test('returns multiple matches', () {

      expect(searchRecords(mockRecords, 'consultation').length, equals(2));

    });
 
    test('returns empty list when nothing matches', () {

      expect(searchRecords(mockRecords, 'zzznomatch'), isEmpty);

    });
 
    test('returns empty list when records list is empty', () {

      expect(searchRecords([], 'blood'), isEmpty);

    });
 
    test('handles null title gracefully', () {

      final records = [

        {'id': '99', 'title': null, 'record_type': 'lab', 'description': null},

      ];

      expect(searchRecords(records, 'lab').length, equals(1));

    });

  });
 
  group('filterByType', () {

    test('returns all records when type is null', () {

      expect(filterByType(mockRecords, null).length, equals(mockRecords.length));

    });
 
    test('returns all records when type is empty string', () {

      expect(filterByType(mockRecords, '').length, equals(mockRecords.length));

    });
 
    test('returns all records when type is whitespace', () {

      expect(filterByType(mockRecords, '   ').length, equals(mockRecords.length));

    });
 
    test('filters to only lab records', () {

      final result = filterByType(mockRecords, 'lab');

      expect(result.length, equals(1));

      expect(result.first['id'], equals('1'));

    });
 
    test('filters to only consultation records', () {

      final result = filterByType(mockRecords, 'consultation');

      expect(result.length, equals(2));

      expect(result.map((r) => r['id']), containsAll(['5', '6']));

    });
 
    test('is case-insensitive', () {

      expect(

        filterByType(mockRecords, 'lab').length,

        equals(filterByType(mockRecords, 'LAB').length),

      );

    });
 
    test('returns empty list for unknown type', () {

      expect(filterByType(mockRecords, 'surgery'), isEmpty);

    });
 
    test('returns empty list when records list is empty', () {

      expect(filterByType([], 'lab'), isEmpty);

    });

  });
 
  group('filterByDateRange', () {

    test('returns all records when no range given', () {

      expect(filterByDateRange(mockRecords).length, equals(mockRecords.length));

    });
 
    test('filters records on or after from date', () {

      final result = filterByDateRange(mockRecords, from: DateTime(2024, 1, 1));

      expect(result.map((r) => r['id']), containsAll(['1', '2', '4']));

      expect(result.map((r) => r['id']), isNot(contains('3')));

    });
 
    test('filters records on or before to date', () {

      final result = filterByDateRange(mockRecords, to: DateTime(2023, 12, 31));

      expect(result.map((r) => r['id']), containsAll(['3', '5']));

      expect(result.map((r) => r['id']), isNot(contains('1')));

    });
 
    test('filters records within a date range', () {

      final result = filterByDateRange(

        mockRecords,

        from: DateTime(2024, 1, 1),

        to: DateTime(2024, 2, 28),

      );

      expect(result.length, equals(2));

      expect(result.map((r) => r['id']), containsAll(['2', '4']));

    });
 
    test('excludes records with null record_date', () {

      final result = filterByDateRange(mockRecords, from: DateTime(2020, 1, 1));

      expect(result.map((r) => r['id']), isNot(contains('6')));

    });
 
    test('returns empty list when no records fall in range', () {

      final result = filterByDateRange(

        mockRecords,

        from: DateTime(2030, 1, 1),

        to: DateTime(2031, 1, 1),

      );

      expect(result, isEmpty);

    });

  });
 
  group('applySearchAndFilter', () {

    test('returns all records when no filters applied', () {

      expect(applySearchAndFilter(mockRecords).length, equals(mockRecords.length));

    });
 
    test('applies type filter and search query together', () {

      final result = applySearchAndFilter(

        mockRecords,

        query: 'annual',

        typeFilter: 'consultation',

      );

      expect(result.length, equals(1));

      expect(result.first['id'], equals('5'));

    });
 
    test('applies type filter, date range, and query together', () {

      final result = applySearchAndFilter(

        mockRecords,

        query: 'flu',

        typeFilter: 'immunization',

        from: DateTime(2023, 1, 1),

        to: DateTime(2023, 12, 31),

      );

      expect(result.length, equals(1));

      expect(result.first['id'], equals('3'));

    });
 
    test('returns empty when combined filters match nothing', () {

      final result = applySearchAndFilter(

        mockRecords,

        query: 'blood',

        typeFilter: 'radiology',

      );

      expect(result, isEmpty);

    });
 
    test('query alone filters correctly', () {

      final result = applySearchAndFilter(mockRecords, query: 'vaccine');

      expect(result.length, equals(1));

      expect(result.first['id'], equals('2'));

    });
 
    test('type filter alone filters correctly', () {

      expect(

        applySearchAndFilter(mockRecords, typeFilter: 'consultation').length,

        equals(2),

      );

    });

  });
 
  group('extractImmunizations', () {

    test('extracts immunization type records', () {

      expect(extractImmunizations(mockRecords), contains('Flu Immunization'));

    });
 
    test('extracts vaccine type records', () {

      expect(extractImmunizations(mockRecords), contains('COVID-19 Vaccine'));

    });
 
    test('does not include non-immunization records', () {

      final result = extractImmunizations(mockRecords);

      expect(result, isNot(contains('Blood Test Results')));

      expect(result, isNot(contains('X-Ray Chest')));

    });
 
    test('returns correct count', () {

      expect(extractImmunizations(mockRecords).length, equals(2));

    });
 
    test('returns empty list when no immunizations exist', () {

      final labOnly = [

        {'id': '1', 'title': 'Blood Test', 'record_type': 'lab'},

      ];

      expect(extractImmunizations(labOnly), isEmpty);

    });
 
    test('uses fallback title when title is null', () {

      final records = [

        {'id': '10', 'title': null, 'record_type': 'immunization'},

      ];

      expect(extractImmunizations(records), equals(['Immunization']));

    });
 
    test('is case-insensitive for record_type', () {

      final records = [

        {'id': '11', 'title': 'MMR', 'record_type': 'IMMUNIZATION'},

        {'id': '12', 'title': 'Hep B', 'record_type': 'Vaccine'},

      ];

      expect(extractImmunizations(records).length, equals(2));

    });
 
    test('returns empty list for empty input', () {

      expect(extractImmunizations([]), isEmpty);

    });

  });
 
  group('extractRiskFactors', () {

    test('returns empty list when details is null', () {

      expect(extractRiskFactors(null), isEmpty);

    });
 
    test('returns empty list when medical_conditions is absent', () {

      expect(extractRiskFactors({'allergies': []}), isEmpty);

    });
 
    test('returns empty list when medical_conditions is empty', () {

      expect(extractRiskFactors({'medical_conditions': []}), isEmpty);

    });
 
    test('extracts condition strings', () {

      final details = {

        'medical_conditions': ['Hypertension', 'Type 2 Diabetes'],

      };

      expect(extractRiskFactors(details), equals(['Hypertension', 'Type 2 Diabetes']));

    });
 
    test('filters out empty and null entries', () {

      final details = {

        'medical_conditions': ['Asthma', '', null, 'Obesity'],

      };

      expect(extractRiskFactors(details), equals(['Asthma', 'Obesity']));

    });
 
    test('returns correct count', () {

      final details = {

        'medical_conditions': ['Hypertension', 'Asthma', 'Type 2 Diabetes'],

      };

      expect(extractRiskFactors(details).length, equals(3));

    });

  });

}
 