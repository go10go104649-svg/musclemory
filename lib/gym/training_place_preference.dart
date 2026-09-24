import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'gym_repository.dart';

class TrainingPlace {
  const TrainingPlace.home() : store = null;
  const TrainingPlace.store(this.store);
  final GymStore? store;
  String get name => store?.displayName ?? '自宅';
  String? get storeId => store?.id;
}

/// Account-local default, separate from legacy name-only preferences. Old names
/// and custom gyms remain intact; a name is never guessed into a store identity.
class TrainingPlacePreference {
  static String get _key {
    final user = SupabaseConfig.initialized
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    return 'training_place_v1_${user ?? 'guest'}';
  }

  static Future<TrainingPlace> load() async {
    final key = _key;
    final p = await SharedPreferences.getInstance();
    final value = p.getString(key);
    if (value == null) return const TrainingPlace.home();
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final store = json['store'];
      if (store is Map<String, dynamic>) {
        final parsed = GymStore.fromJson(store);
        if (parsed.id.isNotEmpty) return TrainingPlace.store(parsed);
      }
    } catch (_) {
      // A corrupt preference must not prevent recording a workout.
    }
    return const TrainingPlace.home();
  }

  static Future<void> save(TrainingPlace place) async {
    final key = _key;
    final p = await SharedPreferences.getInstance();
    if (!await p.setString(key, jsonEncode({'store': place.store?.toJson()}))) {
      throw StateError('利用場所を保存できませんでした');
    }
  }

  static Future<TrainingPlace> reconcile(List<GymStore> registered) async {
    final current = await load();
    if (current.storeId == null) return current;
    for (final store in registered) {
      if (store.id == current.storeId) return TrainingPlace.store(store);
    }
    const home = TrainingPlace.home();
    await save(home);
    return home;
  }
}
