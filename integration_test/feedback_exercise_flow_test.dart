import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_form_expansion_test.dart' as captures;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('incline fly selection recording sharing and saved history', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'rest_timer_enabled': false,
      'completion_check_enabled': true,
    });
    await RestTimerPreference.load();
    await WorkoutUiPreference.load();
    await tester.pumpWidget(const SetkeepApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addExerciseButton')));
    await tester.tap(find.byKey(const Key('addExerciseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseCategory胸')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('exerciseSearchField')),
      'Incline Fly Machine',
    );
    await tester.pumpAndSettle();
    expect(find.text('インクラインフライマシン'), findsOneWidget);
    await tester.tap(find.text('インクラインフライマシン'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSelectedExercises')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('weightField0_1')), '32.5');
    await tester.enterText(find.byKey(const Key('repsField0_1')), '12');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('addSetButton')));
    await tester.tap(find.byKey(const Key('addSetButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('toggleAllSets0')));
    await tester.tap(find.byKey(const Key('toggleAllSets0')));
    await tester.pump();
    await captures.capture(binding, 'incline_fly_record');
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeAndPreviewShareButton')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutSharePage), findsOneWidget);
    expect(find.text('インクラインフライマシン'), findsOneWidget);
    await captures.capture(binding, 'incline_fly_share');
    await tester.pageBack();
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('workout_history'), contains('インクラインフライマシン'));
    expect(prefs.getString('workout_history'), contains('32.5'));
    await tester.tap(find.text('履歴').last);
    await tester.pumpAndSettle();
    expect(find.byType(MonthlyHistoryPage), findsOneWidget);
    await captures.capture(binding, 'incline_fly_history');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
