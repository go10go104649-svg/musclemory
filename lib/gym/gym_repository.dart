import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class GymStore {
  const GymStore({
    required this.id,
    required this.chainName,
    required this.name,
    this.city,
    this.address,
    this.station,
    this.equipmentStatus = 'not_collected',
  });
  final String id, chainName, name, equipmentStatus;
  final String? city, address, station;
  String get displayName => '$chainName $name'.trim();
  factory GymStore.fromJson(Map<String, dynamic> j) => GymStore(
    id: j['id'] as String,
    chainName:
        j['chain_name'] as String? ??
        (j['gym_chains'] as Map?)?['name'] as String? ??
        '',
    name: j['name'] as String,
    city: j['city'] as String?,
    address: j['address'] as String?,
    station: j['station'] as String?,
    equipmentStatus: j['equipment_status'] as String? ?? 'not_collected',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'chain_name': chainName,
    'name': name,
    'city': city,
    'address': address,
    'station': station,
    'equipment_status': equipmentStatus,
  };
}

class GymEquipment {
  const GymEquipment({
    required this.id,
    required this.name,
    required this.category,
    this.quantity,
    this.manufacturer,
    this.model,
    this.exerciseIds = const {},
    this.compositeRuleIds = const {},
  });
  final String id, name, category;
  final int? quantity;
  final String? manufacturer, model;
  final Set<String> exerciseIds;
  final Set<String> compositeRuleIds;
  factory GymEquipment.fromJson(Map<String, dynamic> row) {
    final e = Map<String, dynamic>.from(row['equipment'] as Map);
    return GymEquipment(
      id: e['id'] as String,
      name: e['name'] as String,
      category: e['category'] as String,
      quantity: (row['quantity'] as num?)?.toInt(),
      manufacturer: e['manufacturer'] as String?,
      model: e['model'] as String?,
      exerciseIds: {
        for (final m in e['equipment_exercise_mapping'] as List? ?? const [])
          m['exercise_id'] as String,
      },
      compositeRuleIds: {
        for (final m in e['exercise_equipment_rule_items'] as List? ?? const [])
          m['rule_id'] as String,
      },
    );
  }
}

abstract class GymRepository {
  Future<List<GymStore>> search(String query, {int offset = 0});
  Future<List<GymStore>> registered();
  Future<void> register(GymStore store);
  Future<void> unregister(String storeId);
  Future<List<GymEquipment>> equipment(String storeId, {int offset = 0});
  Future<void> report({
    required String storeId,
    String? equipmentId,
    required String kind,
    String? equipmentName,
    required String comment,
  });
  bool get canReport;
  Future<Set<String>> exerciseIds(String storeId) async {
    final ids = <String>{};
    for (var offset = 0; ; offset += 50) {
      final page = await equipment(storeId, offset: offset);
      ids.addAll(page.expand((e) => e.exerciseIds));
      if (page.length < 50) return ids;
    }
  }
}

// Injectable boundary: tests never contact real accounts or production data.
class GymServices {
  static GymRepository? override;
  static GymRepository get repository => override ?? SupabaseGymRepository();
}

class SupabaseGymRepository extends GymRepository {
  SupabaseClient get _client {
    if (!SupabaseConfig.initialized) throw StateError('店舗情報を現在利用できません');
    return Supabase.instance.client;
  }

  String? get _userId =>
      SupabaseConfig.initialized ? _client.auth.currentUser?.id : null;
  @override
  bool get canReport => _userId != null;
  @override
  Future<List<GymStore>> search(String query, {int offset = 0}) async {
    final rows = await _client.rpc(
      'search_gym_stores',
      params: {'search_query': query.trim(), 'page_offset': offset},
    );
    return (rows as List)
        .map((j) => GymStore.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  @override
  Future<List<GymEquipment>> equipment(String storeId, {int offset = 0}) async {
    final rows = await _client
        .from('gym_store_equipment')
        .select(
          'quantity,equipment!inner(id,name,category,manufacturer,model,equipment_exercise_mapping(exercise_id),exercise_equipment_rule_items(rule_id))',
        )
        .eq('store_id', storeId)
        .eq('available', true)
        .order('equipment_id')
        .range(offset, offset + 49);
    return rows.map(GymEquipment.fromJson).toList();
  }

  @override
  Future<Set<String>> exerciseIds(String storeId) async {
    final rows = await _client.rpc(
      'gym_store_exercise_ids',
      params: {'target_store_id': storeId},
    );
    return {
      for (final row in rows as List)
        if (row is Map && row['exercise_id'] is String)
          row['exercise_id'] as String,
    };
  }

  // Guest registrations stay on this device. Signed-in registrations are RLS
  // protected and queried afresh; they are never exposed through profiles.
  static const _guestKey = 'guest_registered_gym_stores';
  Future<List<GymStore>> _guestStores() async {
    final p = await SharedPreferences.getInstance();
    final encoded = p.getString(_guestKey);
    if (encoded == null) return [];
    return (jsonDecode(encoded) as List)
        .map((j) => GymStore.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  Future<void> _saveGuest(List<GymStore> stores) async {
    final p = await SharedPreferences.getInstance();
    if (!await p.setString(
      _guestKey,
      jsonEncode(stores.map((s) => s.toJson()).toList()),
    )) {
      throw StateError('保存できませんでした');
    }
  }

  @override
  Future<List<GymStore>> registered() async {
    final user = _userId;
    if (user == null) return _guestStores();
    final rows = await _client
        .from('user_gym_stores')
        .select('gym_stores(*,gym_chains(name))')
        .eq('user_id', user)
        .order('created_at');
    return rows
        .map(
          (r) => GymStore.fromJson(
            Map<String, dynamic>.from(r['gym_stores'] as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> register(GymStore store) async {
    final user = _userId;
    if (user == null) {
      final stores = await _guestStores();
      if (!stores.any((s) => s.id == store.id)) {
        await _saveGuest([...stores, store]);
      }
      return;
    }
    await _client
        .from('user_gym_stores')
        .upsert(
          {'user_id': user, 'store_id': store.id},
          onConflict: 'user_id,store_id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> unregister(String storeId) async {
    final user = _userId;
    if (user == null) {
      await _saveGuest(
        (await _guestStores()).where((s) => s.id != storeId).toList(),
      );
      return;
    }
    await _client
        .from('user_gym_stores')
        .delete()
        .eq('user_id', user)
        .eq('store_id', storeId);
  }

  @override
  Future<void> report({
    required String storeId,
    String? equipmentId,
    required String kind,
    String? equipmentName,
    required String comment,
  }) async {
    if (!canReport) throw StateError('報告にはアカウントへのログインが必要です');
    await _client.from('gym_equipment_reports').insert({
      'store_id': storeId,
      'equipment_id': equipmentId,
      'kind': kind,
      'equipment_name': equipmentName,
      'comment': comment.trim(),
    });
  }
}
