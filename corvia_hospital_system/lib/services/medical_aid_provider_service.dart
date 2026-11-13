import 'package:supabase_flutter/supabase_flutter.dart';

class MedicalAidProvider {
  final String id;
  final String name;
  final int displayOrder;
  final bool isActive;

  const MedicalAidProvider({
    required this.id,
    required this.name,
    required this.displayOrder,
    required this.isActive,
  });

  factory MedicalAidProvider.fromMap(Map<String, dynamic> map) {
    return MedicalAidProvider(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      displayOrder: map['display_order'] is int
          ? map['display_order'] as int
          : int.tryParse(map['display_order']?.toString() ?? '99') ?? 99,
      isActive: map['is_active'] == true,
    );
  }
}

class MedicalAidProviderService {
  MedicalAidProviderService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static Future<List<MedicalAidProvider>> getActiveProviders() async {
    final response = await _client
        .from('medical_aid_providers')
        .select('id, name, display_order, is_active')
        .eq('is_active', true)
        .order('display_order', ascending: true);

    final rows = List<Map<String, dynamic>>.from(response);

    return rows
        .map(MedicalAidProvider.fromMap)
        .where((provider) => provider.id.isNotEmpty && provider.name.isNotEmpty)
        .toList();
  }
}
