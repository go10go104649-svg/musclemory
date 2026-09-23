import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:muscle_memory/config/supabase_config.dart';
import 'package:muscle_memory/gym/gym_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('live FIT PLACE search equipment exercise and workout draft', (
    t,
  ) async {
    await SupabaseConfig.initialize();
    expect(SupabaseConfig.initialized, isTrue);
    SharedPreferences.setMockInitialValues({});
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = false;
    final repo = SupabaseGymRepository();
    final stores = await repo.search('札幌北32条');
    expect(stores, isNotEmpty);
    final store = stores.first;
    final equipment = await repo.equipment(store.id);
    final target = equipment.firstWhere((e) => e.exerciseIds.isNotEmpty);
    final exerciseId = target.exerciseIds.first;
    Future<void> settleUntil(Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
      await t.pumpAndSettle();
    }

    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const WorkoutPage(),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('workoutGymButton')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('searchRegisteredGymStores')));
    await t.pump();
    await t.enterText(find.byKey(const Key('gymStoreSearchField')), '札幌北32条');
    await settleUntil(find.byKey(Key('selectGymStore${store.id}')));
    await t.tap(find.byKey(Key('selectGymStore${store.id}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('workoutGymEquipmentButton')));
    await t.pump();
    await settleUntil(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('gymEquipment'),
      ),
    );
    await t.scrollUntilVisible(
      find.byKey(Key('gymEquipment${target.id}')),
      300,
      scrollable: find.byType(Scrollable),
    );
    await t.ensureVisible(find.byKey(Key('gymEquipment${target.id}')));
    await t.tap(find.byKey(Key('gymEquipment${target.id}')));
    await t.pumpAndSettle();
    final add = find.byKey(Key('addGymExercise$exerciseId'));
    await t.ensureVisible(add);
    await t.tap(add);
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exerciseInputHeader0')), findsOneWidget);
    final p = await SharedPreferences.getInstance();
    final draft = jsonDecode(p.getString(activeWorkoutDraftStorageKey)!);
    expect(draft['gymStoreId'], store.id);
    expect((draft['exercises'] as List).single['exerciseId'], exerciseId);
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await t.pumpAndSettle();
    }
    await binding.takeScreenshot('gym_store_exercise_added');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}
