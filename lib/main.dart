import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'services/supabase_sync_service.dart';

const activeWorkoutDraftStorageKey = 'active_workout_draft';

String formatVolumeKg(double volume) {
  final raw = volume == volume.roundToDouble()
      ? volume.toStringAsFixed(0)
      : volume.toStringAsFixed(1);
  return raw.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
}

Future<bool> discardDraftBeforeNewWorkout(BuildContext context) async {
  final preferences = await SharedPreferences.getInstance();
  final draft = WorkoutDraftSummary.tryParse(
    preferences.getString(activeWorkoutDraftStorageKey),
  );
  if (draft == null) return true;
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('新しく始めますか？'),
      content: const Text('入力途中の内容は破棄されます。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('破棄して始める'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await preferences.remove(activeWorkoutDraftStorageKey);
  return true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RestTimerPreference.load();
  await WorkoutUiPreference.load();
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

class WorkoutUiPreference {
  WorkoutUiPreference._();

  static const _completionCheckKey = 'completion_check_enabled';
  static const _workoutTimerKey = 'workout_timer_enabled';
  static const _workoutDurationKey = 'workout_duration_enabled';
  static bool completionCheckEnabled = true;
  static bool workoutTimerEnabled = true;
  static bool workoutDurationEnabled = true;

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    completionCheckEnabled = preferences.getBool(_completionCheckKey) ?? true;
    workoutTimerEnabled = preferences.getBool(_workoutTimerKey) ?? true;
    workoutDurationEnabled = preferences.getBool(_workoutDurationKey) ?? true;
    if (!completionCheckEnabled && RestTimerPreference.enabled) {
      await RestTimerPreference.setEnabled(false);
    }
  }

  static Future<void> setCompletionCheckEnabled(bool value) async {
    completionCheckEnabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completionCheckKey, value);
    if (!value) await RestTimerPreference.setEnabled(false);
  }

  static Future<void> setWorkoutTimerEnabled(bool value) async {
    workoutTimerEnabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_workoutTimerKey, value);
  }

  static Future<void> setWorkoutDurationEnabled(bool value) async {
    workoutDurationEnabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_workoutDurationKey, value);
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
  WorkoutDraftSummary? _workoutDraft;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final workoutTemplates = await WorkoutTemplatePreference.load();
    await CustomGymPreference.load();
    final encoded = preferences.getString(_storageKey);
    final selectedGym = preferences.getString(_gymStorageKey);
    if (selectedGym != null &&
        !standardGyms.contains(selectedGym) &&
        !CustomGymPreference.gyms.contains(selectedGym)) {
      await CustomGymPreference.add(selectedGym);
    }
    final workoutDraft = WorkoutDraftSummary.tryParse(
      preferences.getString(activeWorkoutDraftStorageKey),
    );
    if (!mounted) return;
    final items = sortWorkoutsNewestFirst(decodeWorkoutHistory(encoded));
    setState(() {
      _history = items;
      _selectedGym = selectedGym;
      _weeklyTarget = preferences.getInt(_weeklyTargetStorageKey) ?? 3;
      _workoutTemplates = workoutTemplates;
      _workoutDraft = workoutDraft;
    });
  }

  Future<void> _refreshWorkoutDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final draft = WorkoutDraftSummary.tryParse(
      preferences.getString(activeWorkoutDraftStorageKey),
    );
    if (mounted) setState(() => _workoutDraft = draft);
  }

  Future<void> _discardWorkoutDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(activeWorkoutDraftStorageKey);
    if (mounted) setState(() => _workoutDraft = null);
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

  Future<void> _replaceWorkoutTemplates(
    List<SavedWorkoutTemplate> templates,
  ) async {
    final updated = List<SavedWorkoutTemplate>.from(templates);
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
    if (backup.completionCheckEnabled != null) {
      await _saveCompletionCheckEnabled(backup.completionCheckEnabled!);
    }
    if (backup.workoutTimerEnabled != null) {
      await _saveWorkoutTimerEnabled(backup.workoutTimerEnabled!);
    }
    if (backup.workoutDurationEnabled != null) {
      await _saveWorkoutDurationEnabled(backup.workoutDurationEnabled!);
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
    await CustomGymPreference.replaceAll([
      ...CustomGymPreference.gyms,
      ...backup.customGyms,
    ]);
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
        final workout = WorkoutRecord.tryFromJson(item);
        if (workout == null) continue;
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
    await CustomGymPreference.add(gym);
    await _setGym(gym);
  }

  Future<void> _setGym(String? gym) async {
    setState(() => _selectedGym = gym);
    final preferences = await SharedPreferences.getInstance();
    if (gym == null) {
      await preferences.remove(_gymStorageKey);
    } else {
      await preferences.setString(_gymStorageKey, gym);
    }
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

  Future<void> _saveCompletionCheckEnabled(bool enabled) async {
    await WorkoutUiPreference.setCompletionCheckEnabled(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _saveWorkoutTimerEnabled(bool enabled) async {
    await WorkoutUiPreference.setWorkoutTimerEnabled(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _saveWorkoutDurationEnabled(bool enabled) async {
    await WorkoutUiPreference.setWorkoutDurationEnabled(enabled);
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
        onWorkoutUpdated: _replaceWorkout,
        onWorkoutDeleted: _deleteWorkout,
        workoutTemplates: _workoutTemplates,
        onTemplateSaved: _saveWorkoutTemplate,
        onTemplateDeleted: _deleteWorkoutTemplate,
        workoutDraft: _workoutDraft,
        onDraftChanged: _refreshWorkoutDraft,
        onDraftDiscarded: _discardWorkoutDraft,
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
        completionCheckEnabled: WorkoutUiPreference.completionCheckEnabled,
        workoutTimerEnabled: WorkoutUiPreference.workoutTimerEnabled,
        workoutDurationEnabled: WorkoutUiPreference.workoutDurationEnabled,
        onRestTimerEnabledChanged: _saveRestTimerEnabled,
        onRestTimerSecondsChanged: _saveRestTimerSeconds,
        onCompletionCheckEnabledChanged: _saveCompletionCheckEnabled,
        onWorkoutTimerEnabledChanged: _saveWorkoutTimerEnabled,
        onWorkoutDurationEnabledChanged: _saveWorkoutDurationEnabled,
        onCustomExercisesChanged: () {
          if (mounted) setState(() {});
        },
        onWorkoutTemplatesChanged: _replaceWorkoutTemplates,
        onSelectedGymChanged: _setGym,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFC7F36B),
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) unawaited(_refreshWorkoutDraft());
        },
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
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
    required this.workoutTemplates,
    required this.onTemplateSaved,
    required this.onTemplateDeleted,
    required this.workoutDraft,
    required this.onDraftChanged,
    required this.onDraftDiscarded,
  });

  final List<WorkoutRecord> history;
  final String? selectedGym;
  final ValueChanged<String> onGymChanged;
  final int weeklyTarget;
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
  final Future<void> Function(DateTime, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final Future<void> Function(SavedWorkoutTemplate) onTemplateSaved;
  final Future<void> Function(SavedWorkoutTemplate) onTemplateDeleted;
  final WorkoutDraftSummary? workoutDraft;
  final Future<void> Function() onDraftChanged;
  final Future<void> Function() onDraftDiscarded;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          const HomeHeader(),
          const SizedBox(height: 24),
          if (workoutDraft != null) ...[
            ActiveWorkoutDraftCard(
              summary: workoutDraft!,
              onResume: () => _openWorkout(context),
            ),
            const SizedBox(height: 14),
          ],
          StartWorkoutCard(
            gymName: selectedGym,
            buttonLabel: workoutDraft == null ? 'トレーニングを始める' : '新しいトレーニングを始める',
            onSelectGym: () async {
              final selected = await showGymPicker(context, selectedGym);
              if (selected != null) onGymChanged(selected);
            },
            onPressed: () async {
              await _startWorkout(context);
            },
          ),
          if (workoutTemplates.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionTitle(title: 'マイメニュー', action: '保存したメニュー'),
            const SizedBox(height: 12),
            SavedMenusCard(
              templates: workoutTemplates,
              onSelected: (template) => _startWorkout(
                context,
                initialWorkout: template.toWorkoutRecord(),
              ),
              onDeleted: onTemplateDeleted,
              onRestored: onTemplateSaved,
            ),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionTitle(title: 'クイックスタート', action: '最近のメニュー'),
            const SizedBox(height: 12),
            RecentMenusCard(
              history: history,
              onSelected: (workout) =>
                  _startWorkout(context, initialWorkout: workout),
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
          LastWorkoutCard(
            workout: history.isEmpty ? null : history.first,
            onTap: history.isEmpty
                ? null
                : () => _openWorkoutDetail(context, history.first),
          ),
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
    if (workoutTemplates.any((template) => template.name == name)) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('同じ名前のメニューがあります'),
          content: Text('「$name」の内容を今回のトレーニングで上書きしますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const Key('overwriteTemplateButton'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('上書き'),
            ),
          ],
        ),
      );
      if (overwrite != true || !context.mounted) return;
    }
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
    if (workout != null) await onWorkoutCompleted(workout);
    await onDraftChanged();
  }

  Future<void> _openWorkoutDetail(
    BuildContext context,
    WorkoutRecord workout,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await Navigator.of(context).push<WorkoutRecord>(
      MaterialPageRoute(
        builder: (_) => WorkoutDetailPage(
          workout: workout,
          selectedGym: selectedGym,
          onWorkoutCompleted: onWorkoutCompleted,
          onWorkoutUpdated: onWorkoutUpdated,
          onWorkoutDeleted: onWorkoutDeleted,
        ),
      ),
    );
    if (deleted != null) {
      _showDeletedWorkoutUndo(messenger, deleted, onWorkoutCompleted);
    }
    await onDraftChanged();
  }

  Future<void> _startWorkout(
    BuildContext context, {
    WorkoutRecord? initialWorkout,
  }) async {
    if (workoutDraft != null) {
      final canStart = await discardDraftBeforeNewWorkout(context);
      if (!canStart || !context.mounted) return;
      await onDraftDiscarded();
    }
    if (context.mounted) {
      await _openWorkout(context, initialWorkout: initialWorkout);
    }
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
                key: Key('recentMenu$index'),
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
    required this.onRestored,
  });

  final List<SavedWorkoutTemplate> templates;
  final ValueChanged<SavedWorkoutTemplate> onSelected;
  final Future<void> Function(SavedWorkoutTemplate) onDeleted;
  final Future<void> Function(SavedWorkoutTemplate) onRestored;

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
                  '${template.exerciseNames.join('・')} ・ ${template.sets.length}セット',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelected(template),
                trailing: IconButton(
                  tooltip: '${template.name}を削除',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await onDeleted(template);
                    if (context.mounted) {
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text('「${template.name}」を削除しました'),
                            action: SnackBarAction(
                              label: '元に戻す',
                              onPressed: () async {
                                await onRestored(template);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('「${template.name}」を元に戻しました'),
                                  ),
                                );
                              },
                            ),
                          ),
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

class SavedMenuManagementPage extends StatefulWidget {
  const SavedMenuManagementPage({
    super.key,
    required this.initialTemplates,
    required this.onChanged,
  });

  final List<SavedWorkoutTemplate> initialTemplates;
  final Future<void> Function(List<SavedWorkoutTemplate>) onChanged;

  @override
  State<SavedMenuManagementPage> createState() =>
      _SavedMenuManagementPageState();
}

class _SavedMenuManagementPageState extends State<SavedMenuManagementPage> {
  late List<SavedWorkoutTemplate> _templates;

  @override
  void initState() {
    super.initState();
    _templates = List<SavedWorkoutTemplate>.from(widget.initialTemplates);
  }

  Future<void> _save(List<SavedWorkoutTemplate> updated) async {
    setState(() => _templates = List<SavedWorkoutTemplate>.from(updated));
    await widget.onChanged(_templates);
  }

  Future<void> _rename(SavedWorkoutTemplate template) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameWorkoutTemplateDialog(
        initialName: template.name,
        reservedNames: _templates
            .where((item) => item.name != template.name)
            .map((item) => item.name)
            .toSet(),
      ),
    );
    if (name == null || name == template.name) return;
    final updated = _templates
        .map(
          (item) => item.name == template.name
              ? SavedWorkoutTemplate(name: name, sets: item.sets)
              : item,
        )
        .toList();
    await _save(updated);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('「$name」に名前を変更しました')));
    }
  }

  Future<void> _delete(SavedWorkoutTemplate template) async {
    final index = _templates.indexOf(template);
    final messenger = ScaffoldMessenger.of(context);
    await _save(_templates.where((item) => item != template).toList());
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「${template.name}」を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              final restored = List<SavedWorkoutTemplate>.from(_templates);
              restored.insert(index.clamp(0, restored.length), template);
              await _save(restored);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text('「${template.name}」を元に戻しました')),
                );
              }
            },
          ),
        ),
      );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final updated = List<SavedWorkoutTemplate>.from(_templates);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    await _save(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('マイメニュー管理')),
      body: _templates.isEmpty
          ? const Center(
              child: Text(
                '保存したマイメニューはありません',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      Icon(Icons.drag_indicator_rounded, size: 18),
                      SizedBox(width: 6),
                      Text(
                        '右端を長押しして並び替え',
                        style: TextStyle(color: Color(0xFF6C746D)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    buildDefaultDragHandles: false,
                    itemCount: _templates.length,
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final template = _templates[index];
                      return Card(
                        key: ValueKey('managedMenu_${template.name}'),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(
                            template.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${template.exerciseNames.join('・')} ・ ${template.sets.length}セット',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _rename(template),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '${template.name}の名前を変更',
                                onPressed: () => _rename(template),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: '${template.name}を削除',
                                onPressed: () => _delete(template),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                              ReorderableDragStartListener(
                                key: Key('reorderMenu$index'),
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _RenameWorkoutTemplateDialog extends StatefulWidget {
  const _RenameWorkoutTemplateDialog({
    required this.initialName,
    required this.reservedNames,
  });

  final String initialName;
  final Set<String> reservedNames;

  @override
  State<_RenameWorkoutTemplateDialog> createState() =>
      _RenameWorkoutTemplateDialogState();
}

class _RenameWorkoutTemplateDialogState
    extends State<_RenameWorkoutTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
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
      title: const Text('メニュー名を変更'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('renameTemplateField'),
          controller: _controller,
          autofocus: true,
          maxLength: 30,
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.isEmpty) return 'メニュー名を入力してください';
            if (widget.reservedNames.any(
              (item) => item.toLowerCase() == name.toLowerCase(),
            )) {
              return '同じ名前のメニューがあります';
            }
            return null;
          },
          decoration: const InputDecoration(labelText: 'メニュー名'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('saveTemplateNameButton'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: const Text('保存'),
        ),
      ],
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
    this.buttonLabel = 'トレーニングを始める',
  });

  final String? gymName;
  final VoidCallback onSelectGym;
  final VoidCallback onPressed;
  final String buttonLabel;

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
              label: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ActiveWorkoutDraftCard extends StatelessWidget {
  const ActiveWorkoutDraftCard({
    super.key,
    required this.summary,
    required this.onResume,
  });

  final WorkoutDraftSummary summary;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('activeWorkoutDraftCard'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: onResume,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFC7F36B),
                child: Icon(Icons.edit_note_rounded),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '入力途中のトレーニング',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.exerciseNames.join('・'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF6C746D)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${workoutDateLabel(summary.date)}・${summary.setCount}セット',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777F78),
                      ),
                    ),
                  ],
                ),
              ),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded),
                  Text(
                    '再開',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
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

DateTime startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

int workoutCountInWeek(List<WorkoutRecord> history, DateTime weekStart) {
  final nextWeek = weekStart.add(const Duration(days: 7));
  return history
      .where(
        (workout) =>
            !workout.date.isBefore(weekStart) &&
            workout.date.isBefore(nextWeek),
      )
      .length;
}

int weeklyGoalStreak(List<WorkoutRecord> history, int target, {DateTime? now}) {
  if (target <= 0) return 0;
  var cursor = startOfWeek(now ?? DateTime.now());
  if (workoutCountInWeek(history, cursor) < target) {
    cursor = cursor.subtract(const Duration(days: 7));
  }

  var streak = 0;
  while (workoutCountInWeek(history, cursor) >= target) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 7));
  }
  return streak;
}

class WeeklySummary extends StatelessWidget {
  const WeeklySummary({super.key, required this.history});

  final List<WorkoutRecord> history;

  @override
  Widget build(BuildContext context) {
    final weekStart = startOfWeek(DateTime.now());
    final nextWeek = weekStart.add(const Duration(days: 7));
    final weekly = history.where(
      (item) => !item.date.isBefore(weekStart) && item.date.isBefore(nextWeek),
    );
    final workoutCount = weekly.length;
    final volume = weekly.fold<double>(
      0,
      (total, workout) => total + workout.volume,
    );
    final historyThroughThisWeek = history
        .where((item) => item.date.isBefore(nextWeek))
        .toList();
    final personalBests = countPersonalBests(historyThroughThisWeek, weekStart);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            StatItem(value: '$workoutCount', unit: '回', label: 'ワークアウト'),
            Container(width: 1, height: 46, color: const Color(0xFFE4E7E1)),
            StatItem(value: formatVolumeKg(volume), unit: 'kg', label: 'ボリューム'),
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

  @override
  Widget build(BuildContext context) {
    final currentWeek = startOfWeek(DateTime.now());
    final count = workoutCountInWeek(history, currentWeek);
    final streak = weeklyGoalStreak(history, target);
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
                streak == 0 ? '今週から開始' : '$streak週連続達成',
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
  const LastWorkoutCard({super.key, required this.workout, this.onTap});

  final WorkoutRecord? workout;
  final VoidCallback? onTap;

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
      key: const Key('lastWorkoutCard'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: onTap,
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
                          '${item.exerciseNames.length}種目・${item.sets.length}セット${!WorkoutUiPreference.workoutDurationEnabled || item.durationLabel.isEmpty ? '' : '・${item.durationLabel}'}',
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

enum MuscleMapPeriod {
  week('1週間', 7),
  month('1ヶ月', 30),
  threeMonths('3ヶ月', 90),
  sixMonths('6ヶ月', 180),
  year('1年', 365);

  const MuscleMapPeriod(this.label, this.days);
  final String label;
  final int days;
}

Map<String, int> bodyPartSetCounts(
  List<WorkoutRecord> history,
  MuscleMapPeriod period, {
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: period.days));
  final counts = <String, int>{};
  for (final workout in history.where((item) => !item.date.isBefore(cutoff))) {
    for (final set in workout.sets.where((item) => item.completed)) {
      counts.update(set.bodyPart, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

class BodyMapPage extends StatefulWidget {
  const BodyMapPage({super.key, required this.history});
  final List<WorkoutRecord> history;
  @override
  State<BodyMapPage> createState() => _BodyMapPageState();
}

class _BodyMapPageState extends State<BodyMapPage> {
  MuscleMapPeriod _period = MuscleMapPeriod.week;
  bool _showBack = false;
  double _tilt = 0;

  @override
  Widget build(BuildContext context) {
    final counts = bodyPartSetCounts(widget.history, _period);
    final maximum = counts.values.fold<int>(1, (a, b) => b > a ? b : a);
    const parts = ['胸', '背中', '脚', '肩', '腕', '腹'];
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: [
          const Text(
            '3D筋肉マップ',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '完了セット数に応じて部位の色が濃くなります',
            style: TextStyle(color: Color(0xFF6C746D)),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: MuscleMapPeriod.values
                  .map(
                    (period) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('musclePeriod${period.name}'),
                        label: Text(period.label),
                        selected: _period == period,
                        onSelected: (_) => setState(() => _period = period),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            key: const Key('muscleModel3D'),
            height: 390,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF101820),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '${_period.label} ・ $totalセット',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('前面')),
                        ButtonSegment(value: true, label: Text('背面')),
                      ],
                      selected: {_showBack},
                      onSelectionChanged: (value) => setState(() {
                        _showBack = value.first;
                        _tilt = 0;
                      }),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) => setState(
                      () => _tilt = (_tilt + details.delta.dx / 180).clamp(
                        -0.7,
                        0.7,
                      ),
                    ),
                    onDoubleTap: () => setState(() => _tilt = 0),
                    child: Center(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.002)
                          ..rotateY(_tilt),
                        child: CustomPaint(
                          size: const Size(210, 315),
                          painter: _MuscleBodyPainter(
                            counts: counts,
                            maximum: maximum,
                            showBack: _showBack,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Text(
                  '左右にドラッグして回転 ・ ダブルタップで正面',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...parts.map((part) {
            final value = counts[part] ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _muscleHeatColor(value, maximum),
                  child: Text(
                    part.substring(0, 1),
                    style: const TextStyle(
                      color: Color(0xFF101820),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                title: Text(
                  part,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: LinearProgressIndicator(
                  value: value / maximum,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: const Color(0xFFE8EBE5),
                  color: _muscleHeatColor(value, maximum),
                ),
                trailing: Text(
                  '$valueセット',
                  key: Key('muscleCount$part'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

Color _muscleHeatColor(int value, int maximum) {
  if (value <= 0) return const Color(0xFFD9DDD7);
  final intensity = (value / maximum).clamp(0.0, 1.0);
  return Color.lerp(
    const Color(0xFFFFD5D5),
    const Color(0xFFE11D2E),
    0.2 + intensity * 0.8,
  )!;
}

class _MuscleBodyPainter extends CustomPainter {
  const _MuscleBodyPainter({
    required this.counts,
    required this.maximum,
    required this.showBack,
  });

  final Map<String, int> counts;
  final int maximum;
  final bool showBack;

  static const _wire = Color(0xFF24F4EE);
  static const _wireDim = Color(0xFF087E8C);
  static const _heat = Color(0xFFFF2638);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 230;
    final scaleY = size.height / 350;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    _paintStage(canvas);
    final body = _bodySilhouette();
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF062B38).withValues(alpha: 0.64)
        ..style = PaintingStyle.fill,
    );

    canvas.save();
    canvas.clipPath(body);
    _paintMuscleDots(canvas, body);
    _paintBodyGrid(canvas);
    canvas.restore();

    final glow = Paint()
      ..color = _wire.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final edge = Paint()
      ..color = _wire.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05;
    canvas.drawPath(body, glow);
    canvas.drawPath(body, edge);
    _paintAnatomyContours(canvas);
    canvas.restore();
  }

  void _paintStage(Canvas canvas) {
    final horizon = Paint()
      ..color = _wire.withValues(alpha: 0.08)
      ..strokeWidth = 0.7;
    for (var y = 250.0; y <= 350; y += 13) {
      canvas.drawLine(Offset(8, y), Offset(222, y), horizon);
    }
    for (var x = 8.0; x <= 222; x += 18) {
      canvas.drawLine(const Offset(115, 238), Offset(x, 350), horizon);
    }
    canvas.drawOval(
      const Rect.fromLTWH(58, 337, 114, 10),
      Paint()..color = Colors.black.withValues(alpha: 0.42),
    );
  }

  Path _bodySilhouette() {
    final body = Path()
      ..addOval(const Rect.fromLTWH(94, 4, 42, 51))
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(105, 48, 20, 23),
          const Radius.circular(7),
        ),
      );

    body
      ..moveTo(99, 57)
      ..cubicTo(90, 61, 78, 63, 70, 72)
      ..cubicTo(65, 83, 66, 105, 72, 125)
      ..cubicTo(77, 142, 85, 157, 89, 176)
      ..lineTo(86, 194)
      ..cubicTo(96, 201, 106, 204, 115, 204)
      ..cubicTo(124, 204, 134, 201, 144, 194)
      ..lineTo(141, 176)
      ..cubicTo(145, 157, 153, 142, 158, 125)
      ..cubicTo(164, 105, 165, 83, 160, 72)
      ..cubicTo(152, 63, 140, 61, 131, 57)
      ..cubicTo(124, 63, 106, 63, 99, 57)
      ..close();

    _addLimb(body, const [
      Offset(72, 70),
      Offset(58, 76),
      Offset(43, 126),
      Offset(57, 132),
      Offset(78, 93),
    ]);
    _addLimb(body, const [
      Offset(43, 123),
      Offset(31, 199),
      Offset(46, 202),
      Offset(59, 130),
    ]);
    body.addOval(const Rect.fromLTWH(27, 195, 20, 31));
    _addLimb(body, const [
      Offset(158, 70),
      Offset(172, 76),
      Offset(187, 126),
      Offset(173, 132),
      Offset(152, 93),
    ]);
    _addLimb(body, const [
      Offset(187, 123),
      Offset(199, 199),
      Offset(184, 202),
      Offset(171, 130),
    ]);
    body.addOval(const Rect.fromLTWH(183, 195, 20, 31));

    _addLimb(body, const [
      Offset(88, 183),
      Offset(114, 188),
      Offset(108, 256),
      Offset(97, 276),
      Offset(77, 271),
      Offset(80, 228),
    ]);
    _addLimb(body, const [
      Offset(77, 263),
      Offset(99, 266),
      Offset(93, 326),
      Offset(75, 327),
      Offset(69, 294),
    ]);
    _addLimb(body, const [
      Offset(142, 183),
      Offset(116, 188),
      Offset(122, 256),
      Offset(133, 276),
      Offset(153, 271),
      Offset(150, 228),
    ]);
    _addLimb(body, const [
      Offset(153, 263),
      Offset(131, 266),
      Offset(137, 326),
      Offset(155, 327),
      Offset(161, 294),
    ]);
    _addLimb(body, const [
      Offset(75, 320),
      Offset(94, 320),
      Offset(98, 339),
      Offset(65, 339),
      Offset(66, 331),
    ]);
    _addLimb(body, const [
      Offset(155, 320),
      Offset(136, 320),
      Offset(132, 339),
      Offset(165, 339),
      Offset(164, 331),
    ]);
    return body;
  }

  void _addLimb(Path path, List<Offset> points) {
    path.moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
  }

  void _paintBodyGrid(Canvas canvas) {
    final fine = Paint()
      ..color = _wire.withValues(alpha: 0.54)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55;
    final strong = Paint()
      ..color = _wire.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.78;

    for (var y = 7.0; y < 340; y += 5.5) {
      final bend = math.sin(y / 19) * 3.2;
      final path = Path()
        ..moveTo(20, y)
        ..quadraticBezierTo(115 + bend, y + 2.6, 210, y);
      canvas.drawPath(path, ((y / 5.5).round().isEven) ? strong : fine);
    }
    for (var x = 30.0; x <= 200; x += 6.5) {
      final distance = (x - 115) / 100;
      final path = Path()
        ..moveTo(x, 0)
        ..cubicTo(
          x + distance * 8,
          92,
          x - distance * 7,
          246,
          x + distance * 5,
          345,
        );
      canvas.drawPath(path, ((x / 6.5).round().isEven) ? strong : fine);
    }

    final face = Paint()
      ..color = _wire.withValues(alpha: 0.84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65;
    for (var i = 1; i < 7; i++) {
      final top = 5 + i * 6.5;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(115, top),
          width: 38 - (top - 28).abs() * 0.32,
          height: 6.5,
        ),
        face,
      );
    }
    for (final dx in [-13.0, -7.0, 0.0, 7.0, 13.0]) {
      final path = Path()
        ..moveTo(115 + dx * 0.35, 5)
        ..quadraticBezierTo(115 + dx * 1.2, 29, 115 + dx * 0.55, 54);
      canvas.drawPath(path, face);
    }
  }

  void _paintMuscleDots(Canvas canvas, Path body) {
    final regions = <String, List<Path>>{
      '肩': [
        Path()..addOval(const Rect.fromLTWH(65, 65, 31, 34)),
        Path()..addOval(const Rect.fromLTWH(134, 65, 31, 34)),
      ],
      '腕': [
        Path()..addOval(const Rect.fromLTWH(49, 85, 24, 49)),
        Path()..addOval(const Rect.fromLTWH(157, 85, 24, 49)),
        Path()..addOval(const Rect.fromLTWH(32, 133, 20, 67)),
        Path()..addOval(const Rect.fromLTWH(178, 133, 20, 67)),
      ],
      '脚': [
        Path()..addOval(const Rect.fromLTWH(78, 190, 35, 85)),
        Path()..addOval(const Rect.fromLTWH(117, 190, 35, 85)),
        Path()..addOval(const Rect.fromLTWH(70, 267, 29, 61)),
        Path()..addOval(const Rect.fromLTWH(131, 267, 29, 61)),
      ],
      if (showBack)
        '背中': [
          Path()
            ..moveTo(83, 72)
            ..lineTo(147, 72)
            ..lineTo(139, 154)
            ..lineTo(115, 178)
            ..lineTo(91, 154)
            ..close(),
        ]
      else
        '胸': [
          Path()..addOval(const Rect.fromLTWH(80, 74, 34, 52)),
          Path()..addOval(const Rect.fromLTWH(116, 74, 34, 52)),
        ],
      '腹': [
        Path()..addRRect(const RRect.fromLTRBXY(96, 126, 134, 190, 13, 13)),
      ],
    };

    for (final entry in regions.entries) {
      final value = counts[entry.key] ?? 0;
      if (value <= 0) continue;
      final intensity = (value / maximum).clamp(0.0, 1.0);
      final spacing = 7.5 - intensity * 3.2;
      final dotPaint = Paint()
        ..color = _heat.withValues(alpha: 0.48 + intensity * 0.46)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5 + intensity);
      for (final region in entry.value) {
        final bounds = region.getBounds();
        for (var y = bounds.top; y <= bounds.bottom; y += spacing) {
          for (var x = bounds.left; x <= bounds.right; x += spacing) {
            final staggeredX =
                x + ((y / spacing).round().isEven ? 0 : spacing / 2);
            final point = Offset(staggeredX, y);
            if (region.contains(point) && body.contains(point)) {
              canvas.drawCircle(point, 0.85 + intensity * 0.65, dotPaint);
            }
          }
        }
      }
    }
  }

  void _paintAnatomyContours(Canvas canvas) {
    final contour = Paint()
      ..color = _wireDim.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final bright = Paint()
      ..color = _wire.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.72;

    canvas.drawLine(const Offset(115, 58), const Offset(115, 202), contour);
    canvas.drawArc(
      const Rect.fromLTWH(79, 67, 72, 39),
      0.1,
      2.95,
      false,
      bright,
    );
    canvas.drawArc(
      const Rect.fromLTWH(84, 111, 62, 68),
      0.15,
      2.85,
      false,
      contour,
    );
    canvas.drawArc(
      const Rect.fromLTWH(83, 177, 64, 28),
      0,
      math.pi,
      false,
      bright,
    );
    canvas.drawLine(const Offset(114, 202), const Offset(108, 257), contour);
    canvas.drawLine(const Offset(116, 202), const Offset(122, 257), contour);
    canvas.drawOval(const Rect.fromLTWH(105, 23, 8, 4), bright);
    canvas.drawOval(const Rect.fromLTWH(117, 23, 8, 4), bright);
    canvas.drawArc(
      const Rect.fromLTWH(107, 34, 16, 8),
      0,
      math.pi,
      false,
      bright,
    );
  }

  @override
  bool shouldRepaint(covariant _MuscleBodyPainter old) =>
      old.counts != counts ||
      old.maximum != maximum ||
      old.showBack != showBack;
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
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
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

  void _showCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
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
          if (!isCurrentMonth)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                key: const Key('historyCurrentMonthButton'),
                onPressed: _showCurrentMonth,
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('今月に戻る'),
              ),
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
                    value: formatVolumeKg(volume),
                    unit: 'kg',
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _selectedDay == null ? 'この月の記録はありません' : 'この日の記録はありません',
                  style: const TextStyle(color: Color(0xFF6C746D)),
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
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
  final Future<void> Function(DateTime, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  State<HistorySearchPage> createState() => _HistorySearchPageState();
}

bool workoutMatchesQuery(WorkoutRecord workout, String query) {
  final normalized = _normalizeWorkoutSearchText(query);
  if (normalized.isEmpty) return true;
  final date = workout.date;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final searchable = [
    ...workout.exerciseNames,
    ...workout.bodyParts,
    workout.gymName ?? '',
    workout.note,
    '${date.year}年${date.month}月${date.day}日',
    '${date.year}/${date.month}/${date.day}',
    '${date.year}-$month-$day',
    '${date.month}/${date.day}',
  ].join(' ');
  return _normalizeWorkoutSearchText(searchable).contains(normalized);
}

String _normalizeWorkoutSearchText(String value) {
  const fullWidthDigits = '０１２３４５６７８９';
  var normalized = value.trim().toLowerCase();
  for (var index = 0; index < fullWidthDigits.length; index++) {
    normalized = normalized.replaceAll(fullWidthDigits[index], '$index');
  }
  return normalized
      .replaceAll('／', '/')
      .replaceAll('・', '/')
      .replaceAll('-', '/');
}

class _HistorySearchPageState extends State<HistorySearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.history
        .where((workout) => workoutMatchesQuery(workout, _query))
        .toList();
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
              key: const Key('historySearchField'),
              controller: _searchController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: '種目・部位・場所・メモ・日付',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '検索をクリア',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _query.isEmpty
                    ? '全${results.length}件'
                    : '${results.length}件の記録',
                key: const Key('historySearchResultCount'),
                style: const TextStyle(
                  color: Color(0xFF6C746D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
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
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
  final Future<void> Function(DateTime, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final deleted = await Navigator.of(context).push<WorkoutRecord>(
            MaterialPageRoute<WorkoutRecord>(
              builder: (_) => WorkoutDetailPage(
                workout: workout,
                selectedGym: selectedGym,
                onWorkoutCompleted: onWorkoutCompleted,
                onWorkoutUpdated: onWorkoutUpdated,
                onWorkoutDeleted: onWorkoutDeleted,
              ),
            ),
          );
          if (deleted != null) {
            _showDeletedWorkoutUndo(messenger, deleted, onWorkoutCompleted);
          }
        },
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
                      '${workout.sets.length}セット ・ ${formatVolumeKg(workout.volume)} kg${!WorkoutUiPreference.workoutDurationEnabled || workout.durationLabel.isEmpty ? '' : ' ・ ${workout.durationLabel}'}',
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

void _showDeletedWorkoutUndo(
  ScaffoldMessengerState messenger,
  WorkoutRecord workout,
  Future<void> Function(WorkoutRecord) onRestore,
) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('トレーニング記録を削除しました'),
        action: SnackBarAction(
          label: '元に戻す',
          onPressed: () async {
            await onRestore(workout);
            messenger.showSnackBar(
              const SnackBar(content: Text('トレーニング記録を元に戻しました')),
            );
          },
        ),
      ),
    );
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
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
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
            '${workout.exerciseNames.length}種目 ・ ${workout.sets.length}セット ・ ${formatVolumeKg(workout.volume)} kg${!WorkoutUiPreference.workoutDurationEnabled || workout.durationLabel.isEmpty ? '' : ' ・ ${workout.durationLabel}'}',
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
              key: const Key('repeatWorkoutButton'),
              onPressed: () async {
                final canStart = await discardDraftBeforeNewWorkout(context);
                if (!canStart || !context.mounted) return;
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
                if (repeated != null) await onWorkoutCompleted(repeated);
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
        content: const Text('削除後も直後なら元に戻せます。'),
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
      Navigator.pop(context, workout);
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
  final _formKey = GlobalKey<FormState>();
  late DateTime _startedAt;
  late DateTime _workoutDate;
  Timer? _timer;
  Timer? _restTimer;
  Duration _elapsed = Duration.zero;
  int _restRemaining = 0;
  int _inputRevision = 0;
  bool _allowPop = false;
  bool _leaveDialogOpen = false;
  bool _workoutTimerStopped = false;
  late final TextEditingController _noteController;
  late final List<WorkoutExercise> _exercises;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _workoutDate = widget.isEditing
        ? widget.initialWorkout!.date
        : DateTime.now();
    _exercises = widget.initialWorkout == null
        ? []
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
    } else if (WorkoutUiPreference.workoutTimerEnabled ||
        WorkoutUiPreference.workoutDurationEnabled) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && !_workoutTimerStopped) {
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

  Duration _stopWorkoutTimer({bool keepStopped = false}) {
    if (!widget.isEditing && _timer != null) {
      _elapsed = DateTime.now().difference(_startedAt);
      _timer?.cancel();
      _timer = null;
    }
    if (keepStopped) _workoutTimerStopped = true;
    _restTimer?.cancel();
    _restTimer = null;
    _restRemaining = 0;
    return _elapsed;
  }

  void _addSet(int exerciseIndex) {
    setState(() {
      final sets = _exercises[exerciseIndex].sets;
      final previous = sets.isEmpty ? null : sets.last;
      sets.add(
        WorkoutSet(weight: previous?.weight ?? 0, reps: previous?.reps ?? 0),
      );
    });
    unawaited(_saveDraft());
  }

  void _removeSet(int exerciseIndex, int setIndex) {
    final exercise = _exercises[exerciseIndex];
    final removed = exercise.sets[setIndex];
    setState(() => exercise.sets.removeAt(setIndex));
    unawaited(_saveDraft());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${exercise.name}の${setIndex + 1}セット目を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () {
              if (!mounted || !_exercises.contains(exercise)) return;
              setState(() {
                final restoreIndex = setIndex > exercise.sets.length
                    ? exercise.sets.length
                    : setIndex;
                exercise.sets.insert(restoreIndex, removed);
              });
              unawaited(_saveDraft());
            },
          ),
        ),
      );
  }

  void _removeExercise(int exerciseIndex) {
    final removed = _exercises[exerciseIndex];
    setState(() {
      _exercises.removeAt(exerciseIndex);
      if (_exercises.isEmpty) {
        _stopWorkoutTimer(keepStopped: true);
      }
    });
    unawaited(_saveDraft());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${removed.name}を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () {
              if (!mounted || _exercises.contains(removed)) return;
              setState(() {
                final restoreIndex = exerciseIndex > _exercises.length
                    ? _exercises.length
                    : exerciseIndex;
                _exercises.insert(restoreIndex, removed);
              });
              unawaited(_saveDraft());
            },
          ),
        ),
      );
  }

  void _toggleSet(int exerciseIndex, int setIndex) {
    final set = _exercises[exerciseIndex].sets[setIndex];
    setState(() => set.completed = !set.completed);
    unawaited(_saveDraft());
    if (set.completed) HapticFeedback.mediumImpact();
    if (set.completed &&
        !widget.isEditing &&
        WorkoutUiPreference.completionCheckEnabled &&
        RestTimerPreference.enabled) {
      _startRestTimer();
    }
  }

  void _applyPreviousSets(int exerciseIndex, List<RecordedSet> previousSets) {
    if (previousSets.isEmpty) return;
    setState(() {
      _inputRevision++;
      final sets = _exercises[exerciseIndex].sets;
      sets
        ..clear()
        ..addAll(
          previousSets.map(
            (set) => WorkoutSet(weight: set.weight, reps: set.reps),
          ),
        );
    });
    unawaited(_saveDraft());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_exercises[exerciseIndex].name}に前回の記録を反映しました')),
    );
  }

  void _setAllSetsCompleted(int exerciseIndex, bool completed) {
    setState(() {
      for (final set in _exercises[exerciseIndex].sets) {
        set.completed = completed;
      }
    });
    if (completed) HapticFeedback.mediumImpact();
    unawaited(_saveDraft());
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
    final encoded = preferences.getString(activeWorkoutDraftStorageKey);
    if (encoded == null || !mounted) return;
    try {
      final draft = jsonDecode(encoded) as Map<String, dynamic>;
      final exercises = (draft['exercises'] as List<dynamic>)
          .map((item) => _exerciseFromDraft(item as Map<String, dynamic>))
          .toList();
      final timerStopped = draft['timerStopped'] as bool? ?? false;
      if (exercises.isEmpty) {
        await preferences.remove(activeWorkoutDraftStorageKey);
        return;
      }
      setState(() {
        _inputRevision++;
        final savedElapsedSeconds = (draft['elapsedSeconds'] as num?)?.toInt();
        if (savedElapsedSeconds != null) {
          _elapsed = Duration(seconds: savedElapsedSeconds);
          _startedAt = DateTime.now().subtract(_elapsed);
        } else {
          final savedStartedAt = draft['startedAt'] as String?;
          if (savedStartedAt != null) {
            _startedAt = DateTime.tryParse(savedStartedAt) ?? _startedAt;
            _elapsed = DateTime.now().difference(_startedAt);
          }
        }
        _exercises
          ..clear()
          ..addAll(exercises);
        _noteController.text = draft['note'] as String? ?? '';
        final savedDate = draft['date'] as String?;
        if (savedDate != null) _workoutDate = DateTime.parse(savedDate);
      });
      if (timerStopped) {
        _stopWorkoutTimer(keepStopped: true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('入力途中のトレーニングを再開しました')));
      }
    } catch (_) {
      await preferences.remove(activeWorkoutDraftStorageKey);
    }
  }

  Future<void> _saveDraft() async {
    if (widget.isEditing) return;
    final encodedDraft = jsonEncode({
      'startedAt': _startedAt.toIso8601String(),
      'elapsedSeconds': _elapsed.inSeconds,
      'timerStopped': _workoutTimerStopped,
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
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(activeWorkoutDraftStorageKey, encodedDraft);
  }

  Future<void> _clearDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(activeWorkoutDraftStorageKey);
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
    if (_leaveDialogOpen) return;
    _leaveDialogOpen = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.isEditing ? '修正を中止しますか？' : 'トレーニングを中断しますか？'),
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
            child: Text(widget.isEditing ? '戻る' : '中断する'),
          ),
        ],
      ),
    );
    _leaveDialogOpen = false;
    if (leave == true) _exitWorkout();
  }

  void _exitWorkout([WorkoutRecord? workout]) {
    if (!mounted) return;
    if (!widget.isEditing) {
      _stopWorkoutTimer();
      if (workout == null) unawaited(_saveDraft());
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(workout);
    });
  }

  Future<void> _deleteWorkoutDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('記録をすべて削除しますか？'),
        content: const Text('入力中の種目・セット・メモを削除します。この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirmDeleteWorkoutDraftButton'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _stopWorkoutTimer(keepStopped: true);
    await _clearDraft();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<WorkoutRecord>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
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
                key: const Key('workoutElapsedLabel'),
                widget.isEditing
                    ? '${!WorkoutUiPreference.workoutDurationEnabled || widget.initialWorkout!.durationLabel.isEmpty ? '記録済み' : widget.initialWorkout!.durationLabel} ・ ${widget.gymName ?? '店舗未選択'}'
                    : WorkoutUiPreference.workoutTimerEnabled
                    ? '$_elapsedLabel ・ ${widget.gymName ?? '店舗未選択'}'
                    : widget.gymName ?? '店舗未選択',
                style: const TextStyle(fontSize: 11, color: Color(0xFF777F78)),
              ),
            ],
          ),
          actions: [
            if (!widget.isEditing)
              IconButton(
                key: const Key('deleteWorkoutDraftButton'),
                tooltip: '記録を全削除',
                onPressed: _deleteWorkoutDraft,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
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
                      const Icon(
                        Icons.timer_outlined,
                        color: Color(0xFFC7F36B),
                      ),
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
              if (_exercises.isEmpty) ...[
                Container(
                  key: const Key('emptyWorkoutExercises'),
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE0E4DE)),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 34,
                        color: Color(0xFF777F78),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '種目はまだありません',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '下の「種目を追加」から選んでください',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF777F78)),
                      ),
                    ],
                  ),
                ),
              ],
              ...List.generate(
                _exercises.length,
                (exerciseIndex) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ExerciseInputCard(
                    key: ValueKey('exercise_${_inputRevision}_$exerciseIndex'),
                    exerciseIndex: exerciseIndex,
                    exercise: _exercises[exerciseIndex],
                    history: widget.history,
                    onAddSet: () => _addSet(exerciseIndex),
                    onRemoveSet: (setIndex) =>
                        _removeSet(exerciseIndex, setIndex),
                    onRemove: () => _removeExercise(exerciseIndex),
                    onToggleSet: (setIndex) =>
                        _toggleSet(exerciseIndex, setIndex),
                    onApplyPrevious: (sets) =>
                        _applyPreviousSets(exerciseIndex, sets),
                    onSetAllCompleted: (completed) =>
                        _setAllSetsCompleted(exerciseIndex, completed),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
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
      ),
    );
  }

  void _completeWorkout() {
    _formKey.currentState?.save();
    final completedSets = <RecordedSet>[
      for (final exercise in _exercises)
        for (final set in exercise.sets)
          if (!WorkoutUiPreference.completionCheckEnabled || set.completed)
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
    final finalElapsed = _stopWorkoutTimer();
    final personalBests = _personalBestExercises(completedSets);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
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
                    : WorkoutUiPreference.workoutDurationEnabled
                    ? finalElapsed.inSeconds
                    : 0,
                gymName: widget.gymName,
                note: _noteController.text.trim(),
              );
              if (!widget.isEditing) await _clearDraft();
              if (!dialogContext.mounted || !mounted) return;
              Navigator.of(dialogContext).pop();
              _exitWorkout(record);
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
    final previousSets = latestSetsForExercise(widget.history, template.name);
    if (previousSets.isNotEmpty) {
      return WorkoutExercise(
        name: template.name,
        bodyPart: template.bodyPart,
        equipment: template.equipment,
        sets: previousSets
            .map((set) => WorkoutSet(weight: set.weight, reps: set.reps))
            .toList(),
      );
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

  static SavedWorkoutTemplate? tryFromJson(Object? source) {
    if (source is! Map<String, dynamic>) return null;
    try {
      final template = SavedWorkoutTemplate.fromJson(source);
      if (template.name.trim().isEmpty || template.sets.isEmpty) return null;
      return template;
    } catch (_) {
      return null;
    }
  }

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
      return decodeWorkoutTemplates(jsonDecode(encoded));
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
    this.customGyms = const [],
    this.selectedGym,
    this.weeklyTarget,
    this.restTimerEnabled,
    this.restTimerSeconds,
    this.completionCheckEnabled,
    this.workoutTimerEnabled,
    this.workoutDurationEnabled,
  });

  final List<WorkoutRecord> workouts;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final List<ExerciseTemplate> customExercises;
  final List<String> customGyms;
  final String? selectedGym;
  final int? weeklyTarget;
  final bool? restTimerEnabled;
  final int? restTimerSeconds;
  final bool? completionCheckEnabled;
  final bool? workoutTimerEnabled;
  final bool? workoutDurationEnabled;

  factory MuscleMemoryBackup.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int?;
    if (json['app'] != 'MuscleMemory' || (version != 1 && version != 2)) {
      throw const FormatException('Unsupported Muscle Memory backup');
    }
    final settings = json['settings'] as Map<String, dynamic>? ?? const {};
    return MuscleMemoryBackup(
      workouts: decodeWorkoutItems(json['workouts']),
      workoutTemplates: version == 1
          ? const []
          : decodeWorkoutTemplates(json['workoutTemplates']),
      customExercises: version == 1
          ? const []
          : decodeExerciseTemplates(json['customExercises']),
      customGyms: version == 1
          ? const []
          : decodeCustomGyms(json['customGyms']),
      selectedGym: settings['selectedGym'] as String?,
      weeklyTarget: settings['weeklyTarget'] as int?,
      restTimerEnabled: settings['restTimerEnabled'] as bool?,
      restTimerSeconds: settings['restTimerSeconds'] as int?,
      completionCheckEnabled: settings['completionCheckEnabled'] as bool?,
      workoutTimerEnabled: settings['workoutTimerEnabled'] as bool?,
      workoutDurationEnabled: settings['workoutDurationEnabled'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'app': 'MuscleMemory',
    'version': 2,
    'exportedAt': DateTime.now().toIso8601String(),
    'workouts': workouts.map((item) => item.toJson()).toList(),
    'workoutTemplates': workoutTemplates.map((item) => item.toJson()).toList(),
    'customExercises': customExercises.map((item) => item.toJson()).toList(),
    'customGyms': customGyms,
    'settings': {
      'selectedGym': selectedGym,
      'weeklyTarget': weeklyTarget,
      'restTimerEnabled': restTimerEnabled,
      'restTimerSeconds': restTimerSeconds,
      'completionCheckEnabled': completionCheckEnabled,
      'workoutTimerEnabled': workoutTimerEnabled,
      'workoutDurationEnabled': workoutDurationEnabled,
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

  static ExerciseTemplate? tryFromJson(Object? source) {
    if (source is! Map<String, dynamic>) return null;
    try {
      final exercise = ExerciseTemplate.fromJson(source);
      if (exercise.name.trim().isEmpty || exercise.bodyPart.trim().isEmpty) {
        return null;
      }
      return exercise;
    } catch (_) {
      return null;
    }
  }

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
      exercises = decodeExerciseTemplates(jsonDecode(encoded));
    } catch (_) {
      exercises = [];
    }
  }

  static Future<bool> add(ExerciseTemplate exercise) async {
    if (containsName(exercise.name)) return false;
    await replaceAll([...exercises, exercise]);
    return true;
  }

  static bool containsName(String name, {String? excludingName}) {
    final normalized = name.trim().toLowerCase();
    return exerciseTemplates.any(
          (item) => item.name.toLowerCase() == normalized,
        ) ||
        exercises.any(
          (item) =>
              item.name != excludingName &&
              item.name.toLowerCase() == normalized,
        );
  }

  static Future<bool> update(
    String originalName,
    ExerciseTemplate exercise,
  ) async {
    if (containsName(exercise.name, excludingName: originalName)) return false;
    final updated = exercises
        .map((item) => item.name == originalName ? exercise : item)
        .toList();
    if (!exercises.any((item) => item.name == originalName)) return false;
    await replaceAll(updated);
    return true;
  }

  static Future<void> remove(ExerciseTemplate exercise) async {
    await replaceAll(
      exercises.where((item) => item.name != exercise.name).toList(),
    );
  }

  static Future<void> replaceAll(List<ExerciseTemplate> updated) async {
    final unique = <String, ExerciseTemplate>{};
    for (final exercise in updated) {
      final name = exercise.name.trim();
      if (name.isEmpty ||
          exerciseTemplates.any(
            (item) => item.name.toLowerCase() == name.toLowerCase(),
          )) {
        continue;
      }
      unique.putIfAbsent(
        name.toLowerCase(),
        () => ExerciseTemplate(
          name: name,
          bodyPart: exercise.bodyPart,
          equipment: exercise.equipment,
          startWeight: exercise.startWeight,
          startReps: exercise.startReps,
        ),
      );
    }
    exercises = unique.values.toList();
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
  ExerciseTemplate(
    name: 'トレッドミル',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
  ),
  ExerciseTemplate(
    name: 'エアロバイク',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
  ),
  ExerciseTemplate(
    name: 'クロストレーナー',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
  ),
  ExerciseTemplate(
    name: 'ステアクライマー',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
  ),
  ExerciseTemplate(
    name: 'ローイングマシン',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
  ),
];

class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({super.key, required this.existingNames});

  final Set<String> existingNames;

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  static const _categories = ['胸', '背中', '肩', '腕', '脚', '腹', '有酸素'];
  String _query = '';
  String? _selectedCategory;

  String _categoryLabel(String category) => category == '腹' ? '腹筋' : category;

  IconData _categoryIcon(String category) => switch (category) {
    '胸' => Icons.favorite_outline_rounded,
    '背中' => Icons.accessibility_new_rounded,
    '肩' => Icons.expand_rounded,
    '腕' => Icons.fitness_center_rounded,
    '脚' => Icons.directions_run_rounded,
    '腹' => Icons.grid_view_rounded,
    _ => Icons.monitor_heart_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final allExercises = [
      ...exerciseTemplates,
      ...CustomExercisePreference.exercises,
    ];
    final filtered = allExercises.where((template) {
      final query = _query.toLowerCase();
      return template.bodyPart == _selectedCategory &&
          (template.name.toLowerCase().contains(query) ||
              template.bodyPart.contains(query) ||
              template.equipment.toLowerCase().contains(query));
    }).toList();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  if (_selectedCategory != null)
                    IconButton(
                      key: const Key('backToExerciseCategories'),
                      onPressed: () => setState(() {
                        _selectedCategory = null;
                        _query = '';
                      }),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Text(
                    _selectedCategory == null
                        ? '部位・カテゴリを選択'
                        : '${_categoryLabel(_selectedCategory!)}の種目',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_selectedCategory != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('exerciseSearchField'),
                autofocus: false,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: '種目名・器具で検索',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                if (_selectedCategory == null) ...[
                  ..._categories.map((category) {
                    final count = allExercises
                        .where((exercise) => exercise.bodyPart == category)
                        .length;
                    return Card(
                      child: ListTile(
                        key: Key('exerciseCategory$category'),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFC7F36B),
                          child: Icon(_categoryIcon(category)),
                        ),
                        title: Text(
                          _categoryLabel(category),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text('$count種目'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            setState(() => _selectedCategory = category),
                      ),
                    );
                  }),
                  const Divider(),
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
                ] else
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
    final created = await showDialog<ExerciseTemplate>(
      context: context,
      builder: (_) =>
          _ExerciseEditorDialog(additionalReservedNames: widget.existingNames),
    );
    if (created != null) {
      final added = await CustomExercisePreference.add(created);
      if (mounted && added) Navigator.pop(context, created);
    }
  }
}

class CustomExerciseManagementPage extends StatefulWidget {
  const CustomExerciseManagementPage({super.key});

  @override
  State<CustomExerciseManagementPage> createState() =>
      _CustomExerciseManagementPageState();
}

class _CustomExerciseManagementPageState
    extends State<CustomExerciseManagementPage> {
  Future<void> _addExercise() async {
    final exercise = await showDialog<ExerciseTemplate>(
      context: context,
      builder: (_) => const _ExerciseEditorDialog(),
    );
    if (exercise == null) return;
    final added = await CustomExercisePreference.add(exercise);
    if (mounted && added) setState(() {});
  }

  Future<void> _editExercise(ExerciseTemplate exercise) async {
    final updated = await showDialog<ExerciseTemplate>(
      context: context,
      builder: (_) => _ExerciseEditorDialog(initial: exercise),
    );
    if (updated == null) return;
    final saved = await CustomExercisePreference.update(exercise.name, updated);
    if (mounted && saved) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('「${updated.name}」を更新しました')));
    }
  }

  Future<void> _deleteExercise(ExerciseTemplate exercise) async {
    final messenger = ScaffoldMessenger.of(context);
    await CustomExercisePreference.remove(exercise);
    if (!mounted) return;
    setState(() {});
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「${exercise.name}」を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              final restored = await CustomExercisePreference.add(exercise);
              if (!mounted || !restored) return;
              setState(() {});
              messenger.showSnackBar(
                SnackBar(content: Text('「${exercise.name}」を元に戻しました')),
              );
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final exercises = CustomExercisePreference.exercises;
    return Scaffold(
      appBar: AppBar(
        title: const Text('カスタム種目'),
        actions: [
          IconButton(
            key: const Key('addCustomExerciseButton'),
            tooltip: 'カスタム種目を追加',
            onPressed: _addExercise,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: exercises.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fitness_center_rounded,
                      size: 48,
                      color: Color(0xFF777F78),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'カスタム種目はまだありません',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('種目を作る'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: exercises.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final exercise = exercises[index];
                return Card(
                  key: Key('customExercise$index'),
                  child: ListTile(
                    title: Text(
                      exercise.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${exercise.bodyPart} ・ ${exercise.equipment} ・ ${formatWeight(exercise.startWeight)}kg × ${exercise.startReps}回',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '${exercise.name}を編集',
                          onPressed: () => _editExercise(exercise),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '${exercise.name}を削除',
                          onPressed: () => _deleteExercise(exercise),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ExerciseEditorDialog extends StatefulWidget {
  const _ExerciseEditorDialog({
    this.initial,
    this.additionalReservedNames = const {},
  });

  final ExerciseTemplate? initial;
  final Set<String> additionalReservedNames;

  @override
  State<_ExerciseEditorDialog> createState() => _ExerciseEditorDialogState();
}

class _ExerciseEditorDialogState extends State<_ExerciseEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late String _bodyPart;
  late String _equipment;

  static const _bodyParts = ['胸', '背中', '脚', '肩', '腕', '腹', '有酸素'];
  static const _equipmentOptions = [
    'フリーウェイト',
    'ダンベル',
    'マシン',
    'ケーブル',
    '自重',
    'カスタム',
    'その他',
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _weightController = TextEditingController(
      text: formatWeight(initial?.startWeight ?? 10),
    );
    _repsController = TextEditingController(
      text: (initial?.startReps ?? 10).toString(),
    );
    _bodyPart = initial?.bodyPart ?? '胸';
    _equipment = initial == null
        ? 'マシン'
        : _equipmentOptions.contains(initial.equipment)
        ? initial.equipment
        : 'その他';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return '種目名を入力してください';
    final isAdditionalDuplicate = widget.additionalReservedNames.any(
      (item) =>
          item != widget.initial?.name &&
          item.toLowerCase() == name.toLowerCase(),
    );
    if (isAdditionalDuplicate ||
        CustomExercisePreference.containsName(
          name,
          excludingName: widget.initial?.name,
        )) {
      return '同じ名前の種目があります';
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ExerciseTemplate(
        name: _nameController.text.trim(),
        bodyPart: _bodyPart,
        equipment: _equipment,
        startWeight: double.parse(_weightController.text),
        startReps: int.parse(_repsController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新しい種目' : 'カスタム種目を編集'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('customExerciseNameField'),
                controller: _nameController,
                autofocus: true,
                maxLength: 40,
                validator: _validateName,
                decoration: const InputDecoration(labelText: '種目名'),
              ),
              DropdownButtonFormField<String>(
                key: const Key('customExerciseBodyPartField'),
                initialValue: _bodyPart,
                decoration: const InputDecoration(labelText: '鍛える部位'),
                items: _bodyParts
                    .map(
                      (part) =>
                          DropdownMenuItem(value: part, child: Text(part)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _bodyPart = value!),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const Key('customExerciseEquipmentField'),
                initialValue: _equipment,
                decoration: const InputDecoration(labelText: '器具'),
                items: _equipmentOptions
                    .map(
                      (equipment) => DropdownMenuItem(
                        value: equipment,
                        child: Text(equipment),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _equipment = value!),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('customExerciseWeightField'),
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        final weight = double.tryParse(value ?? '');
                        return weight == null || weight < 0 ? '0以上で入力' : null;
                      },
                      decoration: const InputDecoration(labelText: '初期重量 kg'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const Key('customExerciseRepsField'),
                      controller: _repsController,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final reps = int.tryParse(value ?? '');
                        return reps == null || reps < 1 ? '1以上で入力' : null;
                      },
                      decoration: const InputDecoration(labelText: '初期回数'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('saveCustomExerciseButton'),
          onPressed: _save,
          child: Text(widget.initial == null ? '追加' : '保存'),
        ),
      ],
    );
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
    required this.onRemoveSet,
    required this.onRemove,
    required this.onToggleSet,
    required this.onApplyPrevious,
    required this.onSetAllCompleted,
    required this.onValuesChanged,
  });

  final int exerciseIndex;
  final WorkoutExercise exercise;
  final List<WorkoutRecord> history;
  final VoidCallback onAddSet;
  final ValueChanged<int> onRemoveSet;
  final VoidCallback? onRemove;
  final ValueChanged<int> onToggleSet;
  final ValueChanged<List<RecordedSet>> onApplyPrevious;
  final ValueChanged<bool> onSetAllCompleted;
  final VoidCallback onValuesChanged;

  @override
  Widget build(BuildContext context) {
    final previousSets = latestSetsForExercise(history, exercise.name);
    final completedCount = exercise.sets.where((set) => set.completed).length;
    final allCompleted = completedCount == exercise.sets.length;
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
                if (previousSets.isNotEmpty)
                  TextButton(
                    key: Key('applyPrevious$exerciseIndex'),
                    onPressed: () => onApplyPrevious(previousSets),
                    child: const Text('反映'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (WorkoutUiPreference.completionCheckEnabled)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '完了 $completedCount / ${exercise.sets.length}',
                    style: const TextStyle(
                      color: Color(0xFF6C746D),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (exercise.sets.isNotEmpty)
                  TextButton.icon(
                    key: Key('toggleAllSets$exerciseIndex'),
                    onPressed: () => onSetAllCompleted(!allCompleted),
                    icon: Icon(
                      allCompleted
                          ? Icons.remove_done_rounded
                          : Icons.done_all_rounded,
                      size: 18,
                    ),
                    label: Text(allCompleted ? 'すべて解除' : 'すべて完了'),
                  ),
              ],
            ),
          SetHeader(
            showCompletionCheck: WorkoutUiPreference.completionCheckEnabled,
          ),
          const SizedBox(height: 8),
          ...List.generate(exercise.sets.length, (setIndex) {
            final set = exercise.sets[setIndex];
            return SetRow(
              number: setIndex + 1,
              fieldPrefix: '${exerciseIndex}_',
              set: set,
              showCompletionCheck: WorkoutUiPreference.completionCheckEnabled,
              onWeightChanged: (value) {
                set.weight = value;
                onValuesChanged();
              },
              onRepsChanged: (value) {
                set.reps = value;
                onValuesChanged();
              },
              onToggle: () => onToggleSet(setIndex),
              onDelete: () => onRemoveSet(setIndex),
            );
          }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: exerciseIndex == 0
                  ? const Key('addSetButton')
                  : Key('addSetButton$exerciseIndex'),
              onPressed: onAddSet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('セットを追加'),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkoutDraftSummary {
  const WorkoutDraftSummary({
    required this.date,
    required this.exerciseNames,
    required this.setCount,
  });

  final DateTime date;
  final List<String> exerciseNames;
  final int setCount;

  static WorkoutDraftSummary? tryParse(String? encoded) {
    if (encoded == null) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final exercises = json['exercises'] as List<dynamic>;
      if (exercises.isEmpty) return null;
      final names = <String>[];
      var sets = 0;
      for (final item in exercises) {
        final exercise = item as Map<String, dynamic>;
        final name = exercise['name'] as String?;
        if (name != null && name.isNotEmpty && !names.contains(name)) {
          names.add(name);
        }
        sets += (exercise['sets'] as List<dynamic>? ?? const []).length;
      }
      if (names.isEmpty) return null;
      return WorkoutDraftSummary(
        date:
            DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        exerciseNames: names,
        setCount: sets,
      );
    } catch (_) {
      return null;
    }
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

List<SavedWorkoutTemplate> decodeWorkoutTemplates(Object? source) {
  if (source is! List<dynamic>) return [];
  return source
      .map(SavedWorkoutTemplate.tryFromJson)
      .whereType<SavedWorkoutTemplate>()
      .toList(growable: false);
}

List<ExerciseTemplate> decodeExerciseTemplates(Object? source) {
  if (source is! List<dynamic>) return [];
  return source
      .map(ExerciseTemplate.tryFromJson)
      .whereType<ExerciseTemplate>()
      .toList(growable: false);
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

  double get volume => sets.fold<double>(
    0,
    (total, set) => total + (set.bodyPart == '有酸素' ? 0 : set.weight * set.reps),
  );

  RecordedSet get bestSet => sets.reduce(
    (best, set) => set.weight * set.reps > best.weight * best.reps ? set : best,
  );

  factory WorkoutRecord.fromJson(Map<String, dynamic> json) => WorkoutRecord(
    date: DateTime.parse(json['date'] as String),
    durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    gymName: json['gymName'] as String?,
    note: json['note'] as String? ?? '',
    sets: (json['sets'] as List<dynamic>)
        .map((item) => RecordedSet.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  static WorkoutRecord? tryFromJson(Object? source) {
    if (source is! Map<String, dynamic>) return null;
    try {
      final workout = WorkoutRecord.fromJson(source);
      return workout.sets.isEmpty ? null : workout;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'durationSeconds': durationSeconds,
    'gymName': gymName,
    'note': note,
    'sets': sets.map((set) => set.toJson()).toList(),
  };
}

List<WorkoutRecord> decodeWorkoutItems(Object? source) {
  if (source is! List<dynamic>) return [];
  return source
      .map(WorkoutRecord.tryFromJson)
      .whereType<WorkoutRecord>()
      .toList(growable: false);
}

List<WorkoutRecord> decodeWorkoutHistory(String? encoded) {
  if (encoded == null) return [];
  try {
    return decodeWorkoutItems(jsonDecode(encoded));
  } catch (_) {
    return [];
  }
}

List<WorkoutRecord> sortWorkoutsNewestFirst(Iterable<WorkoutRecord> workouts) =>
    workouts.toList()..sort((a, b) => b.date.compareTo(a.date));

List<RecordedSet> latestSetsForExercise(
  Iterable<WorkoutRecord> workouts,
  String exerciseName,
) {
  WorkoutRecord? latest;
  for (final workout in workouts) {
    if (!workout.sets.any((set) => set.exerciseName == exerciseName)) continue;
    if (latest == null || workout.date.isAfter(latest.date)) latest = workout;
  }
  if (latest == null) return [];
  return latest.sets
      .where((set) => set.exerciseName == exerciseName)
      .toList(growable: false);
}

const setLabelStyle = TextStyle(
  fontSize: 10,
  color: Color(0xFF777F78),
  fontWeight: FontWeight.w800,
  letterSpacing: 1,
);

class SetHeader extends StatelessWidget {
  const SetHeader({super.key, this.showCompletionCheck = true});

  final bool showCompletionCheck;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 42, child: Text('SET', style: setLabelStyle)),
        const Expanded(
          child: Center(child: Text('KG', style: setLabelStyle)),
        ),
        const Expanded(
          child: Center(child: Text('REPS', style: setLabelStyle)),
        ),
        SizedBox(width: showCompletionCheck ? 76 : 38),
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
    required this.onDelete,
    this.showCompletionCheck = true,
  });

  final int number;
  final String fieldPrefix;
  final WorkoutSet set;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onRepsChanged;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final bool showCompletionCheck;

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
          if (showCompletionCheck) ...[
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
            const SizedBox(width: 4),
          ],
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton(
              key: Key('deleteSet$fieldPrefix$number'),
              tooltip: 'セットを削除',
              padding: EdgeInsets.zero,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
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

const standardGyms = ['自宅', 'エニタイムフィットネス', 'ゴールドジム', 'FIT PLACE24'];

List<String> decodeCustomGyms(Object? source) {
  if (source is! List<dynamic>) return [];
  final unique = <String, String>{};
  for (final item in source.whereType<String>()) {
    final name = item.trim();
    if (name.isEmpty || standardGyms.contains(name)) continue;
    unique.putIfAbsent(name.toLowerCase(), () => name);
  }
  return unique.values.toList(growable: false);
}

class CustomGymPreference {
  CustomGymPreference._();

  static const _storageKey = 'custom_gyms';
  static List<String> gyms = [];

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      gyms = [];
      return;
    }
    try {
      gyms = decodeCustomGyms(jsonDecode(encoded));
    } catch (_) {
      gyms = [];
    }
  }

  static bool contains(String name, {String? excludingName}) {
    final normalized = name.trim().toLowerCase();
    return standardGyms.any((item) => item.toLowerCase() == normalized) ||
        gyms.any(
          (item) => item != excludingName && item.toLowerCase() == normalized,
        );
  }

  static Future<bool> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || standardGyms.contains(trimmed)) return false;
    if (gyms.any((item) => item.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }
    await replaceAll([...gyms, trimmed]);
    return true;
  }

  static Future<bool> update(String originalName, String updatedName) async {
    final trimmed = updatedName.trim();
    if (trimmed.isEmpty || contains(trimmed, excludingName: originalName)) {
      return false;
    }
    if (!gyms.contains(originalName)) return false;
    await replaceAll(
      gyms.map((item) => item == originalName ? trimmed : item).toList(),
    );
    return true;
  }

  static Future<void> remove(String name) async {
    await replaceAll(gyms.where((item) => item != name).toList());
  }

  static Future<void> replaceAll(List<String> updated) async {
    gyms = decodeCustomGyms(updated);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(gyms));
  }
}

Future<String?> showGymPicker(BuildContext context, String? currentGym) {
  final gyms = [
    ...standardGyms,
    ...CustomGymPreference.gyms,
    if (currentGym != null &&
        !standardGyms.contains(currentGym) &&
        !CustomGymPreference.gyms.contains(currentGym))
      currentGym,
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
              if (gym != null) await CustomGymPreference.add(gym);
              if (gym != null && context.mounted) Navigator.pop(context, gym);
            },
          ),
        ],
      ),
    ),
  );
}

Future<String?> _showCustomGymDialog(
  BuildContext context, {
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CustomGymDialog(initialName: initialName),
  );
}

class _CustomGymDialog extends StatefulWidget {
  const _CustomGymDialog({this.initialName});

  final String? initialName;

  @override
  State<_CustomGymDialog> createState() => _CustomGymDialogState();
}

class _CustomGymDialogState extends State<_CustomGymDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialName == null ? '場所を追加' : '場所名を変更'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('customGymNameField'),
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.isEmpty) return '場所の名前を入力してください';
            if (CustomGymPreference.contains(
              name,
              excludingName: widget.initialName,
            )) {
              return '同じ名前の場所があります';
            }
            return null;
          },
          decoration: const InputDecoration(
            labelText: '場所の名前',
            hintText: '例：近所の体育館',
          ),
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('saveCustomGymButton'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class CustomGymManagementPage extends StatefulWidget {
  const CustomGymManagementPage({
    super.key,
    required this.selectedGym,
    required this.onSelectedGymChanged,
  });

  final String? selectedGym;
  final Future<void> Function(String?) onSelectedGymChanged;

  @override
  State<CustomGymManagementPage> createState() =>
      _CustomGymManagementPageState();
}

class _CustomGymManagementPageState extends State<CustomGymManagementPage> {
  late String? _selectedGym;

  @override
  void initState() {
    super.initState();
    _selectedGym = widget.selectedGym;
  }

  Future<void> _notifyChanged() => widget.onSelectedGymChanged(_selectedGym);

  Future<void> _add() async {
    final name = await _showCustomGymDialog(context);
    if (name == null) return;
    final added = await CustomGymPreference.add(name);
    if (!mounted || !added) return;
    setState(() {});
    await _notifyChanged();
  }

  Future<void> _edit(String originalName) async {
    final name = await _showCustomGymDialog(context, initialName: originalName);
    if (name == null || name == originalName) return;
    final updated = await CustomGymPreference.update(originalName, name);
    if (!updated || !mounted) return;
    if (_selectedGym == originalName) _selectedGym = name;
    setState(() {});
    await _notifyChanged();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('「$name」に名前を変更しました')));
    }
  }

  Future<void> _delete(String name) async {
    final index = CustomGymPreference.gyms.indexOf(name);
    final wasSelected = _selectedGym == name;
    final messenger = ScaffoldMessenger.of(context);
    await CustomGymPreference.remove(name);
    if (wasSelected) _selectedGym = null;
    if (!mounted) return;
    setState(() {});
    await _notifyChanged();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「$name」を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              final restored = List<String>.from(CustomGymPreference.gyms);
              restored.insert(index.clamp(0, restored.length), name);
              await CustomGymPreference.replaceAll(restored);
              if (wasSelected) _selectedGym = name;
              if (!mounted) return;
              setState(() {});
              await _notifyChanged();
              messenger.showSnackBar(
                SnackBar(content: Text('「$name」を元に戻しました')),
              );
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final gyms = CustomGymPreference.gyms;
    return Scaffold(
      appBar: AppBar(
        title: const Text('カスタム場所'),
        actions: [
          IconButton(
            key: const Key('addCustomGymButton'),
            tooltip: '場所を追加',
            onPressed: _add,
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: gyms.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '登録した場所はありません',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('場所を登録'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: gyms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final gym = gyms[index];
                return Card(
                  key: Key('customGym$index'),
                  child: ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      gym,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: gym == _selectedGym ? const Text('現在選択中') : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '$gymの名前を変更',
                          onPressed: () => _edit(gym),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '$gymを削除',
                          onPressed: () => _delete(gym),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class BackupDataManagementPage extends StatelessWidget {
  const BackupDataManagementPage({
    super.key,
    required this.onExport,
    required this.onImportFile,
    required this.onCopy,
    required this.onImportClipboard,
  });

  final Future<void> Function(BuildContext) onExport;
  final Future<void> Function(BuildContext) onImportFile;
  final Future<void> Function(BuildContext) onCopy;
  final Future<void> Function(BuildContext) onImportClipboard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('バックアップ・データ管理')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  key: const Key('exportBackupFile'),
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('バックアップを書き出す'),
                  subtitle: const Text('日付付きJSONファイルとして保存・共有'),
                  onTap: () => onExport(context),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('importBackupFile'),
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('ファイルから復元'),
                  subtitle: const Text('JSONバックアップを選んで読み込み'),
                  onTap: () => onImportFile(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.copy_all_outlined),
                  title: const Text('バックアップをコピー'),
                  subtitle: const Text('JSONをクリップボードへコピー'),
                  onTap: () => onCopy(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore_rounded),
                  title: const Text('バックアップを読み込む'),
                  subtitle: const Text('コピーした記録をこの端末に追加'),
                  onTap: () => onImportClipboard(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
    required this.completionCheckEnabled,
    required this.workoutTimerEnabled,
    required this.workoutDurationEnabled,
    required this.onRestTimerEnabledChanged,
    required this.onRestTimerSecondsChanged,
    required this.onCompletionCheckEnabledChanged,
    required this.onWorkoutTimerEnabledChanged,
    required this.onWorkoutDurationEnabledChanged,
    required this.onCustomExercisesChanged,
    required this.onWorkoutTemplatesChanged,
    required this.onSelectedGymChanged,
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
  final bool completionCheckEnabled;
  final bool workoutTimerEnabled;
  final bool workoutDurationEnabled;
  final ValueChanged<bool> onRestTimerEnabledChanged;
  final ValueChanged<int> onRestTimerSecondsChanged;
  final ValueChanged<bool> onCompletionCheckEnabledChanged;
  final ValueChanged<bool> onWorkoutTimerEnabledChanged;
  final ValueChanged<bool> onWorkoutDurationEnabledChanged;
  final VoidCallback onCustomExercisesChanged;
  final Future<void> Function(List<SavedWorkoutTemplate>)
  onWorkoutTemplatesChanged;
  final Future<void> Function(String?) onSelectedGymChanged;

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
          _sectionTitle('トレーニング設定'),
          _trainingSettingsCard(context),
          _sectionTitle('アカウント関連'),
          Card(
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
          _sectionTitle('その他設定'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('アプリについて'),
              subtitle: Text('MUSCLE MEMORY'),
            ),
          ),
          _sectionTitle('バックアップ・データ管理'),
          Card(
            child: ListTile(
              key: const Key('backupDataManagementButton'),
              leading: const Icon(Icons.backup_outlined),
              title: const Text('バックアップ・データ管理'),
              subtitle: const Text('書き出し・復元・コピー'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BackupDataManagementPage(
                    onExport: _shareBackup,
                    onImportFile: _restoreFromFile,
                    onCopy: _copyBackup,
                    onImportClipboard: _restoreBackup,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
    ),
  );

  Widget _trainingSettingsCard(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
          key: const Key('customGymManagementButton'),
          leading: const Icon(Icons.add_location_alt_outlined),
          title: const Text('カスタム場所'),
          subtitle: Text(
            CustomGymPreference.gyms.isEmpty
                ? '登録なし'
                : '${CustomGymPreference.gyms.length}件を登録中',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => CustomGymManagementPage(
                selectedGym: selectedGym,
                onSelectedGymChanged: onSelectedGymChanged,
              ),
            ),
          ),
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
        ListTile(
          key: const Key('trainingSettingsButton'),
          leading: const Icon(Icons.fitness_center_rounded),
          title: const Text('トレーニング設定'),
          subtitle: const Text('チェック・タイマー・筋トレ時間'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => TrainingSettingsPage(
                completionCheckEnabled: completionCheckEnabled,
                workoutTimerEnabled: workoutTimerEnabled,
                workoutDurationEnabled: workoutDurationEnabled,
                restTimerEnabled: restTimerEnabled,
                restTimerSeconds: restTimerSeconds,
                onCompletionCheckEnabledChanged:
                    onCompletionCheckEnabledChanged,
                onWorkoutTimerEnabledChanged: onWorkoutTimerEnabledChanged,
                onWorkoutDurationEnabledChanged:
                    onWorkoutDurationEnabledChanged,
                onRestTimerEnabledChanged: onRestTimerEnabledChanged,
                onRestTimerSecondsChanged: onRestTimerSecondsChanged,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          key: const Key('savedMenuManagementButton'),
          leading: const Icon(Icons.bookmarks_outlined),
          title: const Text('マイメニュー管理'),
          subtitle: Text(
            workoutTemplates.isEmpty
                ? '保存なし'
                : '${workoutTemplates.length}件を保存中',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => SavedMenuManagementPage(
                initialTemplates: workoutTemplates,
                onChanged: onWorkoutTemplatesChanged,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          key: const Key('customExerciseManagementButton'),
          leading: const Icon(Icons.tune_rounded),
          title: const Text('カスタム種目'),
          subtitle: Text(
            CustomExercisePreference.exercises.isEmpty
                ? '登録なし'
                : '${CustomExercisePreference.exercises.length}種目を登録中',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const CustomExerciseManagementPage(),
              ),
            );
            onCustomExercisesChanged();
          },
        ),
        const Divider(height: 1),
        const ListTile(
          leading: Icon(Icons.scale_outlined),
          title: Text('重量の単位'),
          trailing: Text('kg', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );

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
      customGyms: CustomGymPreference.gyms,
      selectedGym: selectedGym,
      weeklyTarget: weeklyTarget,
      restTimerEnabled: restTimerEnabled,
      restTimerSeconds: restTimerSeconds,
      completionCheckEnabled: completionCheckEnabled,
      workoutTimerEnabled: workoutTimerEnabled,
      workoutDurationEnabled: workoutDurationEnabled,
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
}

class TrainingSettingsPage extends StatefulWidget {
  const TrainingSettingsPage({
    super.key,
    required this.completionCheckEnabled,
    required this.workoutTimerEnabled,
    required this.workoutDurationEnabled,
    required this.restTimerEnabled,
    required this.restTimerSeconds,
    required this.onCompletionCheckEnabledChanged,
    required this.onWorkoutTimerEnabledChanged,
    required this.onWorkoutDurationEnabledChanged,
    required this.onRestTimerEnabledChanged,
    required this.onRestTimerSecondsChanged,
  });

  final bool completionCheckEnabled;
  final bool workoutTimerEnabled;
  final bool workoutDurationEnabled;
  final bool restTimerEnabled;
  final int restTimerSeconds;
  final ValueChanged<bool> onCompletionCheckEnabledChanged;
  final ValueChanged<bool> onWorkoutTimerEnabledChanged;
  final ValueChanged<bool> onWorkoutDurationEnabledChanged;
  final ValueChanged<bool> onRestTimerEnabledChanged;
  final ValueChanged<int> onRestTimerSecondsChanged;

  @override
  State<TrainingSettingsPage> createState() => _TrainingSettingsPageState();
}

class _TrainingSettingsPageState extends State<TrainingSettingsPage> {
  late bool _completionCheckEnabled;
  late bool _workoutTimerEnabled;
  late bool _workoutDurationEnabled;
  late bool _restTimerEnabled;
  late int _restTimerSeconds;

  @override
  void initState() {
    super.initState();
    _completionCheckEnabled = widget.completionCheckEnabled;
    _workoutTimerEnabled = widget.workoutTimerEnabled;
    _workoutDurationEnabled = widget.workoutDurationEnabled;
    _restTimerEnabled = widget.restTimerEnabled && _completionCheckEnabled;
    _restTimerSeconds = widget.restTimerSeconds;
  }

  String _durationLabel(int seconds) {
    if (seconds < 60) return '$seconds秒';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '$minutes分' : '$minutes分$remainder秒';
  }

  Future<void> _selectRestDuration() async {
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
                title: Text(_durationLabel(seconds)),
                trailing: seconds == _restTimerSeconds
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
    if (selected == null) return;
    setState(() => _restTimerSeconds = selected);
    widget.onRestTimerSecondsChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('トレーニング設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('completionCheckSwitch'),
                  secondary: const Icon(Icons.check_circle_outline_rounded),
                  title: const Text('セット完了チェック'),
                  subtitle: Text(
                    _completionCheckEnabled ? '丸チェックを表示' : '入力した全セットを記録',
                  ),
                  value: _completionCheckEnabled,
                  onChanged: (enabled) {
                    setState(() {
                      _completionCheckEnabled = enabled;
                      if (!enabled) _restTimerEnabled = false;
                    });
                    widget.onCompletionCheckEnabledChanged(enabled);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('workoutTimerSwitch'),
                  secondary: const Icon(Icons.timelapse_rounded),
                  title: const Text('トレーニングタイマー'),
                  subtitle: Text(
                    _workoutTimerEnabled ? '記録中に経過時間を表示' : '画面に表示しない',
                  ),
                  value: _workoutTimerEnabled,
                  onChanged: (enabled) {
                    setState(() => _workoutTimerEnabled = enabled);
                    widget.onWorkoutTimerEnabledChanged(enabled);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('workoutDurationSwitch'),
                  secondary: const Icon(Icons.schedule_rounded),
                  title: const Text('筋トレ時間'),
                  subtitle: Text(
                    _workoutDurationEnabled ? '時間を記録・履歴に表示' : '時間を記録しない',
                  ),
                  value: _workoutDurationEnabled,
                  onChanged: (enabled) {
                    setState(() => _workoutDurationEnabled = enabled);
                    widget.onWorkoutDurationEnabledChanged(enabled);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('restTimerSwitch'),
                  secondary: const Icon(Icons.timer_outlined),
                  title: const Text('休憩タイマー'),
                  subtitle: Text(
                    !_completionCheckEnabled
                        ? 'セット完了チェックをONにすると利用できます'
                        : _restTimerEnabled
                        ? 'セット完了後に開始'
                        : '使用しない',
                  ),
                  value: _restTimerEnabled,
                  onChanged: _completionCheckEnabled
                      ? (enabled) {
                          setState(() => _restTimerEnabled = enabled);
                          widget.onRestTimerEnabledChanged(enabled);
                        }
                      : null,
                ),
                if (_completionCheckEnabled && _restTimerEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('restTimerDurationButton'),
                    leading: const Icon(Icons.hourglass_bottom_rounded),
                    title: const Text('休憩時間'),
                    trailing: Text(
                      _durationLabel(_restTimerSeconds),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onTap: _selectRestDuration,
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text(
              '休憩タイマーは、セット完了チェックを付けたときに開始します。',
              style: TextStyle(fontSize: 12, color: Color(0xFF777F78)),
            ),
          ),
        ],
      ),
    );
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
