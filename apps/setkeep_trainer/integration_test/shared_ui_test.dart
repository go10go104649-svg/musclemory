// Run only on disposable QA simulators/emulators. No Auth or production DB is used.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/design/family_theme.dart';
import 'package:setkeep/main.dart' show ExerciseInputCard, ExercisePickerSheet;
import 'package:setkeep_trainer/menu_editor.dart';
import 'package:setkeep_trainer/trainer_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/trainer_app_test.dart' show FakeRepository, link, menuFixture;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native shared body, per-set editor and category assets', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: HeatmapPage(
          workouts: [
            {
              'performed_at': DateTime.now().toIso8601String(),
              'duration_seconds': 0,
              'sets': [
                {
                  'exerciseId': 'bench_press',
                  'exerciseName': 'ベンチプレス',
                  'bodyPart': '胸',
                  'weight': 20.0,
                  'reps': 10,
                  'completed': true,
                },
              ],
            },
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 5));
    await t.pump();
    expect(find.byKey(const Key('muscleModel3D')), findsOneWidget);
    debugPrint('TENANT_QA_BODY_READY');
    await Future<void>.delayed(const Duration(seconds: 15));
    await t.pumpWidget(
      MaterialApp(
        theme: familyTheme(FamilyPalette.trainer),
        home: MenuEditor(
          repository: FakeRepository(),
          clients: [link()],
          existing: menuFixture(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(ExerciseInputCard), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('addSetButton')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('addSetButton')));
    await t.pumpAndSettle();
    expect(
      t.widget<ExerciseInputCard>(find.byType(ExerciseInputCard)).exercise.sets,
      hasLength(3),
    );
    expect(find.byKey(const Key('toggleAllSets0')), findsNothing);
    debugPrint('TENANT_QA_EDITOR_READY');
    await Future<void>.delayed(const Duration(seconds: 15));
    await t.scrollUntilVisible(
      find.text('Add exercise'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Add exercise'));
    await t.pumpAndSettle();
    expect(find.byType(ExercisePickerSheet), findsOneWidget);
    debugPrint('TENANT_QA_PICKER_READY');
    await Future<void>.delayed(const Duration(seconds: 15));
    expect(t.takeException(), isNull);
  });
}
