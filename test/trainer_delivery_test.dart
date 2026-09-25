import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/trainer/trainer_inbox_page.dart';
import 'package:setkeep/trainer/trainer_menu_codec.dart';

import 'support/trainer_delivery_flow.dart';

void main() {
  trainerDeliveryNativeFlow();
  test('one codec preserves exercise/set order and all SK numeric fields', () {
    final row = TrainerMenuCodec.fromRow({
      'id': 'menu',
      'tenant_menu_exercises': [
        {
          'position': 2,
          'exercise_id': 'run',
          'exercise_name': 'Run',
          'record_type': 'cardio',
          'tenant_menu_sets': [
            {
              'position': 1,
              'values': {
                'durationSeconds': 123,
                'distanceKm': 1.23,
                'speedKmh': 12.3,
                'inclinePercent': 4.5,
                'resistanceLevel': 6.7,
                'paceSecondsPerKm': 345,
                'distanceUnit': 'm',
              },
            },
          ],
        },
        {
          'position': 1,
          'exercise_id': 'bench_press',
          'exercise_name': 'Bench',
          'record_type': 'weightReps',
          'tenant_menu_sets': [
            {
              'position': 2,
              'values': {'weight': 25.5, 'reps': 8},
            },
            {
              'position': 1,
              'values': {'weight': 20.5, 'reps': 10},
            },
          ],
        },
      ],
    });
    final workout = TrainerMenuCodec.workout(row);
    final editable = TrainerMenuCodec.exercises(row['items'] as List);
    expect(workout.sets.map((s) => s.exerciseId), [
      'bench_press',
      'bench_press',
      'run',
    ]);
    expect(editable.first.sets.map((s) => s.weight), [20.5, 25.5]);
    final run = workout.sets.last;
    expect(run.durationSeconds, 123);
    expect(run.distanceKm, 1.23);
    expect(run.speedKmh, 12.3);
    expect(run.inclinePercent, 4.5);
    expect(run.resistanceLevel, 6.7);
    expect(run.paceSecondsPerKm, 345);
    expect(editable.last.distanceUnit, 'm');
    expect(editable.last.sets.single.durationSeconds, run.durationSeconds);
    expect(workout.sets.every((s) => !s.completed), true);
  });
  testWidgets(
    'refresh reflects menu update and comment update/delete without copies',
    (t) async {
      final repo = DeliveryRepository();
      addTearDown(repo.auth.close);
      await t.pumpWidget(
        MaterialApp(
          home: TrainerInboxPage(repository: repo, onStart: (_) async {}),
        ),
      );
      await t.pumpAndSettle();
      repo.version = 2;
      repo.body = 'Edited comment';
      await t.tap(find.byKey(const Key('refreshTrainerInbox')));
      await t.pumpAndSettle();
      expect(find.text('Coach plan v1'), findsNothing);
      expect(find.text('Coach plan v2'), findsOneWidget);
      expect(find.text('Edited comment'), findsOneWidget);
      repo.deleted = true;
      repo.canceled = true;
      await t.tap(find.byKey(const Key('refreshTrainerInbox')));
      await t.pumpAndSettle();
      expect(find.text('Edited comment'), findsNothing);
      expect(find.text('Coach plan v2'), findsNothing);
    },
  );
  testWidgets('start rechecks version/cancel state; stale menu cannot start', (
    t,
  ) async {
    final repo = DeliveryRepository();
    addTearDown(repo.auth.close);
    var starts = 0;
    await t.pumpWidget(
      MaterialApp(
        home: TrainerInboxPage(
          repository: repo,
          onStart: (_) async {
            starts++;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    repo.version = 2;
    await t.tap(find.byKey(const ValueKey('startTrainerMenu:menu-a')));
    await t.pumpAndSettle();
    expect(starts, 0);
    expect(find.text('Coach plan v2'), findsOneWidget);
    repo.canceled = true;
    await t.tap(find.byKey(const ValueKey('startTrainerMenu:menu-a')));
    await t.pumpAndSettle();
    expect(starts, 0);
    expect(find.text('Coach plan v2'), findsNothing);
  });
  testWidgets('account switch discards late A response and clears comments', (
    t,
  ) async {
    final repo = DeliveryRepository();
    addTearDown(repo.auth.close);
    final delayed = Completer<List<Map<String, dynamic>>>();
    repo.pending = delayed;
    await t.pumpWidget(
      MaterialApp(
        home: TrainerInboxPage(repository: repo, onStart: (_) async {}),
      ),
    );
    await t.pump();
    repo.pending = null;
    repo.userId = 'user-b';
    repo.auth.add(null);
    await t.pumpAndSettle();
    delayed.complete([deliveryMenu()]);
    await t.pumpAndSettle();
    expect(find.text('Coach plan v1'), findsNothing);
    expect(find.text('Coach comment'), findsNothing);
    repo.userId = null;
    repo.auth.add(null);
    await t.pumpAndSettle();
    expect(find.text('Sign in from Account on your profile.'), findsOneWidget);
  });
  testWidgets(
    'failed refresh removes stale private content and supports retry',
    (t) async {
      final repo = DeliveryRepository();
      addTearDown(repo.auth.close);
      await t.pumpWidget(
        MaterialApp(
          home: TrainerInboxPage(repository: repo, onStart: (_) async {}),
        ),
      );
      await t.pumpAndSettle();
      repo.fail = true;
      await t.tap(find.byKey(const Key('refreshTrainerInbox')));
      await t.pumpAndSettle();
      expect(find.text('Coach comment'), findsNothing);
      expect(find.byKey(const Key('trainerInboxError')), findsOneWidget);
      repo.fail = false;
      await t.tap(find.byKey(const Key('refreshTrainerInbox')));
      await t.pumpAndSettle();
      expect(find.text('Coach comment'), findsOneWidget);
    },
  );
}
