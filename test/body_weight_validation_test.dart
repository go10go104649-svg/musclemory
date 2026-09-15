import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/body_weight.dart';
import 'package:muscle_memory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a malformed entry does not hide other saved weights', () async {
    SharedPreferences.setMockInitialValues({
      BodyWeightPreference.storageKey: jsonEncode([
        {'id': 'good', 'recordedAt': '2026-09-14', 'weightKg': 82.5},
        {'recordedAt': 123, 'weightKg': 70},
        {'recordedAt': '2026-09-14', 'weightKg': 'broken'},
        {'id': 42, 'recordedAt': '2026-09-14', 'weightKg': 70},
      ]),
    });
    expect((await BodyWeightPreference.load()).single.weightKg, 82.5);
  });

  test('non-finite values are rejected on import', () {
    for (final weight in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        BodyWeightEntry.tryFromJson({
          'recordedAt': '2026-09-14',
          'weightKg': weight,
        }),
        isNull,
      );
    }
  });

  testWidgets('invalid input remains editable and cannot close the editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const BodyWeightEditorDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final input in ['NaN', 'Infinity', '1e999', '0', '-2']) {
      await tester.enterText(find.byKey(const Key('bodyWeightField')), input);
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();
      expect(find.text('体重を正しく入力してください'), findsOneWidget);
      expect(find.byType(BodyWeightEditorDialog), findsOneWidget);
    }
    await tester.enterText(find.byKey(const Key('bodyWeightField')), '82,5');
    await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
    await tester.pumpAndSettle();
    expect(find.byType(BodyWeightEditorDialog), findsNothing);
  });
}
