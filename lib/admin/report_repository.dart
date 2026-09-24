import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../exercise_form_catalog.dart';

const reportStatuses = {
  'pending': '未確認',
  'reviewing': '確認中',
  'applied': '反映済み',
  'rejected': '却下',
};
const reportKinds = {
  'missing_exercise': 'できるのに表示されていない',
  'incorrect_exercise': '表示されているができない',
  'not_present': '設置されていない',
  'removed': '撤去された',
  'added': '新しく追加された',
  'wrong_name': '名称が違う',
  'other': 'その他',
};

class AdminReport {
  AdminReport(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get type => data['report_type'] as String;
  String get status => data['status'] as String;
  String get storeId => data['store_id'] as String;
  String get storeName => data['store_name'] as String;
  String get targetName => type == 'exercise'
      ? ExerciseFormCatalog.canonicalDefinition(
              data['target_id'] as String? ?? '',
            )?.exerciseName ??
            data['target_id'] as String? ??
            '対象指定なし'
      : data['equipment_name'] as String? ??
            data['entered_name'] as String? ??
            '対象指定なし';
  String get kindLabel => reportKinds[data['report_kind']] ?? 'その他';
  String get note => data['admin_note'] as String? ?? '';
  String get dateLabel {
    final d = DateTime.parse(data['created_at'] as String).toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${pad(d.month)}/${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';
  }
}

class ReportBatch {
  const ReportBatch(this.rows, this.counts);
  final List<AdminReport> rows;
  final Map<String, int> counts;
}

abstract class ReportRepository {
  Future<bool> isAdmin();
  Stream<void> get authChanges;
  Future<ReportBatch> list(
    String type,
    String? status,
    String query,
    int offset,
  );
  Future<void> update(AdminReport report, String status, String note);
}

class ReportServices {
  static ReportRepository? override;
  static ReportRepository get repository =>
      override ?? SupabaseReportRepository();
}

class SupabaseReportRepository implements ReportRepository {
  SupabaseClient get client => Supabase.instance.client;
  @override
  Stream<void> get authChanges => SupabaseConfig.initialized
      ? client.auth.onAuthStateChange.map((_) {})
      : const Stream.empty();
  @override
  Future<bool> isAdmin() async {
    if (!SupabaseConfig.initialized || client.auth.currentUser == null) {
      return false;
    }
    return await client.rpc('is_report_admin') == true;
  }

  @override
  Future<ReportBatch> list(
    String type,
    String? status,
    String query,
    int offset,
  ) async {
    final q = query.trim().toLowerCase();
    final ids = ExerciseFormCatalog.entries
        .where(
          (e) => '${e.exerciseName} ${e.englishName} ${e.aliases.join(' ')}'
              .toLowerCase()
              .contains(q),
        )
        .map((e) => e.exerciseId)
        .toList();
    final result = Map<String, dynamic>.from(
      await client.rpc(
        'list_admin_reports',
        params: {
          'report_type_filter': type,
          'status_filter': status,
          'search_text': query.trim(),
          'exercise_ids': q.isEmpty ? <String>[] : ids,
          'page_offset': offset,
        },
      ) as Map,
    );
    return ReportBatch(
      (result['rows'] as List)
          .map((r) => AdminReport(Map<String, dynamic>.from(r as Map)))
          .toList(),
      Map<String, int>.from(result['counts'] as Map? ?? {}),
    );
  }

  @override
  Future<void> update(AdminReport report, String status, String note) async {
    await client.rpc(
      'update_admin_report',
      params: {
        'report_type_value': report.type,
        'report_id': report.id,
        'expected_status': report.status,
        'new_status': status,
        'note': note.trim(),
      },
    );
  }
}
