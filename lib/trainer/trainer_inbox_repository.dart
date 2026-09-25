import 'package:supabase_flutter/supabase_flutter.dart';

import 'trainer_menu_codec.dart';

/// Client view of the very same rows edited in TRAINER. RLS remains authoritative.
class TrainerInboxRepository {
  TrainerInboxRepository(this.client);
  final SupabaseClient client;
  String? get userId => client.auth.currentUser?.id;
  Stream<void> get authChanges => client.auth.onAuthStateChange.map((_) {});
  static const _menuSelect =
      '*,tenant_clients!inner(linked_user_id,status),tenant_menu_exercises(*,tenant_menu_sets(*))';

  Future<List<Map<String, dynamic>>> menus({int offset = 0}) async {
    final uid = userId;
    if (uid == null) return [];
    final rows = await client
        .from('tenant_menus')
        .select(_menuSelect)
        .eq('tenant_clients.linked_user_id', uid)
        .eq('tenant_clients.status', 'active')
        .neq('status', 'canceled')
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + 99);
    return rows.map(TrainerMenuCodec.fromRow).toList();
  }

  Future<Map<String, dynamic>?> menu(String id) async {
    final uid = userId;
    if (uid == null) return null;
    final row = await client
        .from('tenant_menus')
        .select(_menuSelect)
        .eq('id', id)
        .eq('tenant_clients.linked_user_id', uid)
        .eq('tenant_clients.status', 'active')
        .neq('status', 'canceled')
        .maybeSingle();
    return row == null ? null : TrainerMenuCodec.fromRow(row);
  }

  Future<List<Map<String, dynamic>>> comments({int offset = 0}) async {
    final uid = userId;
    if (uid == null) return [];
    return client
        .from('tenant_comments')
        .select('*,tenant_clients!inner(linked_user_id,status)')
        .eq('tenant_clients.linked_user_id', uid)
        .eq('tenant_clients.status', 'active')
        .eq('shared_with_client', true)
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + 99);
  }
}
