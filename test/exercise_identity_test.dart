import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:muscle_memory/exercise_form_catalog.dart';
import 'package:muscle_memory/exercise_form_catalog.g.dart';
import 'package:shared_preferences/shared_preferences.dart';

ExerciseTemplate variant(String id) =>
    exerciseTemplates.singleWhere((e) => e.exerciseId == id);
RecordedSet record(String id, {double weight = 40}) {
  final e = variant(id);
  return RecordedSet(
    exerciseId: e.exerciseId,
    exerciseName: e.name,
    bodyPart: e.bodyPart,
    equipment: e.equipment,
    distanceUnit: e.distanceUnit,
    recordType: e.recordType,
    weight: weight,
    reps: e.recordType.usesSets ? 10 : 0,
    distanceKm: .05,
    durationSeconds: 60,
    completed: true,
  );
}

Widget qaApp(Widget page, {String language = 'ja'}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('ja'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: page,
);
Future<void> tapVisible(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pumpAndSettle();
  await t.tap(find.byKey(key));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomExercisePreference.exercises = [];
    WorkoutUiPreference.completionCheckEnabled = true;
  });
  tearDown(() => CustomExercisePreference.exercises = []);

  test(
    'identity catalog source equals generated data and all 194 IDs are unique',
    () {
      final source = jsonDecode(
        File('tool/exercise_forms/catalog.json').readAsStringSync(),
      ) as Map;
      expect(exerciseFormData, source['exercises']);
      expect(exerciseTemplates, hasLength(194));
      expect(exerciseTemplates.map((e) => e.identity).toSet(), hasLength(194));
      for (final e in ExerciseFormCatalog.entries) {
        expect(e.equipmentLabel, isNotEmpty);
        expect(e.englishName, isNotEmpty);
        expect(e.primaryMuscles, isNotEmpty);
        expect(e.primaryMuscleLabels, isNotEmpty);
        if (e.status == 'planned') expect(e.assetPath, isNull);
      }
      for (final name in ['ショルダープレス', 'インクラインチェストプレス', 'チェストプレス']) {
        final variants = ExerciseFormCatalog.byName[name]!;
        expect(variants, hasLength(2));
        expect(variants.map((e) => e.equipmentLabel).toSet(), {
          'マシン',
          'プレートロード',
        });
        expect(ExerciseFormCatalog.forName(name), isNull);
      }
      expect(variant('dumbbell_shoulder_press').equipment, 'ダンベル');
      expect(variant('plank').matchesQuery('腹筋'), true);
      expect(variant('chin_up').matchesQuery('懸垂'), true);
      expect(
        exerciseDisplayName(
          'ショルダープレス',
          exerciseId: 'plate_loaded_shoulder_press',
          languageCode: 'en',
        ),
        'Shoulder Press',
      );
      expect(ExerciseFormCatalog.byId['bench_press']!.available, true);
      expect(
        ExerciseFormCatalog.byId['incline_dumbbell_press']!.available,
        true,
      );
    },
  );

  test(
    'identity HYROX uses appropriate fields and metres; running stays single',
    () {
      final hyrox = exerciseTemplates
          .where((e) => e.bodyPart == 'HYROX')
          .toList();
      expect(hyrox.map((e) => e.name).toSet(), {
        'スキーエルゴ',
        'スレッドプッシュ',
        'スレッドプル',
        'バーピーブロードジャンプ',
        'ローイング',
        'ファーマーズキャリー',
        'サンドバッグランジ',
        'ウォールボール',
      });
      expect(exerciseTemplates.where((e) => e.name == 'ランニング'), hasLength(1));
      for (final id in [
        'hyrox_sled_push',
        'hyrox_sled_pull',
        'hyrox_farmers_carry',
        'hyrox_sandbag_lunge',
      ]) {
        final before = record(id);
        final after = RecordedSet.fromJson(
          jsonDecode(jsonEncode(before.toJson())),
        );
        expect(after.exerciseId, id);
        expect(after.recordType, ExerciseRecordType.loadedDistance);
        expect(after.hasRequiredValues, true);
        expect(after.displaySummary, contains('50 m'));
        expect(after.distanceKm, .05);
        expect(after.weight, 40);
        expect(WorkoutRecord(date: DateTime(2026), sets: [after]).volume, 0);
      }
      expect(variant('hyrox_ski_erg').recordType, ExerciseRecordType.cardio);
      expect(
        variant('hyrox_wall_ball').recordType,
        ExerciseRecordType.weightReps,
      );
      expect(
        variant('hyrox_burpee_broad_jump').recordType,
        ExerciseRecordType.distance,
      );
      expect(variant('hyrox_sled_push').matchesQuery('スレッド'), true);
      expect(variant('hyrox_sled_push').matchesQuery('Sled Push'), true);
      expect(variant('hyrox_sled_push').matchesQuery('脚'), true);
    },
  );

  test('identity histories and personal bests never merge variants or legacy records', () {
    final a = record('shoulder_press', weight: 80);
    final b = record('plate_loaded_shoulder_press', weight: 20);
    final legacy = RecordedSet.fromJson({
      'exerciseName': 'ショルダープレス',
      'bodyPart': '肩',
      'weight': 12,
      'reps': 10,
      'completed': true,
    });
    final old = WorkoutRecord(date: DateTime(2026, 1, 1), sets: [legacy, a]);
    final current = WorkoutRecord(date: DateTime(2026, 1, 2), sets: [b]);
    final combined = WorkoutRecord(date: DateTime(2026), sets: [a, b, legacy]);
    expect(combined.exerciseGroups, hasLength(3));
    expect(combined.exerciseNames, hasLength(3));
    expect(
      latestSetsForExercise(
        [old, current],
        a.exerciseName,
        exerciseId: a.exerciseId,
      ).single.weight,
      80,
    );
    expect(
      latestSetsForExercise(
        [old, current],
        b.exerciseName,
        exerciseId: b.exerciseId,
      ).single.weight,
      20,
    );
    expect(
      latestSetsForExercise([old, current], legacy.exerciseName).single.weight,
      12,
    );
    expect(countPersonalBests([old, current], DateTime(2026, 1, 2)), 1);
    expect(legacy.exerciseId, isNull);
    expect(legacy.toJson().containsKey('exerciseId'), false);
    final roundtrip = WorkoutRecord.fromJson(
      jsonDecode(jsonEncode(combined.toJson())),
    );
    expect(roundtrip.exerciseGroups.keys, combined.exerciseGroups.keys);
    final menu = SavedWorkoutTemplate.fromJson({
      'name': '同名',
      'sets': [a.toJson(), b.toJson()],
    });
    expect(menu.exerciseGroups, hasLength(2));
    expect(menu.toWorkoutRecord().exerciseGroups, hasLength(2));
  });

  test('identity old backups restore without assigning built-in IDs', () {
    final old = {
      'exerciseName': 'ショルダープレス',
      'bodyPart': '肩',
      'weight': 12,
      'reps': 10,
      'completed': true,
    };
    for (final version in [1, 2, 3]) {
      final backup = MuscleMemoryBackup.fromJson({
        'app': 'MuscleMemory',
        'version': version,
        'workouts': [
          {
            'date': '2026-01-01T00:00:00',
            'sets': [old],
          },
        ],
        'workoutTemplates': [
          {
            'name': '旧メニュー',
            'sets': [old],
          },
        ],
        'customExercises': [
          {
            'name': '自分の種目',
            'bodyPart': '肩',
            'equipment': 'その他',
            'startWeight': 5,
          },
        ],
      });
      expect(backup.workouts.single.sets.single.exerciseId, isNull);
      expect(backup.workouts.single.sets.single.exerciseName, 'ショルダープレス');
      if (version > 1) {
        expect(backup.workoutTemplates.single.sets.single.exerciseId, isNull);
        expect(
          backup.customExercises.single.exerciseId,
          startsWith('custom_legacy_'),
        );
      }
      expect(
        MuscleMemoryBackup.fromJson(jsonDecode(jsonEncode(backup.toJson())))
            .workouts
            .single
            .sets
            .single
            .weight,
        12,
      );
    }
  });

  test(
    'identity custom IDs survive reload rename equipment edits and backups',
    () async {
      final json = {
        'name': '独自プレス',
        'bodyPart': '肩',
        'equipment': 'マシン',
        'startWeight': 10,
      };
      final a = decodeExerciseTemplates([json]).single;
      final again = decodeExerciseTemplates([json]).single;
      expect(a.exerciseId, again.exerciseId);
      await CustomExercisePreference.replaceAll([a]);
      final b = ExerciseTemplate(
        exerciseId: newCustomExerciseId(),
        name: a.name,
        bodyPart: a.bodyPart,
        equipment: 'プレートロード',
        startWeight: 20,
      );
      expect(await CustomExercisePreference.add(b), true);
      expect(await CustomExercisePreference.add(b), false);
      await CustomExercisePreference.load();
      expect(CustomExercisePreference.exercises, hasLength(2));
      expect(
        await CustomExercisePreference.update(a.name, b),
        false,
        reason: 'Ambiguous old name must not choose a row',
      );
      final changed = ExerciseTemplate(
        name: '名前変更',
        bodyPart: a.bodyPart,
        equipment: 'その他',
        startWeight: 15,
      );
      expect(await CustomExercisePreference.update(a.identity, changed), true);
      final restored = decodeExerciseTemplates(
        jsonDecode(
          jsonEncode(
            CustomExercisePreference.exercises.map((e) => e.toJson()).toList(),
          ),
        ),
      );
      expect(restored.map((e) => e.exerciseId).toSet(), {
        a.exerciseId,
        b.exerciseId,
      });
      await CustomExercisePreference.remove(b);
      expect(
        CustomExercisePreference.exercises.single.exerciseId,
        a.exerciseId,
      );
    },
  );

  testWidgets(
    'identity picker can independently select both same-name variants',
    (t) async {
      await t.pumpWidget(
        qaApp(const Scaffold(body: ExercisePickerSheet(existingNames: {}))),
      );
      await t.pumpAndSettle();
      await tapVisible(t, const Key('exerciseCategory肩'));
      await t.enterText(
        find.byKey(const Key('exerciseSearchField')),
        'ショルダープレス',
      );
      await t.pumpAndSettle();
      Finder check(String id) => find.byKey(Key('selectExercise$id'));
      await tapVisible(t, const Key('selectExerciseshoulder_press'));
      expect(t.widget<ListTile>(check('shoulder_press')).selected, true);
      await tapVisible(
        t,
        const Key('selectExerciseplate_loaded_shoulder_press'),
      );
      expect(
        t.widget<ListTile>(check('plate_loaded_shoulder_press')).selected,
        true,
      );
      expect(find.text('2種目選択中'), findsOneWidget);
      expect(find.text('肩 ・ プレートロード'), findsOneWidget);
      await tapVisible(t, const Key('selectExerciseshoulder_press'));
      expect(find.text('1種目選択中'), findsOneWidget);
      expect(
        t.widget<ListTile>(check('plate_loaded_shoulder_press')).selected,
        true,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'identity English names and existing selection use the explicit ID',
    (t) async {
      await t.pumpWidget(
        qaApp(
          const Scaffold(
            body: ExercisePickerSheet(
              existingIdentities: {'id:shoulder_press'},
            ),
          ),
          language: 'en',
        ),
      );
      await t.pumpAndSettle();
      await tapVisible(t, const Key('exerciseCategory肩'));
      await t.enterText(
        find.byKey(const Key('exerciseSearchField')),
        'shoulder press',
      );
      await t.pumpAndSettle();
      expect(find.text('Shoulder Press'), findsNWidgets(2));
      final machine = find.byKey(const Key('selectExerciseshoulder_press'));
      final plate = find.byKey(const Key('selectExerciseplate_loaded_shoulder_press'));
      expect(t.widget<ListTile>(machine).onTap, isNull);
      expect(t.widget<ListTile>(plate).selected, false);
      expect(t.widget<ListTile>(plate).onTap, isNotNull);
      expect(t.widget<ListTile>(machine).selected, false);
      await tapVisible(t, const Key('favoriteExerciseid:shoulder_press'));
      expect(await ExerciseFavoritePreference.load(), contains('id:shoulder_press'));
      expect(find.text('0種目選択中'), findsOneWidget);
      await tapVisible(
        t,
        const Key('selectExerciseplate_loaded_shoulder_press'),
      );
      expect(find.text('1種目選択中'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'identity loaded distance input converts metres while retaining kg',
    (t) async {
      final e = variant('hyrox_sled_push');
      final set = WorkoutSet(weight: 20, reps: 0);
      await t.pumpWidget(
        qaApp(
          Scaffold(
            body: SingleChildScrollView(
              child: ExerciseInputCard(
                exerciseIndex: 0,
                exercise: WorkoutExercise(
                  exerciseId: e.exerciseId,
                  name: e.name,
                  bodyPart: e.bodyPart,
                  equipment: e.equipment,
                  recordType: e.recordType,
                  distanceUnit: e.distanceUnit,
                  sets: [set],
                ),
                history: const [],
                onAddSet: () {},
                onRemove: null,
                onRemoveSet: (_) {},
                onToggleSet: (_) {},
                onApplyPrevious: (_) {},
                onSetAllCompleted: (_) {},
                onValuesChanged: () {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('距離（m）'), findsOneWidget);
      await t.enterText(
        find.descendant(
          of: find.byKey(const Key('distanceField0_')),
          matching: find.byType(TextFormField),
        ),
        '50',
      );
      await t.enterText(
        find.descendant(
          of: find.byKey(const Key('loadedWeightField0_')),
          matching: find.byType(TextFormField),
        ),
        '75',
      );
      await t.pumpAndSettle();
      expect(set.distanceKm, .05);
      expect(set.weight, 75);
      expect(find.text('REPS'), findsNothing);
      expect(find.text('SET'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
