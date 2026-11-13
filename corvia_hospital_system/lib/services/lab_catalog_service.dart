import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class LabCatalogItem {
  const LabCatalogItem({
    required this.name,
    required this.description,
    required this.price,
  });

  final String name;
  final String description;
  final num price;

  factory LabCatalogItem.fromMap(
    Map<String, dynamic> map,
  ) {
    final rawPrice = map['price'];

    num price = 0;

    if (rawPrice is num) {
      price = rawPrice;
    } else if (rawPrice != null) {
      price = num.tryParse(
            rawPrice
                .toString()
                .replaceAll(',', '.')
                .replaceAll('R', '')
                .trim(),
          ) ??
          0;
    }

    return LabCatalogItem(
      name: map['name']?.toString().trim() ?? '',
      description: map['description']?.toString().trim() ?? '',
      price: price,
    );
  }
}

class LabCatalogGroup {
  const LabCatalogGroup({
    required this.heading,
    required this.tests,
  });

  final String heading;
  final List<LabCatalogItem> tests;
}

class LabCatalogService {
  LabCatalogService._();

  static final SupabaseClient _supabase =
      Supabase.instance.client;

  static Future<List<LabCatalogGroup>> loadCatalog() async {
    final signedUrl = await _supabase.storage
        .from('Config')
        .createSignedUrl(
          'List.json',
          3600,
        );

    final response = await http.get(
      Uri.parse(signedUrl),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Lab test catalogue could not load. '
        'HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(
      utf8.decode(
        response.bodyBytes,
      ),
    );

    if (decoded is! Map) {
      throw Exception(
        'Lab test catalogue has an invalid format.',
      );
    }

    final map = Map<String, dynamic>.from(
      decoded,
    );

    final rawHeadings = map['headings'];
    final rawTests = map['tests'];

    if (rawTests is! List) {
      throw Exception(
        'Lab test catalogue does not contain a tests list.',
      );
    }

    final List<String> headings;

    if (rawHeadings is List) {
      headings = rawHeadings
          .map(
            (value) =>
                value?.toString().trim() ?? '',
          )
          .toList(
            growable: false,
          );
    } else {
      headings = <String>[];
    }

    final groups = <LabCatalogGroup>[];

    for (
      var groupIndex = 0;
      groupIndex < rawTests.length;
      groupIndex++
    ) {
      final rawGroup = rawTests[groupIndex];

      if (rawGroup is! List) {
        continue;
      }

      final items = <LabCatalogItem>[];

      for (final rawItem in rawGroup) {
        if (rawItem is! Map) {
          continue;
        }

        final item = LabCatalogItem.fromMap(
          Map<String, dynamic>.from(
            rawItem,
          ),
        );

        if (item.name.isNotEmpty) {
          items.add(
            item,
          );
        }
      }

      if (items.isEmpty) {
        continue;
      }

      String heading = 'Laboratory Tests';

      if (groupIndex < headings.length) {
        final candidate =
            headings[groupIndex].trim();

        if (candidate.isNotEmpty) {
          heading = candidate;
        }
      }

      groups.add(
        LabCatalogGroup(
          heading: heading,
          tests: items,
        ),
      );
    }

    if (groups.isEmpty) {
      throw Exception(
        'No laboratory tests were found in the catalogue.',
      );
    }

    return groups;
  }

  static Future<List<String>> loadTestNames() async {
    final groups = await loadCatalog();

    final names = <String>{};

    for (final group in groups) {
      for (final test in group.tests) {
        final name = test.name.trim();

        if (name.isNotEmpty) {
          names.add(
            name,
          );
        }
      }
    }

    final result = names.toList()
      ..sort(
        (a, b) => a.toLowerCase().compareTo(
              b.toLowerCase(),
            ),
      );

    return result;
  }
}