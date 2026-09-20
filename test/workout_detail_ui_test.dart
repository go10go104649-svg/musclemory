import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/main.dart';

WorkoutRecord detailFixture({int duration = 60, double weight = 40}) =>
    WorkoutRecord(
      date: DateTime(2026, 9, 21),
      durationSeconds: duration,
      sets: [
        for (var i = 0; i < 3; i++)
          RecordedSet(weight: weight, reps: 10, completed: true),
      ],
    );
WorkoutDetailPage detailPage(WorkoutRecord record) => WorkoutDetailPage(
  workout: record,
  selectedGym: null,
  onWorkoutCompleted: (_) async {},
  onWorkoutUpdated: (_, _) async {},
  onWorkoutDeleted: (_) async => false,
);
Widget headerFixture() => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Column(
        children: [
          for (final (index, name) in [(0, 'ベンチプレス'), (1, 'ショルダープレス')])
            ExerciseInputCard(
              exerciseIndex: index,
              exercise: WorkoutExercise(
                name: name,
                bodyPart: index == 0 ? '胸' : '肩',
                equipment: 'フリーウェイト',
                recordType: ExerciseRecordType.weightReps,
                sets: [WorkoutSet(weight: 40, reps: 10)],
              ),
              history: const [],
              onAddSet: () {},
              onRemoveSet: (_) {},
              onRemove: () {},
              onToggleSet: (_) {},
              onApplyPrevious: (_) {},
              onSetAllCompleted: (_) {},
              onValuesChanged: () {},
            ),
        ],
      ),
    ),
  ),
);
void main() {
  setUp(() => WorkoutUiPreference.workoutDurationEnabled = true);
  tearDown(() => WorkoutUiPreference.workoutDurationEnabled = true);
  testWidgets(
    'detail uses one calendar-style summary with four values without changing shared summary',
    (t) async {
      final record = detailFixture();
      expect(record.summaryLabel, '1種目 ・ 3セット ・ 1,200 kg ・ 1分');
      await t.pumpWidget(MaterialApp(home: detailPage(record)));
      await t.pumpAndSettle();
      expect(find.text(record.summaryLabel), findsNothing);
      for (final text in ['1 種目', '3 セット', '1,200 kg', '1分']) {
        final value = t.widget<Text>(find.text(text));
        expect(value.maxLines, 1);
        expect(value.softWrap, false);
      }
      final rects = [
        for (final label in ['種目数', 'セット数', '総ボリューム', 'トレーニング時間'])
          t.getRect(find.byKey(Key('detailSummaryValue$label'))),
      ];
      expect(rects.map((r) => r.top).toSet().length, 1);
      expect(t.takeException(), isNull);
    },
  );
  for (final duration in [0, 60]) {
    testWidgets('duration conditional: $duration', (t) async {
      if (duration > 0) WorkoutUiPreference.workoutDurationEnabled = false;
      await t.pumpWidget(
        MaterialApp(home: detailPage(detailFixture(duration: duration))),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('detailSummaryValueトレーニング時間')), findsNothing);
      expect(find.byKey(const Key('detailSummaryValue総ボリューム')), findsOneWidget);
    });
  }
  testWidgets('large values and text scale fit one row at 280px', (t) async {
    final record = detailFixture(weight: 12345678);
    // Isolate the requested summary from unchanged detail rows at large text scale.
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final page = detailPage(record).build(context) as Scaffold;
            final list = page.body! as ListView;
            final children =
                (list.childrenDelegate as SliverChildListDelegate).children;
            return Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: children[2],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('${formatVolumeKg(record.volume)} kg'), findsOneWidget);
    expect(find.byType(FittedBox), findsNWidgets(8));
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'only exercise headers are lime with readable text and remove icons',
    (t) async {
      await t.pumpWidget(headerFixture());
      await t.pumpAndSettle();
      for (final index in [0, 1]) {
        final header = find.byKey(Key('exerciseInputHeader$index'));
        final box = t.widget<Container>(header).decoration as BoxDecoration;
        expect(box.color, const Color(0xFFC7F36B));
        for (final text in t.widgetList<Text>(
          find.descendant(of: header, matching: find.byType(Text)),
        )) {
          expect(text.style!.color, const Color(0xFF101820));
        }
        expect(
          find.descendant(of: header, matching: find.byTooltip('種目を削除')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: header, matching: find.byType(ValueBox)),
          findsNothing,
        );
      }
      expect(find.text('前回の記録はありません'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    },
  );
}
