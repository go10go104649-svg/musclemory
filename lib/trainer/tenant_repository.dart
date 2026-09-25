import 'trainer_menu_codec.dart';
import 'trainer_repository.dart';

/// Immutable scope: a route/request can never switch its tenant underneath it.
class TenantRepository extends TrainerRepository {
  TenantRepository(super.client, this.tenantId);
  final String tenantId;
  Future<Map<String, dynamic>> mutate(
    String action,
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
      'tenant_mutate',
      params: {'p_tenant': tenantId, 'p_action': action, 'p_data': data},
    ) as Map,
  );
  @override
  Future<List<Map<String, dynamic>>> clients() async {
    final staff = await members();
    final assigned = await assignments();
    final trainer = staff.any(
      (m) =>
          m['user_id'] == userId &&
          m['status'] == 'active' &&
          m['is_trainer'] == true,
    );
    return [
      for (final c
          in await client
              .from('tenant_clients')
              .select()
              .eq('tenant_id', tenantId)
              .eq('status', 'active')
              .order('client_name'))
        {
          ...c,
          'client_id': c['id'],
          'can_coach':
              trainer &&
              assigned.any(
                (a) => a['client_id'] == c['id'] && a['user_id'] == userId,
              ),
          'allow_recording':
              c['linked_user_id'] == null || c['allow_recording'] == true,
          'share_heatmap':
              c['linked_user_id'] == null || c['share_heatmap'] == true,
        },
    ];
  }

  @override
  Future<String> createInvite() => inviteClient();
  Future<String> inviteClient([String? clientId]) async =>
      (await mutate('client_invite', {'client_id': clientId}))['id'] as String;
  @override
  Future<List<Map<String, dynamic>>> workouts(
    String clientId, {
    int offset = 0,
  }) => fetchWorkouts(clientId, offset: offset);
  Future<List<Map<String, dynamic>>> fetchWorkouts(
    String clientId, {
    int offset = 0,
    bool heatmap = false,
  }) async => List<Map<String, dynamic>>.from(
    await client.rpc(
      'tenant_workouts',
      params: {
        'p_tenant': tenantId,
        'p_client': clientId,
        'p_offset': offset,
        'p_heatmap': heatmap,
      },
    ) as List,
  );
  Future<List<Map<String, dynamic>>> heatmapHistory(String clientId) async {
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await fetchWorkouts(clientId, offset: offset, heatmap: true);
      result.addAll(page.where((r) => r['canceled_at'] == null));
      if (page.length < 100) return result;
      offset += page.length;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> notes(String clientId) => client
      .from('tenant_comments')
      .select()
      .eq('tenant_id', tenantId)
      .eq('client_id', clientId)
      .order('created_at', ascending: false);
  @override
  Future<void> addNote(String clientId, String body) async {
    await saveComment(clientId, body);
  }

  Future<void> saveComment(
    String clientId,
    String body, {
    Map<String, dynamic>? existing,
    String? menuId,
    String? date,
    bool shared = true,
    bool delete = false,
  }) async {
    await client.rpc(
      'tenant_save_comment',
      params: {
        'p_tenant': tenantId,
        'p_client': clientId,
        'p_body': body.trim(),
        'p_id': existing?['id'],
        'p_version': existing?['version'],
        'p_menu': menuId,
        'p_date': date,
        'p_shared': shared,
        'p_delete': delete,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> menus({String? clientId}) async {
    var q = client
        .from('tenant_menus')
        .select('*, tenant_menu_exercises(*, tenant_menu_sets(*))')
        .eq('tenant_id', tenantId);
    if (clientId != null) q = q.eq('client_id', clientId);
    final rows = await q.order('created_at', ascending: false);
    return rows.map(TrainerMenuCodec.fromRow).toList();
  }

  @override
  Future<void> addMenu(
    String clientId,
    String name,
    String note,
    List<Map<String, dynamic>> items,
  ) => saveMenu(clientId, name, note, items);
  Future<void> saveMenu(
    String clientId,
    String name,
    String note,
    List<Map<String, dynamic>> items, {
    Map<String, dynamic>? existing,
    String schedule = 'single',
    DateTime? due,
  }) async {
    await mutate('menu', {
      'client_id': clientId,
      'name': name.trim(),
      'note': note.trim(),
      'items': items,
      'schedule': schedule,
      'due_at': due?.toUtc().toIso8601String(),
      if (existing != null) 'id': existing['id'],
      if (existing != null) 'version': existing['version'],
    });
  }

  Future<void> menuStatus(Map<String, dynamic> menu, String status) async {
    await mutate('menu_status', {
      'id': menu['id'],
      'client_id': menu['client_id'],
      'version': menu['version'],
      'status': status,
    });
  }

  @override
  Future<void> recordWorkout(
    String clientId,
    String requestId,
    DateTime date,
    List<Map<String, dynamic>> sets,
  ) async {
    await client.rpc(
      'tenant_record',
      params: {
        'p_tenant': tenantId,
        'p_client': clientId,
        'p_request': requestId,
        'p_date': date.toUtc().toIso8601String(),
        'p_sets': sets,
      },
    );
  }

  Future<void> cancelRecord(String clientId, String id, bool cancel) async {
    await client.rpc(
      'tenant_cancel_record',
      params: {
        'p_tenant': tenantId,
        'p_client': clientId,
        'p_record': id,
        'p_cancel': cancel,
      },
    );
  }

  Future<List<Map<String, dynamic>>> members() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('tenant_members', params: {'p_tenant': tenantId})
            as List,
      );
  Future<List<Map<String, dynamic>>> assignments() =>
      client.from('tenant_assignments').select().eq('tenant_id', tenantId);
  Future<Map<String, dynamic>> billing() async => Map<String, dynamic>.from(
    await client.rpc('tenant_billing_summary', params: {'p_tenant': tenantId})
        as Map,
  );
  Future<List<Map<String, dynamic>>> templates() => client
      .from('tenant_templates')
      .select()
      .eq('tenant_id', tenantId)
      .order('created_at');
}
