import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';

import '../test/workout_detail_ui_test.dart' as fixtures;
import 'exercise_form_expansion_test.dart' as captures;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('detail summary and exercise header display', (t) async {
    WorkoutUiPreference.workoutDurationEnabled = true;
    await t.pumpWidget(
      MaterialApp(home: fixtures.detailPage(fixtures.detailFixture())),
    );
    await t.pumpAndSettle();
    expect(find.text('1,200 kg'), findsOneWidget);
    expect(find.text('1分'), findsOneWidget);
    await captures.capture(binding, 'detail_summary');
    await t.pumpWidget(fixtures.headerFixture());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exerciseInputHeader0')), findsOneWidget);
    expect(find.byKey(const Key('exerciseInputHeader1')), findsOneWidget);
    await captures.capture(binding, 'exercise_headers');
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          initialWorkout: fixtures.detailFixture(),
          isEditing: true,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
    expect(find.byKey(const Key('exerciseInputHeader0')), findsOneWidget);
    await captures.capture(binding, 'edit_save_button');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
}
