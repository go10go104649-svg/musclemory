import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/workout_completion_test.dart' as fixtures;

/// Run only on disposable QA devices. First launch waits in the completion
/// dialog for host-side process termination; second launch verifies real disk data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('completed workout survives process termination at dialog', (
    t,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    const marker = 'qa_completion_restart_pending';
    final restarting = prefs.getBool(marker) ?? false;
    WorkoutUiPreference.completionCheckEnabled = true;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = true;
    RestTimerPreference.enabled = false;
    if (!restarting) {
      await prefs.setString('workout_history', '[]');
      await prefs.setString(activeWorkoutDraftStorageKey, fixtures.draft());
    }
    await t.pumpWidget(const MaterialApp(home: HomeShell()));
    await t.pumpAndSettle();
    if (!restarting) {
      await t.tap(find.byKey(const Key('activeWorkoutDraftCard')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('completeWorkoutButton')));
      await t.pumpAndSettle();
      expect(find.text('トレーニング完了'), findsOneWidget);
      expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
      expect(
        decodeWorkoutHistory(prefs.getString('workout_history')),
        hasLength(1),
      );
      await prefs.setBool(marker, true);
      debugPrint('COMPLETION_READY_FOR_PROCESS_TERMINATION');
      await Future<void>.delayed(const Duration(minutes: 2));
      fail('Host must terminate this QA process while the dialog is open');
    } else {
      expect(prefs.getString(activeWorkoutDraftStorageKey), isNull);
      expect(find.byKey(const Key('activeWorkoutDraftCard')), findsNothing);
      final saved = decodeWorkoutHistory(prefs.getString('workout_history'));
      expect(saved, hasLength(1));
      expect(saved.single.sets.single.weight, 65);
      expect(saved.single.sets.single.reps, 8);
      expect(saved.single.gymName, 'テストジム');
      expect(saved.single.note, '保存確認');
      expect(saved.single.date, DateTime(2026, 9, 20, 18, 30));
      await t.tap(find.byIcon(Icons.calendar_month_outlined));
      await t.pumpAndSettle();
      expect(
        t.widget<MonthlyHistoryPage>(find.byType(MonthlyHistoryPage)).history,
        hasLength(1),
      );
      await prefs.remove(marker);
      debugPrint('COMPLETION_RESTART_VERIFIED');
    }
  });
}
