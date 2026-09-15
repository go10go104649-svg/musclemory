import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscle_memory/main.dart';
import 'package:muscle_memory/body_weight.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Run only through tool/verify_workout_lifecycle.sh on a dedicated QA device.
// This test deliberately exercises the native preferences implementation.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('weight input edit and reload preserve native saved data', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final originalHistory = prefs.getString('workout_history');
    final before = await BodyWeightPreference.load();
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    Future<void> history() async {
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('addBodyWeightButton')));
      await tester.pumpAndSettle();
    }

    await history();
    await tester.tap(find.byKey(const Key('addBodyWeightButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bodyWeightField')), '82.5');
    await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
    await tester.pumpAndSettle();
    await prefs.reload();
    var saved = await BodyWeightPreference.load();
    expect(saved.length, before.length + 1);
    final id = saved.last.id;
    expect(saved.last.weightKg, 82.5);
    await tester.ensureVisible(find.byKey(const Key('bodyWeightChart')));
    await tester.pumpAndSettle();
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
    }
    await binding.takeScreenshot('body_weight_saved');
    await tester.ensureVisible(find.byKey(Key('editBodyWeight$id')));
    await tester.tap(find.byKey(Key('editBodyWeight$id')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bodyWeightField')), '81.9');
    await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await prefs.reload();
    saved = await BodyWeightPreference.load();
    expect(saved.length, before.length + 1);
    expect(saved.singleWhere((entry) => entry.id == id).weightKg, 81.9);
    expect(prefs.getString('workout_history'), originalHistory);
    expect(
      jsonDecode(prefs.getString(BodyWeightPreference.storageKey)!),
      isA<List>(),
    );
    await tester.pumpWidget(const MuscleMemoryApp());
    await tester.pumpAndSettle();
    await history();
    await tester.ensureVisible(find.byKey(const Key('bodyWeightChart')));
    await tester.tap(find.byKey(const Key('bodyWeightChart')));
    await tester.pumpAndSettle();
    expect(find.textContaining('81.9 kg'), findsWidgets);
    await binding.takeScreenshot('body_weight_edited_reloaded');
    expect(tester.takeException(), isNull);
  });
}
