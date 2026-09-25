import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../main.dart' show WorkoutRecord;
import 'trainer_inbox_repository.dart';
import 'trainer_menu_codec.dart';

class TrainerInboxPage extends StatefulWidget {
  const TrainerInboxPage({super.key, required this.onStart, this.repository});
  final Future<void> Function(WorkoutRecord) onStart;
  final TrainerInboxRepository? repository;
  @override
  State<TrainerInboxPage> createState() => _TrainerInboxPageState();
}

class _TrainerInboxPageState extends State<TrainerInboxPage>
    with WidgetsBindingObserver {
  late final repo =
      widget.repository ??
      (SupabaseConfig.initialized
          ? TrainerInboxRepository(Supabase.instance.client)
          : null);
  StreamSubscription<void>? authSubscription;
  List<Map<String, dynamic>> menus = [], comments = [];
  String? error, loadedUser;
  bool loading = true, starting = false;
  int generation = 0;
  String tr(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    authSubscription = repo?.authChanges.listen((_) {
      if (repo?.userId != loadedUser) unawaited(reload());
    });
    unawaited(reload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !starting) unawaited(reload());
  }

  @override
  void dispose() {
    generation++;
    authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> all(
    Future<List<Map<String, dynamic>>> Function({int offset}) fetch,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 100) {
      final page = await fetch(offset: offset);
      rows.addAll(page);
      if (page.length < 100) return rows;
    }
  }

  Future<void> reload() async {
    final current = ++generation;
    final uid = repo?.userId;
    setState(() {
      loadedUser = uid;
      menus = [];
      comments = [];
      error = null;
      loading = uid != null;
    });
    if (uid == null) return;
    try {
      final result = await Future.wait([all(repo!.menus), all(repo!.comments)]);
      if (!mounted || current != generation || repo?.userId != uid) return;
      setState(() {
        menus = result[0];
        comments = result[1];
      });
    } catch (_) {
      if (mounted && current == generation) {
        setState(
          () => error = tr(
            '読み込めませんでした。再読み込みしてください。',
            'Could not load coaching. Please refresh.',
          ),
        );
      }
    }
    if (mounted && current == generation) setState(() => loading = false);
  }

  Future<void> start(Map<String, dynamic> displayed) async {
    if (starting || loadedUser == null) return;
    final uid = loadedUser;
    final current = generation;
    setState(() => starting = true);
    try {
      // Re-fetch at start: a canceled/reassigned menu must not start from stale UI.
      final latest = await repo!.menu(displayed['id'] as String);
      if (!mounted || current != generation || repo?.userId != uid) return;
      if (latest == null || latest['status'] != 'planned') {
        await reload();
        if (mounted) {
          setState(
            () => error = tr(
              'このメニューは現在開始できません。',
              'This menu is no longer available to start.',
            ),
          );
        }
        return;
      }
      if (latest['version'] != displayed['version']) {
        await reload();
        if (mounted) {
          setState(
            () => error = tr(
              'メニューが更新されました。最新内容を確認して開始してください。',
              'The menu changed. Review the latest version before starting.',
            ),
          );
        }
        return;
      }
      await widget.onStart(TrainerMenuCodec.workout(latest));
      if (mounted) await reload();
    } catch (_) {
      if (mounted && current == generation) {
        setState(
          () => error = tr(
            '最新メニューを確認できませんでした。接続を確認してください。',
            'Could not verify the latest menu. Check your connection.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('trainerInboxPage'),
    appBar: AppBar(
      title: Text(tr('トレーナーから', 'From your trainer')),
      actions: [
        IconButton(
          key: const Key('refreshTrainerInbox'),
          onPressed: starting ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loadedUser == null
        ? Center(
            child: Text(
              tr(
                'マイページの「アカウント」でログインしてください。',
                'Sign in from Account on your profile.',
              ),
            ),
          )
        : loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null)
                  Text(error!, key: const Key('trainerInboxError')),
                Text(
                  tr('トレーニングメニュー', 'Training menus'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (menus.isEmpty) Text(tr('メニューはまだありません', 'No menus yet')),
                for (final m in menus)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m['name'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if ((m['note'] as String? ?? '').isNotEmpty)
                            Text(m['note'] as String),
                          Text(
                            '${tr('更新', 'Updated')}: ${m['updated_at'] ?? m['created_at']}',
                          ),
                          if (m['due_at'] != null)
                            Text('${tr('期限', 'Due')}: ${m['due_at']}'),
                          Text(
                            m['schedule'] == 'repeat'
                                ? tr('繰り返し', 'Repeat')
                                : tr('単発', 'Single'),
                          ),
                          for (final item in m['items'] as List) ...[
                            Text(item['exercise_name'] as String),
                            for (final s in TrainerMenuCodec.setsForItem(
                              item as Map,
                            ))
                              Text(_setLabel(s.toJson())),
                          ],
                          if (m['status'] == 'planned')
                            FilledButton(
                              key: ValueKey('startTrainerMenu:${m['id']}'),
                              onPressed: starting ? null : () => start(m),
                              child: Text(
                                tr('このメニューでトレーニング開始', 'Start this workout'),
                              ),
                            )
                          else
                            Text(tr('実施済み', 'Completed')),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  tr('トレーナーからのコメント', 'Trainer comments'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (comments.isEmpty)
                  Text(tr('コメントはまだありません', 'No comments yet')),
                for (final c in comments)
                  Card(
                    child: ListTile(
                      title: Text(c['body'] as String),
                      subtitle: Text(
                        '${tr('更新', 'Updated')}: ${c['updated_at'] ?? c['created_at']}'
                        '${c['workout_date'] == null ? '' : '\n${c['workout_date']}'}'
                        '${c['menu_id'] == null ? '' : '\n${_menuName(c['menu_id'])}'}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
  );
  String _menuName(Object id) =>
      menus
          .where((m) => m['id'] == id)
          .map((m) => m['name'] as String)
          .firstOrNull ??
      tr('関連メニュー', 'Related menu');
  String _setLabel(Map<String, dynamic> s) {
    final parts = <String>[];
    if ((s['weight'] as num) > 0) parts.add('${s['weight']} kg');
    if ((s['reps'] as num) > 0) parts.add('${s['reps']} ${tr('回', 'reps')}');
    if ((s['durationSeconds'] as num) > 0) {
      parts.add('${s['durationSeconds']} s');
    }
    if ((s['distanceKm'] as num) > 0) parts.add('${s['distanceKm']} km');
    return parts.join(' × ');
  }
}
