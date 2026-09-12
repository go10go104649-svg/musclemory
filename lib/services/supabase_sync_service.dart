import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class SupabaseSyncService {
  SupabaseSyncService._();

  static bool get isSignedIn =>
      SupabaseConfig.initialized &&
      Supabase.instance.client.auth.currentUser != null;

  static Future<int> syncWorkouts(List<Map<String, dynamic>> workouts) async {
    if (!isSignedIn || workouts.isEmpty) return 0;

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    final rows = workouts
        .map((workout) {
          final performedAt = workout['date'] as String;
          return {
            'user_id': userId,
            'client_id': performedAt,
            'performed_at': performedAt,
            'duration_seconds': workout['durationSeconds'] as int? ?? 0,
            'gym_name': workout['gymName'] as String?,
            'note': workout['note'] as String? ?? '',
            'sets': workout['sets'],
          };
        })
        .toList(growable: false);

    await client.from('workouts').upsert(rows, onConflict: 'user_id,client_id');
    return rows.length;
  }

  static Future<List<Map<String, dynamic>>> fetchWorkouts() async {
    if (!isSignedIn) return [];

    final rows = await Supabase.instance.client
        .from('workouts')
        .select(
          'client_id, performed_at, duration_seconds, gym_name, note, sets',
        )
        .order('performed_at', ascending: false);

    return rows
        .map(
          (row) => <String, dynamic>{
            'date': row['performed_at'] as String,
            'durationSeconds': row['duration_seconds'] as int? ?? 0,
            'gymName': row['gym_name'] as String?,
            'note': row['note'] as String? ?? '',
            'sets': row['sets'] as List<dynamic>,
          },
        )
        .toList(growable: false);
  }

  static Future<void> deleteWorkout(String clientId) async {
    if (!isSignedIn) return;
    await Supabase.instance.client
        .from('workouts')
        .delete()
        .eq('client_id', clientId);
  }
}
