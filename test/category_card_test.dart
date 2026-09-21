import 'support/bulk_exercise_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/body_part_illustration.dart';
import 'package:muscle_memory/main.dart';

void main() {
  testWidgets(
    'small picker wraps heading and opens scrolled category at the top',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: ExercisePickerSheet(existingNames: <String>{}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final legs = find.byKey(const Key('exerciseCategory脚'));
      await tester.scrollUntilVisible(
        legs,
        180,
        scrollable: exercisePickerScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(legs);
      await tester.pumpAndSettle();
      expect(find.text('脚の種目'), findsOneWidget);
      expect(find.byKey(const Key('exerciseSearchField')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'category cards fit 320px with text scale $scale and remain selectable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final categories = BodyPartIllustration.assets.keys.toList();
        final selected = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 568),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final category in categories)
                      BodyPartCategoryCard(
                        category: category,
                        label: category == '腹' ? '腹筋' : category,
                        count: 123,
                        onTap: () => selected.add(category),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heights = <double>{};
        for (final category in categories) {
          final card = find.byKey(Key('exerciseCategory$category'));
          await tester.scrollUntilVisible(card, 150, scrollable: find.byType(Scrollable));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          heights.add(tester.getSize(card).height);
          final art = find.descendant(
            of: card,
            matching: find.byType(BodyPartIllustration),
          );
          expect(
            find.descendant(of: art, matching: find.byType(CustomPaint)),
            findsNothing,
          );
          expect(
            find.descendant(of: art, matching: find.byType(Image)),
            findsOneWidget,
          );
          final image = tester.widget<Image>(find.descendant(of: art, matching: find.byType(Image)));
          expect((image.image as AssetImage).assetName,
              'assets/category_muscles/${BodyPartIllustration.assets[category]}.png');
          expect(find.descendant(of: art, matching: find.byType(Icon)), findsNothing);
          await tester.tap(card);
        }
        expect(selected, categories);
        if (scale == 1) expect(heights, hasLength(1));
      },
    );
  }
}
