import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/workout_layout_test.dart' as fixtures;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('workout layout native controls, scrolling and keypad', (
    t,
  ) async {
    await fixtures.prepareLayoutPreferences();
    await t.pumpWidget(fixtures.layoutApp());
    await t.pumpAndSettle();
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await t.pumpAndSettle();
    }
    await binding.takeScreenshot('workout_layout_top');
    await t.tap(find.byKey(const Key('startRestTimerButton')));
    await t.pump();
    await t.tap(find.byKey(const Key('stopRestTimerButton')));
    await t.pump();
    final remaining = t
        .widget<Text>(find.byKey(const Key('restRemainingLabel')))
        .data;
    await t.pump(const Duration(seconds: 2));
    expect(
      t.widget<Text>(find.byKey(const Key('restRemainingLabel'))).data,
      remaining,
    );
    await t.tap(find.text('+30秒'));
    await t.pump();
    expect(
      t.widget<Text>(find.byKey(const Key('restRemainingLabel'))).data,
      isNot(remaining),
    );
    final check = find.byKey(const Key('toggleSet0_1'));
    await t.ensureVisible(check);
    await t.pumpAndSettle();
    final position = t.getCenter(check);
    await t.tap(check);
    await t.pump();
    expect(t.getCenter(check), position);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await fixtures.prepareLayoutPreferences();
    await t.pumpWidget(
      fixtures.layoutApp(
        record: fixtures.layoutFixture(exercises: 11, sets: 11),
      ),
    );
    await t.pumpAndSettle();
    final input = find.byKey(const Key('weightField10_11'));
    await t.ensureVisible(input);
    await t.pumpAndSettle();
    await t.tap(input);
    await t.pumpAndSettle();
    final pad = find.byKey(const Key('workoutNumericKeypad'));
    expect(pad, findsOneWidget);
    expect(t.getRect(input).bottom, lessThanOrEqualTo(t.getRect(pad).top));
    await binding.takeScreenshot('workout_layout_bottom_keypad');
    if (Platform.isAndroid) {
      await binding.handlePopRoute();
    } else {
      await t.tap(find.byKey(const Key('closeNumericKeypad')));
    }
    await t.pumpAndSettle();
    expect(pad, findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
}
