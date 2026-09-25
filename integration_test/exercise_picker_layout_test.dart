import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/config/supabase_config.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:setkeep/gym/training_place_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'store picker prioritizes the list with the real Android keyboard',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      await SupabaseConfig.initialize();
      expect(SupabaseConfig.initialized, true);
      final repo = SupabaseGymRepository();
      final stores = await repo.searchStores('カネキン');
      final store = stores.singleWhere(
        (s) => s.id == 'kanekin-fitness-gym:matsudo',
      );
      WorkoutUiPreference.workoutTimerEnabled = false;
      WorkoutUiPreference.workoutDurationEnabled = false;
      RestTimerPreference.enabled = false;
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            initialPlace: TrainingPlace.store(store),
            resumeDraft: false,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('addExerciseButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('addExerciseButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('storeExerciseFilter')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('exercisePickerHeader')),
          matching: find.byKey(const Key('reportStoreExercises')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('storeExerciseCount')), findsNothing);
      final list = find.byKey(const Key('exercisePickerListClip'));
      expect(t.getSize(list).height, greaterThan(280));
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await t.pumpAndSettle();
      }
      await binding.takeScreenshot('picker_categories_compact');
      await t.tap(find.byKey(const Key('exerciseCategory胸')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('addCustomExerciseForCategory')),
        findsOneWidget,
      );
      expect(t.getSize(list).height, greaterThan(280));
      await binding.takeScreenshot('picker_exercises_compact');
      await t.tap(find.byKey(const Key('exerciseSearchField')));
      await Future<void>.delayed(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(
        MediaQuery.viewInsetsOf(t.element(find.byType(ExercisePickerSheet)))
            .bottom,
        greaterThan(0),
      );
      expect(t.getSize(list).height, greaterThan(60));
      expect(
        find.byKey(const Key('addSelectedExercises')).hitTestable(),
        findsOneWidget,
      );
      await binding.takeScreenshot('picker_keyboard_compact');
      debugPrint('QA_PICKER_KEYBOARD_READY');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
    },
  );
}
