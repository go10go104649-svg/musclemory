import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:muscle_memory/services/android_workout_draft.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.musclememory/rest_timer');
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
      final id = await start();
      await action(id, 'set_1'); // still resting
      expect((await draft())['lockRevision'], 0);
      await Future<void>.delayed(const Duration(seconds: 3));
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
      expect((await RestNotificationService.state())!['endsAtMilliseconds'], 0);
      // A queued Flutter snapshot must not undo a committed background completion.
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      saved = await draft();
      expect(saved['exercises'][0]['sets'][1]['completed'], true);
      expect(saved['exercises'][0]['sets'][2]['completed'], true);
      await AndroidWorkoutDraft.clear();
    },
  );
  testWidgets(
    'foreground edits and removal invalidate old notification actions',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold()));
      await AndroidWorkoutDraft.write(jsonEncode(fixture()));
      final id = await start();
      await Future<void>.delayed(const Duration(seconds: 3));
      await AndroidWorkoutDraft.write(
        jsonEncode(fixture()..['note'] = 'edited'),
      );
      await action(id, 'set_1');
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
      expect(details['requestedPromotion'], true);
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
