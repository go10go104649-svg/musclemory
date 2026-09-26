import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../main.dart'
    show
        ExerciseRecordType,
        ExerciseRecordTypeUi,
        RecordedSet,
        SetHeader,
        WorkoutExerciseCardHeader,
        WorkoutExerciseCardShell,
        WorkoutPrimaryButton,
        WorkoutRecord,
        WorkoutSetRowLayout,
        formatDurationSeconds,
        formatWeight;
import 'trainer_inbox_repository.dart';
import 'trainer_menu_codec.dart';

class TrainerInboxPage extends StatefulWidget {
  const TrainerInboxPage({
    super.key,
    required this.onStart,
    this.repository,
    this.onReadChanged,
  });
  final Future<void> Function(WorkoutRecord) onStart;
  final TrainerInboxRepository? repository;
  final VoidCallback? onReadChanged;
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
      // A covered inbox (for example, while a workout is open) is not viewed.
      if (ModalRoute.of(context)?.isCurrent != true) {
        setState(() => loading = false);
        return;
      }
      try {
        await repo!.markRead(
          menuVersions: {
            for (final m in result[0]) m['id'] as String: m['version'] as int,
          },
          commentVersions: {
            for (final c in result[1]) c['id'] as String: c['version'] as int,
          },
        );
        if (mounted && current == generation && repo?.userId == uid) {
          widget.onReadChanged?.call();
        }
      } catch (_) {
        if (mounted && current == generation) {
          setState(
            () => error = tr(
              '既読状態を更新できませんでした。再読み込みしてください。',
              'Could not update read status. Please refresh.',
            ),
          );
        }
      }
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
                for (final m in menus) _menuCard(m),
                const SizedBox(height: 24),
                Text(
                  tr('トレーナーからのコメント', 'Trainer comments'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (comments.isEmpty)
                  Text(tr('コメントはまだありません', 'No comments yet')),
                for (final c in comments) _commentCard(c),
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

  String? _japanDate(Object? raw, {bool padHour = true}) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return null;
    final japan = parsed.toUtc().add(const Duration(hours: 9));
    final hour = padHour
        ? japan.hour.toString().padLeft(2, '0')
        : '${japan.hour}';
    final clock = '$hour:${japan.minute.toString().padLeft(2, '0')}';
    return tr(
      '${japan.month}月${japan.day}日 $clock',
      '${japan.month}/${japan.day} $clock JST',
    );
  }

  Widget _timestamp(String label, Object? value, {bool padHour = true}) {
    final date = _japanDate(value, padHour: padHour);
    if (date == null) return const SizedBox.shrink();
    return Text(
      '$label：$date',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _setValue(String value) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F5F0),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    ),
  );

  Widget _exerciseCard(Map menu, int index, Map item) {
    final sets = TrainerMenuCodec.setsForItem(item);
    final recordType = sets.isEmpty
        ? ExerciseRecordType.fromName(item['record_type'] as String?)
        : sets.first.recordType;
    return WorkoutExerciseCardShell(
      key: ValueKey('trainerMenuExercise:${menu['id']}:$index'),
      children: [
        WorkoutExerciseCardHeader(
          name: item['exercise_name'] as String,
          exerciseId: item['exercise_id'] as String?,
          bodyPart: item['body_part'] as String? ?? '',
          equipment: item['equipment'] as String? ?? '',
        ),
        const SizedBox(height: 10),
        if (recordType.usesSets) ...[
          SetHeader(
            recordType: recordType,
            showCompletionCheck: false,
            trailingWidth: 8,
          ),
          const SizedBox(height: 8),
        ],
        for (final (setIndex, set) in sets.indexed)
          WorkoutSetRowLayout(
            key: ValueKey('trainerMenuSet:${menu['id']}:$index:$setIndex'),
            number: setIndex + 1,
            values: _setValues(set, recordType),
          ),
      ],
    );
  }

  List<Widget> _setValues(RecordedSet set, ExerciseRecordType type) {
    if (!type.usesSets) return [_setValue(set.displaySummary)];
    return [
      if (type.hasWeightInput) _setValue(formatWeight(set.weight)),
      if (type.hasWeightInput || type == ExerciseRecordType.bodyweightReps)
        _setValue('${set.reps}'),
      if (type == ExerciseRecordType.timed)
        _setValue(formatDurationSeconds(set.durationSeconds)),
    ];
  }

  Widget _menuCard(Map<String, dynamic> menu) {
    final updated = menu['updated_at'] ?? menu['created_at'];
    return Card(
      key: ValueKey('trainerMenu:${menu['id']}'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              menu['name'] as String,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if ((menu['note'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(menu['note'] as String),
            ],
            const SizedBox(height: 8),
            _timestamp(tr('更新', 'Updated'), updated),
            if (menu['due_at'] != null)
              _timestamp(tr('期限', 'Due'), menu['due_at'], padHour: false),
            const SizedBox(height: 12),
            for (final (index, item) in (menu['items'] as List).indexed) ...[
              if (index > 0) const SizedBox(height: 10),
              _exerciseCard(menu, index, item as Map),
            ],
            const SizedBox(height: 14),
            if (menu['status'] == 'planned')
              WorkoutPrimaryButton(
                key: ValueKey('startTrainerMenu:${menu['id']}'),
                onPressed: starting ? null : () => start(menu),
                label: tr('このメニューでトレーニング開始', 'Start this workout'),
              )
            else
              Text(tr('実施済み', 'Completed')),
          ],
        ),
      ),
    );
  }

  Widget _commentCard(Map<String, dynamic> comment) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: WorkoutExerciseCardShell(
      key: ValueKey('trainerComment:${comment['id']}'),
      children: [
        Text(
          comment['body'] as String,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
        ),
        if (comment['menu_id'] != null) ...[
          const SizedBox(height: 8),
          Text(
            '${tr('対象メニュー', 'Menu')}：${_menuName(comment['menu_id'])}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 6),
        _timestamp(
          tr('更新', 'Updated'),
          comment['updated_at'] ?? comment['created_at'],
        ),
      ],
    ),
  );
}
