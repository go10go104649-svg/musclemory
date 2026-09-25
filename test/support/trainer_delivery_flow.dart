import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/trainer/trainer_inbox_page.dart';
import 'package:setkeep/trainer/trainer_inbox_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> deliveryMenu({int version = 1}) => {
  'id': 'menu-a',
  'client_id': 'client-a',
  'tenant_id': 'tenant-a',
  'name': 'Coach plan v$version',
  'note': 'Controlled movement',
  'status': 'planned',
  'schedule': 'single',
  'version': version,
  'updated_at': '2026-09-25',
  'items': [
    {
      'exercise_id': 'bench_press',
      'exercise_name': 'ベンチプレス',
      'body_part': '胸',
      'equipment': 'バーベル',
      'record_type': 'weightReps',
      'set_values': [
        {'weight': version == 1 ? 20.0 : 30.0, 'reps': 10},
        {'weight': 25.0, 'reps': 8},
      ],
    },
  ],
};

class DeliveryRepository implements TrainerInboxRepository {
  @override
  String? userId = 'user-a';
  final auth = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get authChanges => auth.stream;
  int version = 1;
  bool canceled = false, deleted = false, fail = false;
  String body = 'Coach comment';
  Completer<List<Map<String, dynamic>>>? pending;
  @override
  Future<List<Map<String, dynamic>>> menus({int offset = 0}) async {
    if (fail) throw StateError('offline');
    if (pending != null) return pending!.future;
    return userId == 'user-a' && !canceled
        ? [deliveryMenu(version: version)]
        : [];
  }

  @override
  Future<List<Map<String, dynamic>>> comments({int offset = 0}) async =>
      userId == 'user-a' && !deleted
      ? [
          {
            'id': 'comment-a',
            'body': body,
            'updated_at': '2026-09-25',
            'menu_id': 'menu-a',
          },
        ]
      : [];
  @override
  Future<Map<String, dynamic>?> menu(String id) async =>
      userId == 'user-a' && !canceled ? deliveryMenu(version: version) : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The fixture replaces only the cloud boundary. Uses the actual SK workout UI.
void trainerDeliveryNativeFlow() {
  testWidgets(
    'shared menu opens standard SK workout with exact per-set targets',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      WorkoutUiPreference.workoutTimerEnabled = false;
      RestTimerPreference.enabled = false;
      final repo = DeliveryRepository();
      addTearDown(repo.auth.close);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TrainerInboxPage(
              repository: repo,
              onStart: (record) async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => WorkoutPage(
                      initialWorkout: record,
                      resumeDraft: false,
                      useDefaultPlace: true,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Coach comment'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('startTrainerMenu:menu-a')));
      await t.pumpAndSettle();
      expect(find.byType(WorkoutPage), findsOneWidget);
      expect(find.byType(ExerciseInputCard), findsOneWidget);
      final exercise = t
          .widget<ExerciseInputCard>(find.byType(ExerciseInputCard))
          .exercise;
      expect(exercise.exerciseId, 'bench_press');
      expect(exercise.sets.map((s) => s.weight), [20.0, 25.0]);
      expect(exercise.sets.map((s) => s.reps), [10, 8]);
      expect(exercise.sets.every((s) => !s.completed), true);
      expect(find.byKey(const Key('completeWorkoutButton')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
}
