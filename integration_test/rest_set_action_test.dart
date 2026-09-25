import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/services/android_workout_draft.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.setkeep.app/rest_timer');
  Map<String, dynamic> fixture() => {
    'sessionId': 'qa-workout',
    'lockRevision': 0,
    'date': '2026-09-24T12:00:00.000',
    'gymName': '自宅',
    'note': 'keep',
    'exercises': [
      {
        'instanceId': 'qa-exercise',
        'exerciseId': 'bench_press',
        'name': 'ベンチプレス',
        'bodyPart': '胸',
        'equipment': 'バーベル',
        'recordType': 'weightReps',
        'sets': List.generate(
          3,
          (i) => {
            'setId': 'set_$i',
            'weight': 80.5,
            'reps': 10,
            'durationSeconds': 23,
            'distanceKm': 1.2,
            'completed': i == 0,
          },
        ),
      },
    ],
  };
  const target = {
    'sessionId': 'qa-workout',
    'exerciseInstanceId': 'qa-exercise',
    'previousSetId': 'set_0',
    'targetSetId': 'set_1',
  };
  Future<Map<String, dynamic>> draft() async =>
      jsonDecode((await AndroidWorkoutDraft.read())!);
  Future<String> start() async {
    await RestNotificationService.schedule(
      2,
      exerciseName: 'ベンチプレス',
      target: target,
      restSeconds: 2,
    );
    final state = (await RestNotificationService.state())!;
    return state['timerId'] as String;
  }

  Future<void> action(String id, String set) => channel.invokeMethod(
    'debugRestAction',
    {'action': 'complete', 'timerId': id, 'targetSetId': set},
  );
  testWidgets(
    'native set action persists once and advances only its bound set',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold()));
      await AndroidWorkoutDraft.clear();
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      debugPrint('QA_REST_PERMISSION_READY');
      await Future<void>.delayed(const Duration(seconds: 2));
      final before = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      final id = await start();
      final status = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      expect(status['delivered'], contains(7340));
      await action(id, 'wrong-set');
      expect((await draft())['lockRevision'], 0);
      await action(id, 'set_1');
      await action(id, 'set_1');
      var saved = await draft();
      final sets = saved['exercises'][0]['sets'] as List;
      expect(sets[1]['completed'], true);
      expect(sets[2]['completed'], false);
      expect(sets[1]['weight'], 80.5);
      expect(sets[1]['reps'], 10);
      expect(sets[1]['durationSeconds'], 23);
      expect(sets[1]['distanceKm'], 1.2);
      expect(saved['note'], 'keep');
      expect(saved['lockRevision'], 1);
      final afterAction = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      expect(
        afterAction['completionCount'] ?? 0,
        before['completionCount'] ?? 0,
      );
      final next = (await RestNotificationService.state())!;
      expect(next['timerId'], isNot(id));
      expect(
        next['endsAtMilliseconds'],
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      await action(next['timerId'], 'set_2');
      saved = await draft();
      expect(saved['exercises'][0]['sets'][2]['completed'], true);
      expect(saved['lockRevision'], 2);
      final afterExpiry = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      expect(
        afterExpiry['completionCount'],
        (before['completionCount'] ?? 0) + 1,
      );
      expect((await RestNotificationService.state())!['endsAtMilliseconds'], 0);
      // A queued Flutter snapshot must not undo a committed background completion.
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      saved = await draft();
      expect(saved['exercises'][0]['sets'][1]['completed'], true);
      expect(saved['exercises'][0]['sets'][2]['completed'], true);
      await AndroidWorkoutDraft.clear();
    },
  );
  testWidgets('native action moves across exercises and skips completed sets', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold()));
    await AndroidWorkoutDraft.clear();
    final data = fixture();
    data['exercises'][0]['sets'][2]['completed'] = true;
    final second = Map<String, Object>.from(data['exercises'][0]);
    second['instanceId'] = 'second';
    second['name'] = 'ダンベルカール';
    second['exerciseId'] = 'dumbbell_curl';
    second['sets'] = [
      {'setId': 'second_0', 'weight': 12, 'reps': 8, 'completed': false},
    ];
    data['exercises'].add(second);
    await AndroidWorkoutDraft.write(jsonEncode(data));
    final id = await start();
    await action(id, 'set_1');
    final next = (await RestNotificationService.state())!;
    expect(next['target']['targetSetId'], 'second_0');
    expect(next['exerciseName'], 'ダンベルカール');
    await action(id, 'set_1');
    expect((await draft())['exercises'][1]['sets'][0]['completed'], false);
    await action(
      next['timerId'],
      'second_0',
    ); // Replacement arriving during a double tap.
    expect((await draft())['exercises'][1]['sets'][0]['completed'], false);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await action(next['timerId'], 'second_0');
    expect((await draft())['exercises'][1]['sets'][0]['completed'], true);
    expect((await RestNotificationService.state())!['endsAtMilliseconds'], 0);
    await AndroidWorkoutDraft.clear();
  });
  testWidgets(
    'extended action replaces stale generation and stop stays silent',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold()));
      await AndroidWorkoutDraft.clear();
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      final oldId = await start();
      final before = (await RestNotificationService.state())!;
      await channel.invokeMethod<void>('debugRestAction', {'action': 'extend'});
      final extended = (await RestNotificationService.state())!;
      expect(
        extended['endsAtMilliseconds'],
        before['endsAtMilliseconds'] + 30000,
      );
      await action(oldId, 'set_1');
      expect((await draft())['lockRevision'], 0);
      await action(extended['timerId'], 'set_1');
      expect((await draft())['lockRevision'], 1);
      await channel.invokeMethod<void>('debugRestAction', {'action': 'stop'});
      final status = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      await Future<void>.delayed(const Duration(seconds: 3));
      final after = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      expect(after['completionCount'], status['completionCount']);
      expect(after['delivered'], isNot(contains(7340)));
      await action(extended['timerId'], 'set_1');
      expect((await draft())['lockRevision'], 1);
      await AndroidWorkoutDraft.clear();
    },
  );
  testWidgets(
    'value edits preserve bound action while removal invalidates it',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold()));
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      final id = await start();
      await Future<void>.delayed(const Duration(seconds: 3));
      await AndroidWorkoutDraft.write(
        jsonEncode(fixture()..['note'] = 'edited'),
      );
      await action(id, 'set_1');
      expect((await draft())['exercises'][0]['sets'][1]['completed'], true);
      expect((await draft())['note'], 'edited');
      await AndroidWorkoutDraft.clear();
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      final removalId = await start();
      final removed = fixture();
      removed['exercises'][0]['sets'].removeAt(1);
      await AndroidWorkoutDraft.write(jsonEncode(removed));
      await action(removalId, 'set_1');
      expect((await draft())['exercises'][0]['sets'].length, 2);
      expect((await draft())['exercises'][0]['sets'][1]['completed'], false);
      await AndroidWorkoutDraft.clear();
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      final undoId = await start();
      final undone = fixture();
      undone['exercises'][0]['sets'][0]['completed'] = false;
      await AndroidWorkoutDraft.write(jsonEncode(undone));
      await action(undoId, 'set_1');
      expect((await draft())['exercises'][0]['sets'][1]['completed'], false);
      await AndroidWorkoutDraft.clear();
      await action(id, 'set_1');
      expect(await AndroidWorkoutDraft.read(), isNull);
    },
  );
  testWidgets(
    'normal set completion arms the action and saved workout includes background sets',
    (t) async {
      await AndroidWorkoutDraft.clear();
      WorkoutUiPreference.completionCheckEnabled = true;
      WorkoutUiPreference.workoutTimerEnabled = false;
      WorkoutUiPreference.workoutDurationEnabled = false;
      RestTimerPreference.enabled = true;
      RestTimerPreference.seconds = 2;
      WorkoutRecord? result;
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            gymName: '自宅',
            resumeDraft: false,
            initialWorkout: WorkoutRecord(
              date: DateTime.now(),
              sets: List.generate(
                3,
                (_) => const RecordedSet(
                  exerciseName: 'ベンチプレス',
                  exerciseId: 'bench_press',
                  weight: 80.5,
                  reps: 10,
                  completed: false,
                ),
              ),
            ),
            onSave: (record) async {
              result = record;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      final check = find.byKey(const Key('toggleSet0_1'));
      await t.ensureVisible(check);
      await t.pumpAndSettle();
      await t.tap(check);
      await Future<void>.delayed(const Duration(seconds: 3));
      await t.pumpAndSettle();
      await channel.invokeMethod<void>('debugRestAction', {
        'action': 'completeNotification',
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect((await draft())['exercises'][0]['sets'][1]['completed'], true);
      await t.tap(find.byKey(const Key('completeWorkoutButton')));
      await t.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.sets.length, 2);
      expect(result!.sets.last.weight, 80.5);
      expect(await AndroidWorkoutDraft.read(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('manual start and app checks use the same next-exercise policy', (
    t,
  ) async {
    await AndroidWorkoutDraft.clear();
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = true;
    RestTimerPreference.seconds = 90;
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          gymName: '自宅',
          resumeDraft: false,
          initialWorkout: WorkoutRecord(
            date: DateTime.now(),
            sets: const [
              RecordedSet(
                exerciseName: 'ベンチプレス',
                exerciseId: 'bench_press',
                weight: 80,
                reps: 10,
                completed: false,
              ),
              RecordedSet(
                exerciseName: 'ダンベルカール',
                exerciseId: 'dumbbell_curl',
                weight: 10,
                reps: 10,
                completed: false,
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final start = find.byKey(const Key('startRestTimerButton'));
    await t.ensureVisible(start);
    await t.tap(start);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    var status = (await channel.invokeMapMethod<String, dynamic>(
      'debugStatus',
    ))!;
    expect(
      (status['ongoingDetails'] as List).single['actions'],
      contains('セット完了'),
    );
    final first = find.byKey(const Key('toggleSet0_1'));
    await t.ensureVisible(first);
    await t.pumpAndSettle();
    await t.tap(first);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect((await RestNotificationService.state())!['exerciseName'], 'ダンベルカール');
    final last = find.byKey(const Key('toggleSet1_1'));
    await t.scrollUntilVisible(
      last,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(last);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect((await RestNotificationService.state())!['endsAtMilliseconds'], 0);
    status = (await channel.invokeMapMethod<String, dynamic>('debugStatus'))!;
    expect(status['delivered'], isNot(contains(7340)));
    await t.pumpWidget(const SizedBox());
    await AndroidWorkoutDraft.clear();
  });
  testWidgets(
    'notification PendingIntent completes a set without foregrounding the app',
    (t) async {
      if (!const bool.fromEnvironment('REST_BOUNDARY_HOST_QA')) return;
      await t.pumpWidget(const MaterialApp(home: Scaffold()));
      await AndroidWorkoutDraft.clear();
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      await start();
      final running = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      final details = (running['ongoingDetails'] as List).single as Map;
      expect(details['chronometer'], true);
      expect(details['countdown'], true);
      expect(details['actions'], ['停止', '+30秒', 'セット完了']);
      debugPrint('QA_REST_BOUNDARY_lock');
      await Future<void>.delayed(const Duration(seconds: 4));
      final before = (await channel.invokeMapMethod<String, dynamic>(
        'debugStatus',
      ))!;
      expect(before['foreground'], false);
      expect(before['keyguardLocked'], true);
      final ready = (before['ongoingDetails'] as List).single as Map;
      expect(ready['chronometer'], false);
      expect(ready['actions'], ['セット完了']);
      await channel.invokeMethod<void>('debugRestAction', {
        'action': 'completeNotification',
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final saved = await draft();
      expect(saved['exercises'][0]['sets'][1]['completed'], true);
      expect(saved['exercises'][0]['sets'][2]['completed'], false);
      expect(
        (await channel.invokeMapMethod<String, dynamic>(
          'debugStatus',
        ))!['foreground'],
        false,
      );
      debugPrint('QA_LOCK_SET_COMMITTED');
      await Future<void>.delayed(const Duration(seconds: 5));
      // Preserve this QA draft for host-side process-death durability inspection.
      await RestNotificationService.cancel();
    },
  );
}
