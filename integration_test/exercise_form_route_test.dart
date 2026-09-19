import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/bench_press_form.dart';
import 'package:muscle_memory/exercise_form_catalog.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_form_expansion_test.dart' as playback;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'category list opens the matching native form through detail route',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const selected = String.fromEnvironment(
        'FORM_QA_IDS',
        defaultValue: 'bench_press,incline_dumbbell_press',
      );
      for (final id in selected.split(',')) {
        final form = ExerciseFormCatalog.byId[id]!;
        expect(
          form.available,
          isTrue,
          reason: 'Review candidate must be enabled: $id',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExercisePickerSheet(
                key: UniqueKey(),
                existingNames: const {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('exerciseCategory${form.category}')));
        await tester.pumpAndSettle();
        final button = find.byKey(Key('exerciseMuscles${form.exerciseName}'));
        await tester.scrollUntilVisible(
          button,
          300,
          scrollable: find.descendant(
            of: find.byKey(ValueKey('exercisePickerList${form.category}')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(button);
        for (var attempt = 0; attempt < 20; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.byType(ExerciseMuscleDetailPage).evaluate().isNotEmpty) {
            break;
          }
        }
        expect(find.byType(ExerciseMuscleDetailPage), findsOneWidget);
        expect(find.byType(ExerciseFormView), findsOneWidget);
        expect(
          tester
              .widget<ExerciseFormView>(find.byType(ExerciseFormView))
              .exerciseName,
          form.exerciseName,
        );
        for (final label in [
          ...form.primaryMuscleLabels,
          ...form.secondaryMuscleLabels,
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        var visible = false;
        for (var attempt = 0; attempt < 25; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          await tester.pump();
          expect(find.textContaining('読み込めませんでした'), findsNothing);
          if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
            continue;
          }
          final bytes = await playback.capture(
            binding,
            'route_${id}_warming',
            record: !Platform.isAndroid,
          );
          if (await playback.brightSceneFraction(tester, bytes) > .015) {
            visible = true;
            break;
          }
        }
        expect(visible, isTrue, reason: 'Detail route native scene: $id');
        await Future<void>.delayed(const Duration(seconds: 4));
        await tester.pump();
        await playback.capture(binding, 'route_$id');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ExerciseFormView), findsNothing);
        expect(button, findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
