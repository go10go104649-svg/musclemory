import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'services/supabase_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RestTimerPreference.load();
  await CustomExercisePreference.load();
  await SupabaseConfig.initialize();
  runApp(const MuscleMemoryApp());
}

class RestTimerPreference {
  RestTimerPreference._();

  static const _enabledKey = 'rest_timer_enabled';
  static const _secondsKey = 'rest_timer_seconds';
  static bool enabled = false;
  static int seconds = 90;

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    enabled = preferences.getBool(_enabledKey) ?? false;
    seconds = preferences.getInt(_secondsKey) ?? 90;
  }

  static Future<void> setEnabled(bool value) async {
    enabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
  }

  static Future<void> setSeconds(int value) async {
    seconds = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_secondsKey, value);
  }
}

class MuscleMemoryApp extends StatelessWidget {
  const MuscleMemoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MuscleMemory',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja', 'JP'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ja', 'JP')],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC7F36B),
          primary: const Color(0xFF101820),
          secondary: const Color(0xFFC7F36B),
          surface: const Color(0xFFF4F5F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F5F0),
        fontFamily: '.SF Pro Display',
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _storageKey = 'workout_history';
  static const _gymStorageKey = 'selected_gym';
  static const _weeklyTargetStorageKey = 'weekly_target';
  int _selectedIndex = 0;
  List<WorkoutRecord> _history = [];
  String? _selectedGym;
  int _weeklyTarget = 3;
  List<SavedWorkoutTemplate> _workoutTemplates = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final workoutTemplates = await WorkoutTemplatePreference.load();
    final encoded = preferences.getString(_storageKey);
    if (!mounted) return;
    final decodedItems = encoded == null
        ? <WorkoutRecord>[]
        : (jsonDecode(encoded) as List<dynamic>)
              .map(
                (item) => WorkoutRecord.fromJson(item as Map<String, dynamic>),
              )
              .toList();
    final items = sortWorkoutsNewestFirst(decodedItems);
    setState(() {
      _history = items;
      _selectedGym = preferences.getString(_gymStorageKey);
      _weeklyTarget = preferences.getInt(_weeklyTargetStorageKey) ?? 3;
      _workoutTemplates = workoutTemplates;
    });
  }

  Future<void> _saveWorkoutTemplate(SavedWorkoutTemplate template) async {
    final updated = [
      template,
      ..._workoutTemplates.where((item) => item.name != template.name),
    ];
    setState(() => _workoutTemplates = updated);
    await WorkoutTemplatePreference.save(updated);
  }

  Future<void> _deleteWorkoutTemplate(SavedWorkoutTemplate template) async {
    final updated = _workoutTemplates
        .where((item) => item.name != template.name)
        .toList();
    setState(() => _workoutTemplates = updated);
    await WorkoutTemplatePreference.save(updated);
  }

  Future<void> _saveWorkout(WorkoutRecord workout) async {
    final updated = sortWorkoutsNewestFirst([workout, ..._history]);
    setState(() => _history = updated);
    await _persistHistory(updated);
    await _syncHistory(updated);
  }

  Future<void> _persistHistory(List<WorkoutRecord> history) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(history.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _replaceWorkout(
    DateTime originalDate,
    WorkoutRecord workout,
  ) async {
    final updated = sortWorkoutsNewestFirst(
      _history.map((item) => item.date == originalDate ? workout : item),
    );
    setState(() => _history = updated);
    await _persistHistory(updated);
    await _syncHistory(updated);
  }

  Future<bool> _deleteWorkout(WorkoutRecord workout) async {
    try {
      await SupabaseSyncService.deleteWorkout(workout.date.toIso8601String());
    } catch (error) {
      debugPrint('Supabase delete failed: $error');
      return false;
    }
    final updated = _history
        .where((item) => item.date != workout.date)
        .toList();
    setState(() => _history = updated);
    await _persistHistory(updated);
    return true;
  }

  Future<int> _importWorkouts(List<WorkoutRecord> imported) async {
    final merged = <String, WorkoutRecord>{
      for (final workout in _history) workout.date.toIso8601String(): workout,
      for (final workout in imported) workout.date.toIso8601String(): workout,
    };
    final updated = sortWorkoutsNewestFirst(merged.values);
    final addedCount = updated.length - _history.length;
    setState(() => _history = updated);
    await _persistHistory(updated);
    await _syncHistory(updated);
    return addedCount;
  }

  Future<int> _importBackup(MuscleMemoryBackup backup) async {
    final addedCount = await _importWorkouts(backup.workouts);
    if (backup.selectedGym != null) await _saveGym(backup.selectedGym!);
    if (backup.weeklyTarget != null) {
      await _saveWeeklyTarget(backup.weeklyTarget!.clamp(2, 7).toInt());
    }
    if (backup.restTimerEnabled != null) {
      await _saveRestTimerEnabled(backup.restTimerEnabled!);
    }
    if (backup.restTimerSeconds != null) {
      await _saveRestTimerSeconds(backup.restTimerSeconds!);
    }

    final templates = <String, SavedWorkoutTemplate>{
      for (final item in _workoutTemplates) item.name: item,
      for (final item in backup.workoutTemplates) item.name: item,
    }.values.toList();
    setState(() => _workoutTemplates = templates);
    await WorkoutTemplatePreference.save(templates);

    final customExercises = <String, ExerciseTemplate>{
      for (final item in CustomExercisePreference.exercises) item.name: item,
      for (final item in backup.customExercises) item.name: item,
    }.values.toList();
    await CustomExercisePreference.replaceAll(customExercises);
    return addedCount;
  }

  Future<int> _syncHistory([List<WorkoutRecord>? history]) async {
    try {
      final localHistory = history ?? _history;
      await SupabaseSyncService.syncWorkouts(
        localHistory.map((item) => item.toJson()).toList(),
      );
      final cloudItems = await SupabaseSyncService.fetchWorkouts();
      if (!SupabaseSyncService.isSignedIn) return 0;

      final merged = <String, WorkoutRecord>{
        for (final workout in localHistory)
          workout.date.toIso8601String(): workout,
      };
      for (final item in cloudItems) {
        final workout = WorkoutRecord.fromJson(item);
        merged[workout.date.toIso8601String()] = workout;
      }
      final updated = sortWorkoutsNewestFirst(merged.values);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _storageKey,
        jsonEncode(updated.map((item) => item.toJson()).toList()),
      );
      if (mounted) setState(() => _history = updated);
      return updated.length;
    } catch (error) {
      debugPrint('Supabase sync failed: $error');
      return 0;
    }
  }

  Future<void> _saveGym(String gym) async {
    setState(() => _selectedGym = gym);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_gymStorageKey, gym);
  }

  Future<void> _saveWeeklyTarget(int target) async {
    setState(() => _weeklyTarget = target);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_weeklyTargetStorageKey, target);
  }

  Future<void> _saveRestTimerEnabled(bool enabled) async {
    await RestTimerPreference.setEnabled(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _saveRestTimerSeconds(int seconds) async {
    await RestTimerPreference.setSeconds(seconds);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        history: _history,
        selectedGym: _selectedGym,
        onGymChanged: _saveGym,
        weeklyTarget: _weeklyTarget,
        onWorkoutCompleted: _saveWorkout,
        workoutTemplates: _workoutTemplates,
        onTemplateSaved: _saveWorkoutTemplate,
        onTemplateDeleted: _deleteWorkoutTemplate,
      ),
      MonthlyHistoryPage(
        history: _history,
        selectedGym: _selectedGym,
        onWorkoutCompleted: _saveWorkout,
        onWorkoutUpdated: _replaceWorkout,
        onWorkoutDeleted: _deleteWorkout,
      ),
      BodyMapPage(history: _history),
      ProfilePage(
        selectedGym: _selectedGym,
        onGymChanged: _saveGym,
        history: _history,
        onSyncRequested: _syncHistory,
        workoutTemplates: _workoutTemplates,
        onBackupImported: _importBackup,
        weeklyTarget: _weeklyTarget,
        onWeeklyTargetChanged: _saveWeeklyTarget,
        restTimerEnabled: RestTimerPreference.enabled,
        restTimerSeconds: RestTimerPreference.seconds,
        onRestTimerEnabledChanged: _saveRestTimerEnabled,
        onRestTimerSecondsChanged: _saveRestTimerSeconds,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFC7F36B),
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: '履歴',
          ),
          NavigationDestination(
            icon: Icon(Icons.accessibility_new_outlined),
            selectedIcon: Icon(Icons.accessibility_new_rounded),
            label: '部位',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'マイページ',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.history,
    required this.selectedGym,
    required this.onGymChanged,
    required this.weeklyTarget,
    required this.onWorkoutCompleted,
    required this.workoutTemplates,
    required this.onTemplateSaved,
    required this.onTemplateDeleted,
  });

  final List<WorkoutRecord> history;
  final String? selectedGym;
  final ValueChanged<String> onGymChanged;
  final int weeklyTarget;
  final ValueChanged<WorkoutRecord> onWorkoutCompleted;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final Future<void> Function(SavedWorkoutTemplate) onTemplateSaved;
  final Future<void> Function(SavedWorkoutTemplate) onTemplateDeleted;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          const HomeHeader(),
          const SizedBox(height: 24),
          StartWorkoutCard(
            gymName: selectedGym,
            onSelectGym: () async {
              final selected = await showGymPicker(context, selectedGym);
              if (selected != null) onGymChanged(selected);
            },
            onPressed: () async {
              await _openWorkout(context);
            },
          ),
          if (workoutTemplates.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionTitle(title: 'マイメニュー', action: '保存したメニュー'),
            const SizedBox(height: 12),
            SavedMenusCard(
              templates: workoutTemplates,
              onSelected: (template) => _openWorkout(
                context,
                initialWorkout: template.toWorkoutRecord(),
              ),
              onDeleted: onTemplateDeleted,
            ),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionTitle(title: 'クイックスタート', action: '最近のメニュー'),
            const SizedBox(height: 12),
            RecentMenusCard(
              history: history,
              onSelected: (workout) =>
                  _openWorkout(context, initialWorkout: workout),
              onSave: (workout) => _saveAsTemplate(context, workout),
            ),
          ],
          const SizedBox(height: 24),
          const SectionTitle(title: '今週の記録', action: '詳細'),
          const SizedBox(height: 12),
          WeeklySummary(history: history),
          const SizedBox(height: 12),
          WeeklyGoalCard(history: history, target: weeklyTarget),
          const SizedBox(height: 24),
          const SectionTitle(title: '前回のトレーニング', action: '履歴'),
          const SizedBox(height: 12),
          LastWorkoutCard(workout: history.isEmpty ? null : history.first),
          const SizedBox(height: 24),
          const SectionTitle(title: '最近鍛えた部位', action: '7日間'),
          const SizedBox(height: 12),
          MuscleChips(history: history),
        ],
      ),
    );
  }

  Future<void> _saveAsTemplate(
    BuildContext context,
    WorkoutRecord workout,
  ) async {
    final defaultName = workout.bodyParts.join('・');
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SaveWorkoutTemplateDialog(initialName: defaultName),
    );
    if (name == null || !context.mounted) return;
    await onTemplateSaved(SavedWorkoutTemplate(name: name, sets: workout.sets));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('「$name」を保存しました')));
    }
  }

  Future<void> _openWorkout(
    BuildContext context, {
    WorkoutRecord? initialWorkout,
  }) async {
    final workout = await Navigator.of(context).push<WorkoutRecord>(
      MaterialPageRoute(
        builder: (_) => WorkoutPage(
          history: history,
          initialWorkout: initialWorkout,
          gymName: selectedGym,
        ),
      ),
    );
    if (workout != null) onWorkoutCompleted(workout);
  }
}

class _SaveWorkoutTemplateDialog extends StatefulWidget {
  const _SaveWorkoutTemplateDialog({required this.initialName});

  final String initialName;

  @override
  State<_SaveWorkoutTemplateDialog> createState() =>
      _SaveWorkoutTemplateDialogState();
}

class _SaveWorkoutTemplateDialogState
    extends State<_SaveWorkoutTemplateDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('マイメニューに保存'),
      content: TextField(
        key: const Key('templateNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(
          labelText: 'メニュー名',
          hintText: '例：胸の日',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(context, value);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class RecentMenusCard extends StatelessWidget {
  const RecentMenusCard({
    super.key,
    required this.history,
    required this.onSelected,
    required this.onSave,
  });

  final List<WorkoutRecord> history;
  final ValueChanged<WorkoutRecord> onSelected;
  final ValueChanged<WorkoutRecord> onSave;

  List<WorkoutRecord> get _recentMenus {
    final signatures = <String>{};
    final menus = <WorkoutRecord>[];
    for (final workout in history) {
      final signature = workout.exerciseNames.join('|');
      if (signatures.add(signature)) menus.add(workout);
      if (menus.length == 3) break;
    }
    return menus;
  }

  @override
  Widget build(BuildContext context) {
    final menus = _recentMenus;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: List.generate(menus.length, (index) {
          final workout = menus[index];
          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFC7F36B),
                  child: Icon(Icons.play_arrow_rounded),
                ),
                title: Text(
                  workout.exerciseNames.join('・'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${workout.exerciseNames.length}種目・${workout.sets.length}セット',
                ),
                trailing: IconButton(
                  tooltip: 'マイメニューに保存',
                  onPressed: () => onSave(workout),
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                onTap: () => onSelected(workout),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class SavedMenusCard extends StatelessWidget {
  const SavedMenusCard({
    super.key,
    required this.templates,
    required this.onSelected,
    required this.onDeleted,
  });

  final List<SavedWorkoutTemplate> templates;
  final ValueChanged<SavedWorkoutTemplate> onSelected;
  final Future<void> Function(SavedWorkoutTemplate) onDeleted;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: List.generate(templates.length, (index) {
          final template = templates[index];
          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              ListTile(
                key: Key('savedMenu$index'),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF101820),
                  foregroundColor: Color(0xFFC7F36B),
                  child: Icon(Icons.fitness_center_rounded),
                ),
                title: Text(
                  template.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${template.exerciseNames.length}種目・${template.sets.length}セット',
                ),
                onTap: () => onSelected(template),
                trailing: IconButton(
                  tooltip: '${template.name}を削除',
                  onPressed: () async {
                    await onDeleted(template);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('「${template.name}」を削除しました')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MUSCLE MEMORY',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.1,
                  color: const Color(0xFF6C746D),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '今日も積み上げよう',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF101820),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }
}

class StartWorkoutCard extends StatelessWidget {
  const StartWorkoutCard({
    super.key,
    required this.gymName,
    required this.onSelectGym,
    required this.onPressed,
  });

  final String? gymName;
  final VoidCallback onSelectGym;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: onSelectGym,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 15,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        gymName ?? '店舗を選択',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.fitness_center_rounded,
                color: Color(0xFFC7F36B),
                size: 30,
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            '次の1セットが、\n成長の記録になる。',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              key: const Key('startWorkoutButton'),
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC7F36B),
                foregroundColor: const Color(0xFF101820),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                'トレーニングを始める',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.action});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF101820),
            ),
          ),
        ),
        Text(
          action,
          style: const TextStyle(
            color: Color(0xFF6C746D),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class WeeklySummary extends StatelessWidget {
  const WeeklySummary({super.key, required this.history});

  final List<WorkoutRecord> history;

  @override
  Widget build(BuildContext context) {
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    final weekStart = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );
    final weekly = history.where((item) => !item.date.isBefore(weekStart));
    final workoutCount = weekly.length;
    final volume = weekly.fold<double>(
      0,
      (total, workout) => total + workout.volume,
    );
    final personalBests = countPersonalBests(history, weekStart);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            StatItem(value: '$workoutCount', unit: '回', label: 'ワークアウト'),
            Container(width: 1, height: 46, color: const Color(0xFFE4E7E1)),
            StatItem(
              value: (volume / 1000).toStringAsFixed(1),
              unit: 't',
              label: 'ボリューム',
            ),
            Container(width: 1, height: 46, color: const Color(0xFFE4E7E1)),
            StatItem(value: '$personalBests', unit: '個', label: '自己ベスト'),
          ],
        ),
      ),
    );
  }
}

class WeeklyGoalCard extends StatelessWidget {
  const WeeklyGoalCard({
    super.key,
    required this.history,
    required this.target,
  });

  final List<WorkoutRecord> history;
  final int target;

  DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  int get _streak {
    if (history.isEmpty) return 0;
    final now = DateTime.now();
    var cursor = _weekStart(now);
    final currentHasWorkout = history.any(
      (workout) => _weekStart(workout.date) == cursor,
    );
    if (!currentHasWorkout) cursor = cursor.subtract(const Duration(days: 7));

    var streak = 0;
    while (history.any((workout) => _weekStart(workout.date) == cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final currentWeek = _weekStart(DateTime.now());
    final count = history
        .where((workout) => !workout.date.isBefore(currentWeek))
        .length;
    final progress = (count / target).clamp(0.0, 1.0);
    final remaining = target - count;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F4D1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  remaining <= 0 ? '今週の目標を達成！' : 'あと$remaining回で今週の目標',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '$_streak週継続',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white,
              color: const Color(0xFF83AD30),
            ),
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$count / $target 回',
              style: const TextStyle(fontSize: 11, color: Color(0xFF59634F)),
            ),
          ),
        ],
      ),
    );
  }
}

class StatItem extends StatelessWidget {
  const StatItem({
    super.key,
    required this.value,
    required this.unit,
    required this.label,
  });

  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Color(0xFF101820)),
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF777F78)),
          ),
        ],
      ),
    );
  }
}

class LastWorkoutCard extends StatelessWidget {
  const LastWorkoutCard({super.key, required this.workout});

  final WorkoutRecord? workout;

  @override
  Widget build(BuildContext context) {
    if (workout == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: const Padding(
          padding: EdgeInsets.all(22),
          child: Row(
            children: [
              Icon(Icons.add_chart_rounded, color: Color(0xFF6C746D)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '最初のトレーニングを記録してみよう',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final item = workout!;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                DateBadge(date: item.date),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.bodyParts.join('・'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.exerciseNames.length}種目・${item.sets.length}セット${item.durationLabel.isEmpty ? '' : '・${item.durationLabel}'}',
                        style: const TextStyle(
                          color: Color(0xFF777F78),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF777F78),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: const Color(0xFFE9EBE6)),
            const SizedBox(height: 14),
            ExerciseLine(
              name: item.bestSet.exerciseName,
              detail:
                  '${formatWeight(item.bestSet.weight)} kg × ${item.bestSet.reps}  ベストセット',
            ),
          ],
        ),
      ),
    );
  }
}

class DateBadge extends StatelessWidget {
  const DateBadge({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2EA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.month}月',
            style: const TextStyle(fontSize: 10, color: Color(0xFF6C746D)),
          ),
          Text(
            date.day.toString().padLeft(2, '0'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class ExerciseLine extends StatelessWidget {
  const ExerciseLine({super.key, required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFC7F36B).withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.fitness_center_rounded, size: 18),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Color(0xFF777F78)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MuscleChips extends StatelessWidget {
  const MuscleChips({super.key, required this.history});

  final List<WorkoutRecord> history;

  @override
  Widget build(BuildContext context) {
    final counts = _bodyPartCounts(history);
    final items = ['胸', '背中', '脚', '肩', '腕', '腹'].map((part) {
      final count = counts[part] ?? 0;
      final label = count >= 5 ? '高' : (count >= 2 ? '中' : '低');
      final color = count >= 5
          ? const Color(0xFF101820)
          : (count >= 2 ? const Color(0xFF65735F) : const Color(0xFFBBC2B8));
      return (part, label, color);
    }).toList();
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: item.$3,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                item.$1,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 7),
              Text(
                item.$2,
                style: const TextStyle(fontSize: 11, color: Color(0xFF777F78)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

Map<String, int> _bodyPartCounts(List<WorkoutRecord> history) {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  final counts = <String, int>{};
  for (final workout in history.where((item) => item.date.isAfter(cutoff))) {
    for (final set in workout.sets) {
      counts.update(set.bodyPart, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

int countPersonalBests(List<WorkoutRecord> history, DateTime since) {
  final bestWeights = <String, double>{};
  var count = 0;
  final chronological = [...history]..sort((a, b) => a.date.compareTo(b.date));
  for (final workout in chronological) {
    final workoutBest = <String, double>{};
    for (final set in workout.sets) {
      workoutBest.update(
        set.exerciseName,
        (value) => set.weight > value ? set.weight : value,
        ifAbsent: () => set.weight,
      );
    }
    for (final entry in workoutBest.entries) {
      final previous = bestWeights[entry.key] ?? 0.0;
      if (entry.value > previous) {
        bestWeights[entry.key] = entry.value;
        if (!workout.date.isBefore(since)) count++;
      }
    }
  }
  return count;
}

class BodyMapPage extends StatelessWidget {
  const BodyMapPage({super.key, required this.history});

  final List<WorkoutRecord> history;

  @override
  Widget build(BuildContext context) {
    final counts = _bodyPartCounts(history);
    final maximum = counts.values.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    const parts = ['胸', '背中', '脚', '肩', '腕', '腹'];
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: [
          const Text(
            '部位ヒートマップ',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text('直近7日間の完了セット', style: TextStyle(color: Color(0xFF6C746D))),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF101820),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.accessibility_new_rounded,
                  size: 92,
                  color: Color(0xFFC7F36B),
                ),
                SizedBox(height: 8),
                Text('鍛えた部位ほど濃く表示', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...parts.map((part) {
            final value = counts[part] ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        part,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: value / maximum,
                          minHeight: 10,
                          backgroundColor: const Color(0xFFE8EBE5),
                          color: const Color(0xFFC7F36B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 54,
                      child: Text(
                        '$valueセット',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class MonthlyHistoryPage extends StatefulWidget {
  const MonthlyHistoryPage({
    super.key,
    required this.history,
    required this.selectedGym,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
  });

  final List<WorkoutRecord> history;
  final String? selectedGym;
  final ValueChanged<WorkoutRecord> onWorkoutCompleted;
  final Future<void> Function(DateTime, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  State<MonthlyHistoryPage> createState() => _MonthlyHistoryPageState();
}

class _MonthlyHistoryPageState extends State<MonthlyHistoryPage> {
  final ScrollController _scrollController = ScrollController();
  late DateTime _visibleMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _moveMonth(int amount) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + amount,
      );
      _selectedDay = null;
    });
  }

  void _selectDay(DateTime date, bool selected) {
    setState(() => _selectedDay = selected ? null : date);
    if (selected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent.clamp(
        0.0,
        460.0,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monthWorkouts = widget.history
        .where(
          (workout) =>
              workout.date.year == _visibleMonth.year &&
              workout.date.month == _visibleMonth.month,
        )
        .toList();
    final shownWorkouts = _selectedDay == null
        ? monthWorkouts
        : monthWorkouts
              .where((workout) => _sameDay(workout.date, _selectedDay!))
              .toList();
    final volume = monthWorkouts.fold<double>(
      0,
      (total, workout) => total + workout.volume,
    );
    final setCount = monthWorkouts.fold<int>(
      0,
      (total, workout) => total + workout.sets.length,
    );
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leadingEmptyDays = firstDay.weekday - 1;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final today = DateTime.now();
    final isCurrentMonth =
        _visibleMonth.year == today.year && _visibleMonth.month == today.month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('月間カレンダー'),
        actions: [
          if (widget.history.isNotEmpty)
            IconButton(
              tooltip: '履歴を検索',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HistorySearchPage(
                    history: widget.history,
                    selectedGym: widget.selectedGym,
                    onWorkoutCompleted: widget.onWorkoutCompleted,
                    onWorkoutUpdated: widget.onWorkoutUpdated,
                    onWorkoutDeleted: widget.onWorkoutDeleted,
                  ),
                ),
              ),
              icon: const Icon(Icons.search_rounded),
            ),
          if (widget.history.isNotEmpty)
            IconButton(
              tooltip: '種目ごとの成長を見る',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExerciseProgressPage(history: widget.history),
                ),
              ),
              icon: const Icon(Icons.insights_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '前の月',
                onPressed: () => _moveMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${_visibleMonth.year}年 ${_visibleMonth.month}月',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: '次の月',
                onPressed: isCurrentMonth ? null : () => _moveMonth(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  StatItem(
                    value: '${monthWorkouts.length}',
                    unit: '回',
                    label: 'トレーニング',
                  ),
                  Container(
                    width: 1,
                    height: 46,
                    color: const Color(0xFFE4E7E1),
                  ),
                  StatItem(value: '$setCount', unit: '組', label: 'セット'),
                  Container(
                    width: 1,
                    height: 46,
                    color: const Color(0xFFE4E7E1),
                  ),
                  StatItem(
                    value: (volume / 1000).toStringAsFixed(1),
                    unit: 't',
                    label: 'ボリューム',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            key: const Key('monthlyCalendar'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final day in ['月', '火', '水', '木', '金', '土', '日'])
                        Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777F78),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisExtent: 44,
                        ),
                    itemCount: leadingEmptyDays + daysInMonth,
                    itemBuilder: (context, index) {
                      if (index < leadingEmptyDays) return const SizedBox();
                      final day = index - leadingEmptyDays + 1;
                      final date = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month,
                        day,
                      );
                      final hasWorkout = monthWorkouts.any(
                        (workout) => _sameDay(workout.date, date),
                      );
                      final selected =
                          _selectedDay != null && _sameDay(_selectedDay!, date);
                      return InkWell(
                        key: Key('calendarDay$day'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _selectDay(date, selected),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF101820)
                                : hasWorkout
                                ? const Color(0xFFC7F36B)
                                      .withValues(alpha: 0.42)
                                : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontWeight: hasWorkout
                                      ? FontWeight.w900
                                      : FontWeight.w500,
                                  color: selected ? Colors.white : null,
                                ),
                              ),
                              if (hasWorkout)
                                Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFFC7F36B)
                                        : const Color(0xFF101820),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _selectedDay == null
                ? 'この月の記録'
                : '${_selectedDay!.month}月${_selectedDay!.day}日の記録',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (shownWorkouts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'この日の記録はありません',
                  style: TextStyle(color: Color(0xFF6C746D)),
                ),
              ),
            )
          else
            ...shownWorkouts.map(
              (workout) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: HistoryCard(
                  workout: workout,
                  selectedGym: widget.selectedGym,
                  onWorkoutCompleted: widget.onWorkoutCompleted,
                  onWorkoutUpdated: widget.onWorkoutUpdated,
                  onWorkoutDeleted: widget.onWorkoutDeleted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HistorySearchPage extends StatefulWidget {
  const HistorySearchPage({
    super.key,
    required this.history,
    required this.selectedGym,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
  });

  final List<WorkoutRecord> history;
  final String? selectedGym;
  final ValueChanged<WorkoutRecord> onWorkoutCompleted;
  final Future<void> Function(DateTime, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  State<HistorySearchPage> createState() => _HistorySearchPageState();
}

class _HistorySearchPageState extends State<HistorySearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = _query.toLowerCase();
    final results = widget.history.where((workout) {
      if (normalized.isEmpty) return true;
      return workout.exerciseNames.any(
            (name) => name.toLowerCase().contains(normalized),
          ) ||
          workout.bodyParts.any((part) => part.contains(normalized)) ||
          (workout.gymName?.toLowerCase().contains(normalized) ?? false) ||
          workout.note.toLowerCase().contains(normalized);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F0),
        title: const Text('履歴を検索'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: '種目・部位・場所・メモ',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('該当する記録はありません'))
                  : ListView.separated(
                      itemCount: results.length,
                      padding: const EdgeInsets.only(bottom: 32),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => HistoryCard(
                        workout: results[index],
                        selectedGym: widget.selectedGym,
                        onWorkoutCompleted: widget.onWorkoutCompleted,
                        onWorkoutUpdated: widget.onWorkoutUpdated,
                        onWorkoutDeleted: widget.onWorkoutDeleted,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExerciseProgressPage extends StatefulWidget {
  const ExerciseProgressPage({super.key, required this.history});

  final List<WorkoutRecord> history;

  @override
  State<ExerciseProgressPage> createState() => _ExerciseProgressPageState();
}

class _ExerciseProgressPageState extends State<ExerciseProgressPage> {
  late String _selectedExercise;

  List<String> get _exerciseNames {
    final names = widget.history
        .expand((workout) => workout.exerciseNames)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  @override
  void initState() {
    super.initState();
    _selectedExercise = _exerciseNames.first;
  }

  List<_ExerciseProgressPoint> get _points {
    final points = <_ExerciseProgressPoint>[];
    for (final workout in widget.history.reversed) {
      final sets = workout.sets
          .where((set) => set.exerciseName == _selectedExercise)
          .toList();
      if (sets.isEmpty) continue;
      final bestWeight = sets.fold<double>(
        0.0,
        (best, set) => set.weight > best ? set.weight : best,
      );
      final estimatedOneRepMax = sets.fold<double>(0, (best, set) {
        final estimate = set.weight * (1 + set.reps / 30);
        return estimate > best ? estimate : best;
      });
      points.add(
        _ExerciseProgressPoint(
          date: workout.date,
          bestWeight: bestWeight,
          estimatedOneRepMax: estimatedOneRepMax,
          setCount: sets.length,
        ),
      );
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final bestWeight = points.fold<double>(
      0.0,
      (best, point) => point.bestWeight > best ? point.bestWeight : best,
    );
    final estimatedOneRepMax = points.fold<double>(
      0,
      (best, point) =>
          point.estimatedOneRepMax > best ? point.estimatedOneRepMax : best,
    );
    final totalSets = points.fold<int>(
      0,
      (total, point) => total + point.setCount,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F0),
        title: const Text('種目ごとの成長'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedExercise,
            decoration: const InputDecoration(
              labelText: '種目',
              border: OutlineInputBorder(),
            ),
            items: _exerciseNames
                .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _selectedExercise = value);
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ProgressMetric(
                  label: '最高重量',
                  value: '${formatWeight(bestWeight)} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProgressMetric(
                  label: '推定1RM',
                  value: '${estimatedOneRepMax.round()} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProgressMetric(label: '総セット', value: '$totalSets'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ExerciseProgressChart(points: points),
          const SizedBox(height: 24),
          const Text(
            '記録一覧',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...points.reversed.map(
            (point) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFC7F36B),
                  child: Icon(Icons.fitness_center_rounded),
                ),
                title: Text(
                  '${formatWeight(point.bestWeight)} kg',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${point.date.month}月${point.date.day}日 ・ ${point.setCount}セット',
                ),
                trailing: Text(
                  '1RM ${point.estimatedOneRepMax.round()} kg',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseProgressPoint {
  const _ExerciseProgressPoint({
    required this.date,
    required this.bestWeight,
    required this.estimatedOneRepMax,
    required this.setCount,
  });

  final DateTime date;
  final double bestWeight;
  final double estimatedOneRepMax;
  final int setCount;
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6C746D)),
          ),
          const SizedBox(height: 5),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseProgressChart extends StatelessWidget {
  const _ExerciseProgressChart({required this.points});

  final List<_ExerciseProgressPoint> points;

  @override
  Widget build(BuildContext context) {
    final visible = points.length > 8
        ? points.sublist(points.length - 8)
        : points;
    final maximum = visible.fold<double>(
      1.0,
      (best, point) => point.bestWeight > best ? point.bestWeight : best,
    );
    return Container(
      height: 190,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最高重量の変化',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: visible.map((point) {
                return Expanded(
                  child: Semantics(
                    label:
                        '${point.date.month}月${point.date.day}日、${formatWeight(point.bestWeight)} kg',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            formatWeight(point.bestWeight),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            height: 18 + (70 * point.bestWeight / maximum),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC7F36B),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${point.date.day}日',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.workout,
    required this.selectedGym,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
  });

  final WorkoutRecord workout;
  final String? selectedGym;
  final ValueChanged<WorkoutRecord> onWorkoutCompleted;
  final Future<void> Function(DateTime, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutDetailPage(
              workout: workout,
              selectedGym: selectedGym,
              onWorkoutCompleted: onWorkoutCompleted,
              onWorkoutUpdated: onWorkoutUpdated,
              onWorkoutDeleted: onWorkoutDeleted,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              DateBadge(date: workout.date),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workout.exerciseNames.length == 1
                          ? workout.exerciseNames.first
                          : '${workout.exerciseNames.first} ほか${workout.exerciseNames.length - 1}種目',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${workout.sets.length}セット ・ ${(workout.volume / 1000).toStringAsFixed(1)} t${workout.durationLabel.isEmpty ? '' : ' ・ ${workout.durationLabel}'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF777F78),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'BEST  ${formatWeight(workout.bestSet.weight)} kg × ${workout.bestSet.reps}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (workout.gymName != null &&
                        workout.gymName!.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Color(0xFF777F78),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              workout.gymName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777F78),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (workout.note.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.notes_rounded,
                            size: 14,
                            color: Color(0xFF777F78),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              workout.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777F78),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF777F78)),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({
    super.key,
    required this.workout,
    required this.selectedGym,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
  });

  final WorkoutRecord workout;
  final String? selectedGym;
  final ValueChanged<WorkoutRecord> onWorkoutCompleted;
  final Future<void> Function(DateTime, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F0),
        title: const Text(
          'トレーニング詳細',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                final updated = await Navigator.of(context).push<WorkoutRecord>(
                  MaterialPageRoute(
                    builder: (_) => WorkoutPage(
                      initialWorkout: workout,
                      isEditing: true,
                      gymName: workout.gymName ?? selectedGym,
                    ),
                  ),
                );
                if (updated != null && context.mounted) {
                  await onWorkoutUpdated(workout.date, updated);
                  if (context.mounted) Navigator.pop(context);
                }
              }
              if (value == 'delete' && context.mounted) {
                await _confirmDelete(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('記録を修正')),
              PopupMenuItem(value: 'delete', child: Text('記録を削除')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            '${workout.date.year}年${workout.date.month}月${workout.date.day}日',
            style: const TextStyle(color: Color(0xFF6C746D)),
          ),
          if (workout.gymName != null && workout.gymName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Color(0xFF6C746D),
                ),
                const SizedBox(width: 4),
                Text(
                  workout.gymName!,
                  style: const TextStyle(color: Color(0xFF6C746D)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${workout.exerciseNames.length}種目 ・ ${workout.sets.length}セット ・ ${(workout.volume / 1000).toStringAsFixed(1)} t${workout.durationLabel.isEmpty ? '' : ' ・ ${workout.durationLabel}'}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          if (workout.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      workout.note,
                      style: const TextStyle(color: Color(0xFF6C746D)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          ...workout.exerciseNames.map((name) {
            final sets = workout.sets
                .where((set) => set.exerciseName == name)
                .toList();
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sets.first.bodyPart,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF777F78),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(
                      sets.length,
                      (index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 42,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${formatWeight(sets[index].weight)} kg × ${sets[index].reps} 回',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF83AD30),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: () async {
                final repeated = await Navigator.of(context)
                    .push<WorkoutRecord>(
                      MaterialPageRoute(
                        builder: (_) => WorkoutPage(
                          history: [workout],
                          initialWorkout: workout,
                          gymName: selectedGym,
                        ),
                      ),
                    );
                if (repeated != null) onWorkoutCompleted(repeated);
              },
              icon: const Icon(Icons.replay_rounded),
              label: const Text('この内容でもう一度'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('この記録を削除しますか？'),
        content: const Text('削除した記録は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final deleted = await onWorkoutDeleted(workout);
    if (!context.mounted) return;
    if (deleted) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('クラウドとの通信に失敗したため削除できませんでした')),
      );
    }
  }
}

class WorkoutPage extends StatefulWidget {
  const WorkoutPage({
    super.key,
    this.history = const [],
    this.initialWorkout,
    this.isEditing = false,
    this.gymName,
  });

  final List<WorkoutRecord> history;
  final WorkoutRecord? initialWorkout;
  final bool isEditing;
  final String? gymName;

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  static const _draftStorageKey = 'active_workout_draft';
  final _formKey = GlobalKey<FormState>();
  late final DateTime _startedAt;
  late DateTime _workoutDate;
  Timer? _timer;
  Timer? _restTimer;
  Duration _elapsed = Duration.zero;
  int _restRemaining = 0;
  late final TextEditingController _noteController;
  late final List<WorkoutExercise> _exercises;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _workoutDate = widget.initialWorkout?.date ?? DateTime.now();
    _exercises = widget.initialWorkout == null
        ? [_exerciseFromTemplate(exerciseTemplates.first)]
        : _exercisesFrom(widget.initialWorkout!, completed: widget.isEditing);
    _noteController = TextEditingController(
      text: widget.isEditing ? widget.initialWorkout?.note ?? '' : '',
    );
    _noteController.addListener(_saveDraft);
    if (!widget.isEditing && widget.initialWorkout == null) {
      _loadDraft();
    }
    if (widget.isEditing) {
      _elapsed = Duration(seconds: widget.initialWorkout!.durationSeconds);
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _elapsed = DateTime.now().difference(_startedAt));
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  String get _elapsedLabel {
    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _addSet(int exerciseIndex) {
    setState(() {
      final sets = _exercises[exerciseIndex].sets;
      final previous = sets.last;
      sets.add(WorkoutSet(weight: previous.weight, reps: previous.reps));
    });
    unawaited(_saveDraft());
  }

  void _removeLastSet(int exerciseIndex) {
    setState(() {
      final sets = _exercises[exerciseIndex].sets;
      if (sets.length > 1) sets.removeLast();
    });
    unawaited(_saveDraft());
  }

  void _toggleSet(int exerciseIndex, int setIndex) {
    final set = _exercises[exerciseIndex].sets[setIndex];
    setState(() => set.completed = !set.completed);
    unawaited(_saveDraft());
    if (set.completed) HapticFeedback.mediumImpact();
    if (set.completed && !widget.isEditing && RestTimerPreference.enabled) {
      _startRestTimer();
    }
  }

  void _startRestTimer([int? seconds]) {
    _restTimer?.cancel();
    setState(() => _restRemaining = seconds ?? RestTimerPreference.seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_restRemaining <= 1) {
        timer.cancel();
        setState(() => _restRemaining = 0);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('休憩終了。次のセットへ！')));
      } else {
        setState(() => _restRemaining--);
      }
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    setState(() => _restRemaining = 0);
  }

  String get _restLabel {
    final minutes = (_restRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_restRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _addExercise() async {
    final existingNames = _exercises.map((item) => item.name).toSet();
    final selected = await showModalBottomSheet<ExerciseTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.82,
        child: ExercisePickerSheet(existingNames: existingNames),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _exercises.add(_exerciseFromTemplate(selected));
    });
    unawaited(_saveDraft());
  }

  Future<void> _loadDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_draftStorageKey);
    if (encoded == null || !mounted) return;
    try {
      final draft = jsonDecode(encoded) as Map<String, dynamic>;
      final exercises = (draft['exercises'] as List<dynamic>)
          .map((item) => _exerciseFromDraft(item as Map<String, dynamic>))
          .toList();
      if (exercises.isEmpty) return;
      setState(() {
        _exercises
          ..clear()
          ..addAll(exercises);
        _noteController.text = draft['note'] as String? ?? '';
        final savedDate = draft['date'] as String?;
        if (savedDate != null) _workoutDate = DateTime.parse(savedDate);
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('入力途中のトレーニングを再開しました')));
      }
    } catch (_) {
      await preferences.remove(_draftStorageKey);
    }
  }

  Future<void> _saveDraft() async {
    if (widget.isEditing) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _draftStorageKey,
      jsonEncode({
        'date': _workoutDate.toIso8601String(),
        'note': _noteController.text,
        'exercises': _exercises
            .map(
              (exercise) => {
                'name': exercise.name,
                'bodyPart': exercise.bodyPart,
                'equipment': exercise.equipment,
                'sets': exercise.sets
                    .map(
                      (set) => {
                        'weight': set.weight,
                        'reps': set.reps,
                        'completed': set.completed,
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
      }),
    );
  }

  Future<void> _clearDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_draftStorageKey);
  }

  WorkoutExercise _exerciseFromDraft(Map<String, dynamic> json) {
    return WorkoutExercise(
      name: json['name'] as String,
      bodyPart: json['bodyPart'] as String,
      equipment: json['equipment'] as String,
      sets: (json['sets'] as List<dynamic>).map((item) {
        final setJson = item as Map<String, dynamic>;
        return WorkoutSet(
          weight: (setJson['weight'] as num).toDouble(),
          reps: setJson['reps'] as int,
        )..completed = setJson['completed'] as bool? ?? false;
      }).toList(),
    );
  }

  Future<void> _selectWorkoutDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _workoutDate.isAfter(now) ? now : _workoutDate,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: 'トレーニング日',
      cancelText: 'キャンセル',
      confirmText: '決定',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _workoutDate = preserveWorkoutTime(_workoutDate, selected);
    });
    unawaited(_saveDraft());
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.isEditing ? '修正を中止しますか？' : 'ホームに戻りますか？'),
        content: Text(
          widget.isEditing ? '変更した内容は保存されません。' : '入力内容は自動保存され、次回ここから再開できます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('入力を続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('戻る'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F0),
        leading: BackButton(onPressed: _confirmLeave),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEditing ? '記録を修正' : 'トレーニング',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              '${widget.isEditing ? (widget.initialWorkout!.durationLabel.isEmpty ? '記録済み' : widget.initialWorkout!.durationLabel) : _elapsedLabel} ・ ${widget.gymName ?? '店舗未選択'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF777F78)),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('completeWorkoutButton'),
            onPressed: _completeWorkout,
            child: Text(
              widget.isEditing ? '保存' : '完了',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                key: const Key('workoutDateButton'),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE9F4D1),
                  child: Icon(Icons.calendar_today_rounded),
                ),
                title: const Text(
                  'トレーニング日',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6C746D)),
                ),
                subtitle: Text(
                  workoutDateLabel(_workoutDate),
                  style: const TextStyle(
                    color: Color(0xFF101820),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _selectWorkoutDate,
              ),
            ),
            const SizedBox(height: 16),
            if (_restRemaining > 0) ...[
              Container(
                key: const Key('restTimerBanner'),
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF101820),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: Color(0xFFC7F36B)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '休憩  $_restLabel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _startRestTimer(_restRemaining + 30),
                      child: const Text('+30秒'),
                    ),
                    TextButton(onPressed: _skipRest, child: const Text('終了')),
                  ],
                ),
              ),
            ],
            ...List.generate(
              _exercises.length,
              (exerciseIndex) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ExerciseInputCard(
                  exerciseIndex: exerciseIndex,
                  exercise: _exercises[exerciseIndex],
                  history: widget.history,
                  onAddSet: () => _addSet(exerciseIndex),
                  onRemoveLastSet: () => _removeLastSet(exerciseIndex),
                  onRemove: exerciseIndex == 0
                      ? null
                      : () {
                          setState(() => _exercises.removeAt(exerciseIndex));
                          unawaited(_saveDraft());
                        },
                  onToggleSet: (setIndex) =>
                      _toggleSet(exerciseIndex, setIndex),
                  onValuesChanged: _saveDraft,
                ),
              ),
            ),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                key: const Key('addExerciseButton'),
                onPressed: _addExercise,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF101820),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  '種目を追加',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'トレーニングメモ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      hintText: 'フォームや体調などをメモ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _completeWorkout() {
    _formKey.currentState?.save();
    final completedSets = <RecordedSet>[
      for (final exercise in _exercises)
        for (final set in exercise.sets)
          if (set.completed)
            RecordedSet(
              exerciseName: exercise.name,
              bodyPart: exercise.bodyPart,
              weight: set.weight,
              reps: set.reps,
              completed: true,
            ),
    ];
    if (completedSets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('完了したセットを1つ以上チェックしてください')));
      return;
    }

    if (completedSets.any((set) => set.weight <= 0 || set.reps <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('チェックしたセットの重量・回数に1以上の数字を入力してください')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final personalBests = _personalBestExercises(completedSets);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.isEditing ? '修正を保存' : 'トレーニング完了'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${completedSets.length}セットを${widget.isEditing ? '保存' : '記録'}します。',
            ),
            if (!widget.isEditing && personalBests.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F4D1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '自己ベスト更新\n${personalBests.join('・')}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              final record = WorkoutRecord(
                date: _workoutDate,
                sets: completedSets,
                durationSeconds: widget.isEditing
                    ? widget.initialWorkout!.durationSeconds
                    : _elapsed.inSeconds,
                gymName: widget.gymName,
                note: _noteController.text.trim(),
              );
              await _clearDraft();
              if (!dialogContext.mounted || !mounted) return;
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop(record);
            },
            child: Text(widget.isEditing ? '保存する' : 'ホームへ戻る'),
          ),
        ],
      ),
    );
  }

  List<String> _personalBestExercises(List<RecordedSet> completedSets) {
    final names = completedSets.map((set) => set.exerciseName).toSet();
    return names.where((name) {
      final currentBest = completedSets
          .where((set) => set.exerciseName == name)
          .fold<double>(
            0,
            (best, set) => set.weight > best ? set.weight : best,
          );
      final previousBest = widget.history
          .expand((workout) => workout.sets)
          .where((set) => set.exerciseName == name)
          .fold<double>(
            0,
            (best, set) => set.weight > best ? set.weight : best,
          );
      return currentBest > previousBest;
    }).toList();
  }

  WorkoutExercise _exerciseFromTemplate(ExerciseTemplate template) {
    for (final workout in widget.history) {
      final matching = workout.sets
          .where((set) => set.exerciseName == template.name)
          .toList();
      if (matching.isNotEmpty) {
        return WorkoutExercise(
          name: template.name,
          bodyPart: template.bodyPart,
          equipment: template.equipment,
          sets: matching
              .map((set) => WorkoutSet(weight: set.weight, reps: set.reps))
              .toList(),
        );
      }
    }
    return WorkoutExercise(
      name: template.name,
      bodyPart: template.bodyPart,
      equipment: template.equipment,
      sets: List.generate(
        3,
        (_) =>
            WorkoutSet(weight: template.startWeight, reps: template.startReps),
      ),
    );
  }

  static List<WorkoutExercise> _exercisesFrom(
    WorkoutRecord workout, {
    required bool completed,
  }) => workout.exerciseNames.map((name) {
    final recordedSets = workout.sets
        .where((set) => set.exerciseName == name)
        .toList();
    final template = exerciseTemplates.where((item) => item.name == name);
    return WorkoutExercise(
      name: name,
      bodyPart: recordedSets.first.bodyPart,
      equipment: template.isEmpty ? 'フリーウェイト' : template.first.equipment,
      sets: recordedSets
          .map(
            (set) =>
                WorkoutSet(weight: set.weight, reps: set.reps)
                  ..completed = completed,
          )
          .toList(),
    );
  }).toList();
}

DateTime preserveWorkoutTime(DateTime original, DateTime calendarDay) =>
    DateTime(
      calendarDay.year,
      calendarDay.month,
      calendarDay.day,
      original.hour,
      original.minute,
      original.second,
      original.millisecond,
      original.microsecond,
    );

String workoutDateLabel(DateTime date) {
  final now = DateTime.now();
  final isToday =
      date.year == now.year && date.month == now.month && date.day == now.day;
  final formatted = '${date.year}年${date.month}月${date.day}日';
  return isToday ? '今日・$formatted' : formatted;
}

class SavedWorkoutTemplate {
  const SavedWorkoutTemplate({required this.name, required this.sets});

  final String name;
  final List<RecordedSet> sets;

  List<String> get exerciseNames =>
      sets.map((set) => set.exerciseName).toSet().toList(growable: false);

  WorkoutRecord toWorkoutRecord() =>
      WorkoutRecord(date: DateTime.now(), sets: sets);

  factory SavedWorkoutTemplate.fromJson(Map<String, dynamic> json) =>
      SavedWorkoutTemplate(
        name: json['name'] as String,
        sets: (json['sets'] as List<dynamic>)
            .map((item) => RecordedSet.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'sets': sets.map((set) => set.toJson()).toList(),
  };
}

class WorkoutTemplatePreference {
  WorkoutTemplatePreference._();

  static const _storageKey = 'workout_templates';

  static Future<List<SavedWorkoutTemplate>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) return [];
    try {
      return (jsonDecode(encoded) as List<dynamic>)
          .map(
            (item) =>
                SavedWorkoutTemplate.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<SavedWorkoutTemplate> templates) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(templates.map((item) => item.toJson()).toList()),
    );
  }
}

class MuscleMemoryBackup {
  const MuscleMemoryBackup({
    required this.workouts,
    this.workoutTemplates = const [],
    this.customExercises = const [],
    this.selectedGym,
    this.weeklyTarget,
    this.restTimerEnabled,
    this.restTimerSeconds,
  });

  final List<WorkoutRecord> workouts;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final List<ExerciseTemplate> customExercises;
  final String? selectedGym;
  final int? weeklyTarget;
  final bool? restTimerEnabled;
  final int? restTimerSeconds;

  factory MuscleMemoryBackup.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int?;
    if (json['app'] != 'MuscleMemory' || (version != 1 && version != 2)) {
      throw const FormatException('Unsupported Muscle Memory backup');
    }
    final settings = json['settings'] as Map<String, dynamic>? ?? const {};
    return MuscleMemoryBackup(
      workouts: (json['workouts'] as List<dynamic>? ?? const [])
          .map((item) => WorkoutRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      workoutTemplates: version == 1
          ? const []
          : (json['workoutTemplates'] as List<dynamic>? ?? const [])
                .map(
                  (item) => SavedWorkoutTemplate.fromJson(
                    item as Map<String, dynamic>,
                  ),
                )
                .toList(),
      customExercises: version == 1
          ? const []
          : (json['customExercises'] as List<dynamic>? ?? const [])
                .map(
                  (item) =>
                      ExerciseTemplate.fromJson(item as Map<String, dynamic>),
                )
                .toList(),
      selectedGym: settings['selectedGym'] as String?,
      weeklyTarget: settings['weeklyTarget'] as int?,
      restTimerEnabled: settings['restTimerEnabled'] as bool?,
      restTimerSeconds: settings['restTimerSeconds'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'app': 'MuscleMemory',
    'version': 2,
    'exportedAt': DateTime.now().toIso8601String(),
    'workouts': workouts.map((item) => item.toJson()).toList(),
    'workoutTemplates': workoutTemplates.map((item) => item.toJson()).toList(),
    'customExercises': customExercises.map((item) => item.toJson()).toList(),
    'settings': {
      'selectedGym': selectedGym,
      'weeklyTarget': weeklyTarget,
      'restTimerEnabled': restTimerEnabled,
      'restTimerSeconds': restTimerSeconds,
    },
  };
}

class ExerciseTemplate {
  const ExerciseTemplate({
    required this.name,
    required this.bodyPart,
    required this.equipment,
    required this.startWeight,
    this.startReps = 10,
  });

  final String name;
  final String bodyPart;
  final String equipment;
  final double startWeight;
  final int startReps;

  factory ExerciseTemplate.fromJson(Map<String, dynamic> json) =>
      ExerciseTemplate(
        name: json['name'] as String,
        bodyPart: json['bodyPart'] as String,
        equipment: json['equipment'] as String? ?? 'カスタム',
        startWeight: (json['startWeight'] as num?)?.toDouble() ?? 10,
        startReps: json['startReps'] as int? ?? 10,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'bodyPart': bodyPart,
    'equipment': equipment,
    'startWeight': startWeight,
    'startReps': startReps,
  };
}

class CustomExercisePreference {
  CustomExercisePreference._();

  static const _storageKey = 'custom_exercises';
  static List<ExerciseTemplate> exercises = [];

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      exercises = [];
      return;
    }
    try {
      exercises = (jsonDecode(encoded) as List<dynamic>).map((item) {
        final json = item as Map<String, dynamic>;
        return ExerciseTemplate.fromJson(json);
      }).toList();
    } catch (_) {
      exercises = [];
    }
  }

  static Future<void> add(ExerciseTemplate exercise) async {
    if (exerciseTemplates.any((item) => item.name == exercise.name) ||
        exercises.any((item) => item.name == exercise.name)) {
      return;
    }
    await replaceAll([...exercises, exercise]);
  }

  static Future<void> replaceAll(List<ExerciseTemplate> updated) async {
    exercises = updated
        .where(
          (exercise) =>
              !exerciseTemplates.any((item) => item.name == exercise.name),
        )
        .toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(exercises.map((item) => item.toJson()).toList()),
    );
  }
}

const exerciseTemplates = [
  ExerciseTemplate(
    name: 'ベンチプレス',
    bodyPart: '胸',
    equipment: 'フリーウェイト',
    startWeight: 40,
  ),
  ExerciseTemplate(
    name: 'インクラインダンベルプレス',
    bodyPart: '胸',
    equipment: 'ダンベル',
    startWeight: 20,
  ),
  ExerciseTemplate(
    name: 'ラットプルダウン',
    bodyPart: '背中',
    equipment: 'マシン',
    startWeight: 40,
  ),
  ExerciseTemplate(
    name: 'スクワット',
    bodyPart: '脚',
    equipment: 'フリーウェイト',
    startWeight: 40,
  ),
  ExerciseTemplate(
    name: 'ショルダープレス',
    bodyPart: '肩',
    equipment: 'ダンベル',
    startWeight: 12,
  ),
  ExerciseTemplate(
    name: 'アームカール',
    bodyPart: '腕',
    equipment: 'ダンベル',
    startWeight: 10,
  ),
  ExerciseTemplate(
    name: 'チェストプレス',
    bodyPart: '胸',
    equipment: 'マシン',
    startWeight: 30,
  ),
  ExerciseTemplate(
    name: 'ダンベルフライ',
    bodyPart: '胸',
    equipment: 'ダンベル',
    startWeight: 10,
  ),
  ExerciseTemplate(
    name: 'デッドリフト',
    bodyPart: '背中',
    equipment: 'フリーウェイト',
    startWeight: 50,
  ),
  ExerciseTemplate(
    name: 'バーベルロウ',
    bodyPart: '背中',
    equipment: 'フリーウェイト',
    startWeight: 30,
  ),
  ExerciseTemplate(
    name: 'シーテッドロウ',
    bodyPart: '背中',
    equipment: 'マシン',
    startWeight: 30,
  ),
  ExerciseTemplate(name: '懸垂', bodyPart: '背中', equipment: '自重', startWeight: 1),
  ExerciseTemplate(
    name: 'レッグプレス',
    bodyPart: '脚',
    equipment: 'マシン',
    startWeight: 60,
  ),
  ExerciseTemplate(
    name: 'レッグエクステンション',
    bodyPart: '脚',
    equipment: 'マシン',
    startWeight: 25,
  ),
  ExerciseTemplate(
    name: 'レッグカール',
    bodyPart: '脚',
    equipment: 'マシン',
    startWeight: 20,
  ),
  ExerciseTemplate(
    name: 'ブルガリアンスクワット',
    bodyPart: '脚',
    equipment: 'ダンベル',
    startWeight: 10,
  ),
  ExerciseTemplate(
    name: 'サイドレイズ',
    bodyPart: '肩',
    equipment: 'ダンベル',
    startWeight: 5,
  ),
  ExerciseTemplate(
    name: 'リアレイズ',
    bodyPart: '肩',
    equipment: 'ダンベル',
    startWeight: 5,
  ),
  ExerciseTemplate(
    name: 'トライセプスプッシュダウン',
    bodyPart: '腕',
    equipment: 'ケーブル',
    startWeight: 15,
  ),
  ExerciseTemplate(
    name: 'ハンマーカール',
    bodyPart: '腕',
    equipment: 'ダンベル',
    startWeight: 8,
  ),
  ExerciseTemplate(
    name: 'クランチ',
    bodyPart: '腹',
    equipment: '自重',
    startWeight: 1,
    startReps: 15,
  ),
];

class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({super.key, required this.existingNames});

  final Set<String> existingNames;

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final allExercises = [
      ...exerciseTemplates,
      ...CustomExercisePreference.exercises,
    ];
    final filtered = allExercises.where((template) {
      final query = _query.toLowerCase();
      return template.name.toLowerCase().contains(query) ||
          template.bodyPart.contains(query) ||
          template.equipment.toLowerCase().contains(query);
    }).toList();
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '種目を選択',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: '種目名・部位・器具で検索',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF101820),
                    foregroundColor: Colors.white,
                    child: Icon(Icons.add_rounded),
                  ),
                  title: const Text(
                    '自分で種目を作る',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: const Text('一覧にない種目を追加'),
                  onTap: _createCustomExercise,
                ),
                const Divider(),
                ...filtered.map((template) {
                  final added = widget.existingNames.contains(template.name);
                  return ListTile(
                    enabled: !added,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFC7F36B),
                      child: Icon(Icons.fitness_center_rounded),
                    ),
                    title: Text(
                      template.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${template.bodyPart} ・ ${template.equipment}',
                    ),
                    trailing: added
                        ? const Text('追加済み')
                        : const Icon(Icons.add_rounded),
                    onTap: added
                        ? null
                        : () => Navigator.pop(context, template),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createCustomExercise() async {
    final nameController = TextEditingController();
    String bodyPart = '胸';
    final created = await showDialog<ExerciseTemplate>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新しい種目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '種目名'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: bodyPart,
                decoration: const InputDecoration(labelText: '鍛える部位'),
                items: const ['胸', '背中', '脚', '肩', '腕', '腹']
                    .map(
                      (part) =>
                          DropdownMenuItem(value: part, child: Text(part)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => bodyPart = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty || widget.existingNames.contains(name)) return;
                Navigator.pop(
                  dialogContext,
                  ExerciseTemplate(
                    name: name,
                    bodyPart: bodyPart,
                    equipment: 'カスタム',
                    startWeight: 10,
                  ),
                );
              },
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (created != null) {
      await CustomExercisePreference.add(created);
      if (mounted) Navigator.pop(context, created);
    }
  }
}

class WorkoutExercise {
  WorkoutExercise({
    required this.name,
    required this.bodyPart,
    required this.equipment,
    required this.sets,
  });

  final String name;
  final String bodyPart;
  final String equipment;
  final List<WorkoutSet> sets;
}

class ExerciseInputCard extends StatelessWidget {
  const ExerciseInputCard({
    super.key,
    required this.exerciseIndex,
    required this.exercise,
    required this.history,
    required this.onAddSet,
    required this.onRemoveLastSet,
    required this.onRemove,
    required this.onToggleSet,
    required this.onValuesChanged,
  });

  final int exerciseIndex;
  final WorkoutExercise exercise;
  final List<WorkoutRecord> history;
  final VoidCallback onAddSet;
  final VoidCallback onRemoveLastSet;
  final VoidCallback? onRemove;
  final ValueChanged<int> onToggleSet;
  final VoidCallback onValuesChanged;

  @override
  Widget build(BuildContext context) {
    List<RecordedSet> previousSets = [];
    for (final workout in history) {
      final matching = workout.sets
          .where((set) => set.exerciseName == exercise.name)
          .toList();
      if (matching.isNotEmpty) {
        previousSets = matching;
        break;
      }
    }
    final previousText = previousSets.isEmpty
        ? '前回の記録はありません'
        : '前回  ${previousSets.map((set) => '${formatWeight(set.weight)}kg × ${set.reps}').join(' ・ ')}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${exercise.bodyPart} ・ ${exercise.equipment}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF777F78),
                      ),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: '種目を削除',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF2EA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    previousText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SetHeader(),
          const SizedBox(height: 8),
          ...List.generate(exercise.sets.length, (setIndex) {
            final set = exercise.sets[setIndex];
            return SetRow(
              number: setIndex + 1,
              fieldPrefix: '${exerciseIndex}_',
              set: set,
              onWeightChanged: (value) {
                set.weight = value;
                onValuesChanged();
              },
              onRepsChanged: (value) {
                set.reps = value;
                onValuesChanged();
              },
              onToggle: () => onToggleSet(setIndex),
            );
          }),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: exerciseIndex == 0
                      ? const Key('addSetButton')
                      : Key('addSetButton$exerciseIndex'),
                  onPressed: onAddSet,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('セットを追加'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: '最後のセットを削除',
                onPressed: exercise.sets.length > 1 ? onRemoveLastSet : null,
                icon: const Icon(Icons.remove_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String formatWeight(double weight) {
  if (weight == weight.roundToDouble()) return weight.toInt().toString();
  return weight
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

double parseWeight(String? text) =>
    double.tryParse((text ?? '').replaceAll(',', '.')) ?? 0;

class WorkoutSet {
  WorkoutSet({required this.weight, required this.reps});

  double weight;
  int reps;
  bool completed = false;
}

class RecordedSet {
  const RecordedSet({
    this.exerciseName = 'ベンチプレス',
    this.bodyPart = '胸',
    required this.weight,
    required this.reps,
    required this.completed,
  });

  final String exerciseName;
  final String bodyPart;
  final double weight;
  final int reps;
  final bool completed;

  factory RecordedSet.fromJson(Map<String, dynamic> json) => RecordedSet(
    exerciseName: json['exerciseName'] as String? ?? 'ベンチプレス',
    bodyPart: json['bodyPart'] as String? ?? '胸',
    weight: (json['weight'] as num).toDouble(),
    reps: json['reps'] as int,
    completed: json['completed'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'exerciseName': exerciseName,
    'bodyPart': bodyPart,
    'weight': weight,
    'reps': reps,
    'completed': completed,
  };
}

class WorkoutRecord {
  const WorkoutRecord({
    required this.date,
    required this.sets,
    this.durationSeconds = 0,
    this.gymName,
    this.note = '',
  });

  final DateTime date;
  final List<RecordedSet> sets;
  final int durationSeconds;
  final String? gymName;
  final String note;

  List<String> get exerciseNames =>
      sets.map((set) => set.exerciseName).toSet().toList(growable: false);

  List<String> get bodyParts =>
      sets.map((set) => set.bodyPart).toSet().toList(growable: false);

  String get durationLabel {
    if (durationSeconds <= 0) return '';
    final minutes = (durationSeconds / 60).ceil();
    return '$minutes分';
  }

  double get volume =>
      sets.fold<double>(0, (total, set) => total + (set.weight * set.reps));

  RecordedSet get bestSet => sets.reduce(
    (best, set) => set.weight * set.reps > best.weight * best.reps ? set : best,
  );

  factory WorkoutRecord.fromJson(Map<String, dynamic> json) => WorkoutRecord(
    date: DateTime.parse(json['date'] as String),
    durationSeconds: json['durationSeconds'] as int? ?? 0,
    gymName: json['gymName'] as String?,
    note: json['note'] as String? ?? '',
    sets: (json['sets'] as List<dynamic>)
        .map((item) => RecordedSet.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'durationSeconds': durationSeconds,
    'gymName': gymName,
    'note': note,
    'sets': sets.map((set) => set.toJson()).toList(),
  };
}

List<WorkoutRecord> sortWorkoutsNewestFirst(Iterable<WorkoutRecord> workouts) =>
    workouts.toList()..sort((a, b) => b.date.compareTo(a.date));

const setLabelStyle = TextStyle(
  fontSize: 10,
  color: Color(0xFF777F78),
  fontWeight: FontWeight.w800,
  letterSpacing: 1,
);

class SetHeader extends StatelessWidget {
  const SetHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(width: 42, child: Text('SET', style: setLabelStyle)),
        Expanded(
          child: Center(child: Text('KG', style: setLabelStyle)),
        ),
        Expanded(
          child: Center(child: Text('REPS', style: setLabelStyle)),
        ),
        SizedBox(width: 42),
      ],
    );
  }
}

class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.number,
    this.fieldPrefix = '',
    required this.set,
    required this.onWeightChanged,
    required this.onRepsChanged,
    required this.onToggle,
  });

  final int number;
  final String fieldPrefix;
  final WorkoutSet set;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onRepsChanged;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '$number',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: ValueBox(
              key: Key('weightField$fieldPrefix$number'),
              value: set.weight,
              allowDecimal: true,
              onChanged: (value) => onWeightChanged(value.toDouble()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ValueBox(
              key: Key('repsField$fieldPrefix$number'),
              value: set.reps,
              onChanged: (value) => onRepsChanged(value.toInt()),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton.filled(
              padding: EdgeInsets.zero,
              onPressed: onToggle,
              style: IconButton.styleFrom(
                backgroundColor: set.completed
                    ? const Color(0xFFC7F36B)
                    : const Color(0xFFE8EBE5),
                foregroundColor: const Color(0xFF101820),
              ),
              icon: Icon(
                set.completed ? Icons.check_rounded : Icons.circle_outlined,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ValueBox extends StatelessWidget {
  const ValueBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowDecimal = false,
  });

  final num value;
  final ValueChanged<num> onChanged;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: allowDecimal ? formatWeight(value.toDouble()) : '$value',
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      textInputAction: TextInputAction.done,
      textAlign: TextAlign.center,
      inputFormatters: [
        if (allowDecimal)
          TextInputFormatter.withFunction((oldValue, newValue) {
            final valid = RegExp(r'^\d*([\.,]\d{0,2})?$');
            return valid.hasMatch(newValue.text) ? newValue : oldValue;
          })
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      onChanged: (text) {
        final parsed = allowDecimal
            ? parseWeight(text)
            : int.tryParse(text) ?? 0;
        onChanged(parsed);
      },
      onSaved: (text) => onChanged(
        allowDecimal ? parseWeight(text) : int.tryParse(text ?? '') ?? 0,
      ),
      style: const TextStyle(fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF4F5F0),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

Future<String?> showGymPicker(BuildContext context, String? currentGym) {
  const standardGyms = ['自宅', 'エニタイムフィットネス', 'ゴールドジム', 'FIT PLACE24'];
  final gyms = [
    if (currentGym != null && !standardGyms.contains(currentGym)) currentGym,
    ...standardGyms,
  ];
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Text(
              'トレーニング場所',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
          ),
          ...gyms.map(
            (gym) => ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(
                gym,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: gym == currentGym
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF83AD30),
                    )
                  : null,
              onTap: () => Navigator.pop(context, gym),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_location_alt_outlined),
            title: const Text(
              '場所を追加',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('ジム名などを自由に入力'),
            onTap: () async {
              final gym = await _showCustomGymDialog(context);
              if (gym != null && context.mounted) Navigator.pop(context, gym);
            },
          ),
        ],
      ),
    ),
  );
}

Future<String?> _showCustomGymDialog(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('場所を追加'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '場所の名前',
          hintText: '例：近所の体育館',
        ),
        onSubmitted: (value) {
          final name = value.trim();
          if (name.isNotEmpty) Navigator.pop(dialogContext, name);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.pop(dialogContext, name);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.selectedGym,
    required this.onGymChanged,
    required this.history,
    required this.onSyncRequested,
    required this.workoutTemplates,
    required this.onBackupImported,
    required this.weeklyTarget,
    required this.onWeeklyTargetChanged,
    required this.restTimerEnabled,
    required this.restTimerSeconds,
    required this.onRestTimerEnabledChanged,
    required this.onRestTimerSecondsChanged,
  });

  final String? selectedGym;
  final ValueChanged<String> onGymChanged;
  final List<WorkoutRecord> history;
  final Future<int> Function() onSyncRequested;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final Future<int> Function(MuscleMemoryBackup) onBackupImported;
  final int weeklyTarget;
  final ValueChanged<int> onWeeklyTargetChanged;
  final bool restTimerEnabled;
  final int restTimerSeconds;
  final ValueChanged<bool> onRestTimerEnabledChanged;
  final ValueChanged<int> onRestTimerSecondsChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: [
          const Text(
            'マイページ',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 22),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFFC7F36B),
                    child: Icon(Icons.person_rounded, size: 30),
                  ),
                  SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MuscleMemoryユーザー',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '今日の1セットを積み上げよう',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777F78),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                ListTile(
                  key: const Key('exportBackupFile'),
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('バックアップを書き出す'),
                  subtitle: const Text('日付付きJSONファイルとして保存・共有'),
                  onTap: () => _shareBackup(context),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('importBackupFile'),
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('ファイルから復元'),
                  subtitle: const Text('JSONバックアップを選んで読み込み'),
                  onTap: () => _restoreFromFile(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.copy_all_outlined),
                  title: const Text('バックアップをコピー'),
                  subtitle: const Text('JSONをクリップボードへコピー'),
                  onTap: () => _copyBackup(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore_rounded),
                  title: const Text('バックアップを読み込む'),
                  subtitle: const Text('コピーした記録をこの端末に追加'),
                  onTap: () => _restoreBackup(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'データ同期',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Supabaseクラウド'),
              subtitle: Text(_cloudStatus),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: SupabaseConfig.initialized
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CloudAccountPage(
                          historyCount: history.length,
                          onSyncRequested: onSyncRequested,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'トレーニング設定',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('いつもの場所'),
                  subtitle: Text(selectedGym ?? '未選択'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final selected = await showGymPicker(context, selectedGym);
                    if (selected != null) onGymChanged(selected);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('1週間の目標'),
                  trailing: Text(
                    '$weeklyTarget回',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () => _selectWeeklyTarget(context),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('restTimerSwitch'),
                  secondary: const Icon(Icons.timer_outlined),
                  title: const Text('休憩タイマー'),
                  subtitle: Text(restTimerEnabled ? 'セット完了後に開始' : '使用しない'),
                  value: restTimerEnabled,
                  onChanged: onRestTimerEnabledChanged,
                ),
                if (restTimerEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.hourglass_bottom_rounded),
                    title: const Text('休憩時間'),
                    trailing: Text(
                      _restDurationLabel(restTimerSeconds),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onTap: () => _selectRestDuration(context),
                  ),
                ],
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.scale_outlined),
                  title: Text('重量の単位'),
                  trailing: Text(
                    'kg',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _cloudStatus {
    if (!SupabaseConfig.isConfigured) return '未設定・端末内に安全に保存中';
    if (SupabaseConfig.initializationError != null) return '接続設定を確認してください';
    if (SupabaseSyncService.isSignedIn) return 'ログイン済み・同期できます';
    return '接続準備完了・ログインしてください';
  }

  Future<void> _copyBackup(BuildContext context) async {
    final backup = _backupJson();
    await Clipboard.setData(ClipboardData(text: backup));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('バックアップをコピーしました')));
  }

  Future<void> _restoreBackup(BuildContext context) async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!context.mounted) return;
      await _restoreText(context, clipboard?.text ?? '');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MuscleMemoryのバックアップが見つかりません')),
      );
    }
  }

  String _backupJson() => jsonEncode(
    MuscleMemoryBackup(
      workouts: history,
      workoutTemplates: workoutTemplates,
      customExercises: CustomExercisePreference.exercises,
      selectedGym: selectedGym,
      weeklyTarget: weeklyTarget,
      restTimerEnabled: restTimerEnabled,
      restTimerSeconds: restTimerSeconds,
    ).toJson(),
  );

  Future<void> _shareBackup(BuildContext context) async {
    try {
      final now = DateTime.now();
      final date =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final fileName = 'muscle_memory_backup_$date.json';
      await SharePlus.instance.share(
        ShareParams(
          title: 'Muscle Memory バックアップ',
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(_backupJson())),
              mimeType: 'application/json',
            ),
          ],
          fileNameOverrides: [fileName],
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('バックアップを書き出せませんでした')));
    }
  }

  Future<void> _restoreFromFile(BuildContext context) async {
    try {
      const jsonType = XTypeGroup(
        label: 'Muscle Memory JSON',
        extensions: ['json'],
        uniformTypeIdentifiers: ['public.json'],
      );
      final file = await openFile(acceptedTypeGroups: [jsonType]);
      if (file == null) return;
      final source = await file.readAsString();
      if (!context.mounted) return;
      await _restoreText(context, source);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('バックアップを読み込めませんでした')));
    }
  }

  Future<void> _restoreText(BuildContext context, String source) async {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final backup = MuscleMemoryBackup.fromJson(decoded);
    final count = await onBackupImported(backup);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$count件の新しい記録と設定を読み込みました')));
  }

  Future<void> _selectWeeklyTarget(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text(
                '1週間の目標',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
            ),
            ...List.generate(6, (index) {
              final value = index + 2;
              return ListTile(
                title: Text('週$value回'),
                trailing: value == weeklyTarget
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF83AD30),
                      )
                    : null,
                onTap: () => Navigator.pop(context, value),
              );
            }),
          ],
        ),
      ),
    );
    if (selected != null) onWeeklyTargetChanged(selected);
  }

  String _restDurationLabel(int seconds) {
    if (seconds < 60) return '$seconds秒';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '$minutes分' : '$minutes分$remainder秒';
  }

  Future<void> _selectRestDuration(BuildContext context) async {
    const durations = [30, 60, 90, 120, 180];
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text(
                '休憩時間',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
            ),
            ...durations.map(
              (seconds) => ListTile(
                title: Text(_restDurationLabel(seconds)),
                trailing: seconds == restTimerSeconds
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF83AD30),
                      )
                    : null,
                onTap: () => Navigator.pop(context, seconds),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) onRestTimerSecondsChanged(selected);
  }
}

class CloudAccountPage extends StatefulWidget {
  const CloudAccountPage({
    super.key,
    required this.historyCount,
    required this.onSyncRequested,
  });

  final int historyCount;
  final Future<int> Function() onSyncRequested;

  @override
  State<CloudAccountPage> createState() => _CloudAccountPageState();
}

class _CloudAccountPageState extends State<CloudAccountPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      _message = error.message;
    } catch (_) {
      _message = '通信に失敗しました。接続を確認してください。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    final count = await widget.onSyncRequested();
    _message = '$count件の記録を同期しました';
  });

  Future<void> _signUp() => _run(() async {
    final response = await Supabase.instance.client.auth.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    _message = response.session == null
        ? '確認メールを送りました。メールを開いて登録を完了してください。'
        : 'アカウントを作成しました';
  });

  Future<void> _signOut() => _run(() async {
    await Supabase.instance.client.auth.signOut();
    _message = 'ログアウトしました';
  });

  @override
  Widget build(BuildContext context) {
    final signedIn = SupabaseSyncService.isSignedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('クラウド同期')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            signedIn ? 'Supabaseにログイン中' : 'アカウントで同期',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '端末内の${widget.historyCount}件の記録を、同じアカウントの端末で使えるようにします。',
            style: const TextStyle(color: Color(0xFF6C746D), height: 1.5),
          ),
          const SizedBox(height: 24),
          if (!signedIn) ...[
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'メールアドレス',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'パスワード（6文字以上）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: const Text('ログインして同期'),
            ),
            TextButton(
              onPressed: _busy ? null : _signUp,
              child: const Text('新しいアカウントを作る'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final count = await widget.onSyncRequested();
                      _message = '$count件の記録を同期しました';
                    }),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('今すぐ同期'),
            ),
            TextButton(
              onPressed: _busy ? null : _signOut,
              child: const Text('ログアウト'),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC7F36B),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 36),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF6C746D)),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
