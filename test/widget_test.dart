import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('custom exercises persist between sessions', () async {
    SharedPreferences.setMockInitialValues({});
    await CustomExercisePreference.load();
    await CustomExercisePreference.add(
      const ExerciseTemplate(
        name: 'テスト種目',
        bodyPart: '背中',
        equipment: 'カスタム',
        startWeight: 15,
      ),
    );

    CustomExercisePreference.exercises = [];
    await CustomExercisePreference.load();
    expect(CustomExercisePreference.exercises, hasLength(1));
    expect(CustomExercisePreference.exercises.single.name, 'テスト種目');
    expect(CustomExercisePreference.exercises.single.bodyPart, '背中');
  });

  test('personal bests are counted in date order', () {
    WorkoutRecord workout(DateTime date, String exercise, int weight) =>
        WorkoutRecord(
          date: date,
          sets: [
            RecordedSet(
              exerciseName: exercise,
              bodyPart: exercise == 'スクワット' ? '脚' : '胸',
              weight: weight.toDouble(),
              reps: 5,
              completed: true,
            ),
          ],
        );

    final history = [
      workout(DateTime(2026, 1, 4), 'ベンチプレス', 50),
      workout(DateTime(2026, 1, 3), 'ベンチプレス', 60),
      workout(DateTime(2026, 1, 1), 'ベンチプレス', 50),
      workout(DateTime(2026, 1, 2), 'スクワット', 80),
      workout(DateTime(2026, 1, 2), 'ベンチプレス', 55),
    ];

    expect(countPersonalBests(history, DateTime(2026, 1, 2)), 3);
  });

  test('changing the calendar day preserves the recorded time', () {
    final original = DateTime(2026, 9, 12, 18, 42, 31, 120, 45);
    final changed = preserveWorkoutTime(original, DateTime(2026, 8, 3));

    expect(changed, DateTime(2026, 8, 3, 18, 42, 31, 120, 45));
  });

  test('decimal weights support old integer data and compact display', () {
    final oldData = RecordedSet.fromJson({
      'exerciseName': 'ベンチプレス',
      'bodyPart': '胸',
      'weight': 50,
      'reps': 8,
      'completed': true,
    });
    final decimalData = RecordedSet.fromJson({
      'exerciseName': 'ベンチプレス',
      'bodyPart': '胸',
      'weight': 52.5,
      'reps': 8,
      'completed': true,
    });

    expect(oldData.weight, 50.0);
    expect(decimalData.weight, 52.5);
    expect(formatWeight(oldData.weight), '50');
    expect(formatWeight(decimalData.weight), '52.5');
    expect(parseWeight('52,5'), 52.5);
  });

  test('version 2 backup preserves workouts menus exercises and settings', () {
    final backup = MuscleMemoryBackup(
      workouts: [
        WorkoutRecord(
          date: DateTime(2026, 9, 12, 18, 30),
          sets: const [
            RecordedSet(
              exerciseName: 'ベンチプレス',
              bodyPart: '胸',
              weight: 52.5,
              reps: 8,
              completed: true,
            ),
          ],
        ),
      ],
      workoutTemplates: const [
        SavedWorkoutTemplate(
          name: '胸の日',
          sets: [
            RecordedSet(
              exerciseName: 'ベンチプレス',
              bodyPart: '胸',
              weight: 52.5,
              reps: 8,
              completed: true,
            ),
          ],
        ),
      ],
      customExercises: const [
        ExerciseTemplate(
          name: 'テストプレス',
          bodyPart: '胸',
          equipment: 'カスタム',
          startWeight: 12.5,
        ),
      ],
      selectedGym: 'テストジム',
      weeklyTarget: 4,
      restTimerEnabled: true,
      restTimerSeconds: 120,
    );

    final restored = MuscleMemoryBackup.fromJson(backup.toJson());

    expect(restored.workouts.single.sets.single.weight, 52.5);
    expect(restored.workoutTemplates.single.name, '胸の日');
    expect(restored.customExercises.single.startWeight, 12.5);
    expect(restored.selectedGym, 'テストジム');
    expect(restored.weeklyTarget, 4);
    expect(restored.restTimerEnabled, isTrue);
    expect(restored.restTimerSeconds, 120);
  });

  test('old history-only backups remain readable', () {
    final restored = MuscleMemoryBackup.fromJson({
      'app': 'MuscleMemory',
      'version': 1,
      'workouts': <dynamic>[],
    });

    expect(restored.workouts, isEmpty);
    expect(restored.workoutTemplates, isEmpty);
    expect(restored.weeklyTarget, isNull);
  });

  test('workouts are sorted newest first without changing the input list', () {
    WorkoutRecord workout(DateTime date) => WorkoutRecord(
      date: date,
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    final old = workout(DateTime(2026, 1, 1));
    final newest = workout(DateTime(2026, 1, 3));
    final middle = workout(DateTime(2026, 1, 2));
    final input = [old, newest, middle];

    final sorted = sortWorkoutsNewestFirst(input);

    expect(sorted, [newest, middle, old]);
    expect(input, [old, newest, middle]);
  });

  testWidgets('history cards show the saved location and memo', (tester) async {
    final workout = WorkoutRecord(
      date: DateTime(2026, 9, 12),
      gymName: 'テストジム',
      note: 'フォームを丁寧に',
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryCard(
            workout: workout,
            selectedGym: null,
            onWorkoutCompleted: (_) {},
            onWorkoutUpdated: (_, _) async {},
            onWorkoutDeleted: (_) async => true,
          ),
        ),
      ),
    );

    expect(find.text('テストジム'), findsOneWidget);
    expect(find.text('フォームを丁寧に'), findsOneWidget);
  });

  testWidgets('an existing workout date can be changed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final workout = WorkoutRecord(
      date: DateTime(2025, 3, 15, 19, 30),
      sets: const [
        RecordedSet(
          exerciseName: 'ベンチプレス',
          bodyPart: '胸',
          weight: 50,
          reps: 8,
          completed: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: WorkoutPage(initialWorkout: workout, isEditing: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('2025年3月15日'), findsOneWidget);
    await tester.tap(find.byKey(const Key('workoutDateButton')));
    await tester.pumpAndSettle();
    expect(find.text('トレーニング日'), findsWidgets);
    await tester.tap(find.text('14'));
    await tester.tap(find.text('決定'));
    await tester.pumpAndSettle();

    expect(find.text('2025年3月14日'), findsOneWidget);
  });

  test('saved workout templates persist', () async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutTemplatePreference.save([
      const SavedWorkoutTemplate(
        name: '胸の日',
        sets: [
          RecordedSet(
            exerciseName: 'ベンチプレス',
            bodyPart: '胸',
            weight: 50,
            reps: 8,
            completed: true,
          ),
        ],
      ),
    ]);

    final templates = await WorkoutTemplatePreference.load();
    expect(templates, hasLength(1));
    expect(templates.single.name, '胸の日');
    expect(templates.single.sets.single.weight, 50);
  });

  testWidgets('starts a workout and adds a set', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    expect(find.text('今日も積み上げよう'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();

    expect(find.text('ベンチプレス'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weightField0_1')), '42.5');
    expect(find.text('42.5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addSetButton')));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('active_workout_draft'),
      contains('"weight":42.5'),
    );
  });

  testWidgets('completed workout appears in history', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pump();
    expect(find.text('完了したセットを1つ以上チェックしてください'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('自己ベスト更新'), findsOneWidget);
    await tester.tap(find.text('ホームへ戻る'));
    await tester.pumpAndSettle();

    expect(find.text('クイックスタート'), findsOneWidget);

    await tester.tap(find.byTooltip('マイメニューに保存'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('templateNameField')), '胸の日');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('マイメニュー'), findsOneWidget);
    expect(find.text('胸の日'), findsOneWidget);

    await tester.tap(find.text('履歴'));
    await tester.pumpAndSettle();
    expect(find.text('月間カレンダー'), findsOneWidget);
    expect(find.byKey(const Key('monthlyCalendar')), findsOneWidget);
    expect(find.text('トレーニング履歴'), findsNothing);
    expect(find.byTooltip('カレンダーで見る'), findsNothing);
    expect(find.byTooltip('履歴を検索'), findsOneWidget);
    expect(find.byTooltip('種目ごとの成長を見る'), findsOneWidget);

    final today = DateTime.now();
    await tester.tap(find.byKey(Key('calendarDay${today.day}')));
    await tester.pumpAndSettle();
    expect(find.text('${today.month}月${today.day}日の記録'), findsOneWidget);
    expect(find.text('ベンチプレス'), findsOneWidget);
  });

  testWidgets('rest timer only starts when enabled', (tester) async {
    SharedPreferences.setMockInitialValues({
      'rest_timer_enabled': false,
      'rest_timer_seconds': 60,
    });
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();
    expect(find.byKey(const Key('restTimerBanner')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    SharedPreferences.setMockInitialValues({
      'rest_timer_enabled': true,
      'rest_timer_seconds': 60,
    });
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();

    expect(find.byKey(const Key('restTimerBanner')), findsOneWidget);
    expect(find.textContaining('休憩  01:'), findsOneWidget);
  });

  testWidgets('workout draft is saved and leaving asks for confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await RestTimerPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '55');
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('active_workout_draft'),
      contains('"weight":55'),
    );
    expect(preferences.getString('active_workout_draft'), contains('"date":'));

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('ホームに戻りますか？'), findsOneWidget);
    expect(find.textContaining('入力内容は自動保存'), findsOneWidget);
  });
}
