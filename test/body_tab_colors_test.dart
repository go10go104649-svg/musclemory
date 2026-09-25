import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/body_tab_colors.dart';
import 'package:setkeep/muscle_targets.dart';

void main() {
  test(
    'annual category example uses exact maximum ratios, not muscle weights',
    () {
      final values = bodyTabRelativeIntensities({
        '胸': 200,
        '背中': 180,
        '脚': 80,
        '肩': 60,
        '腕': 50,
        '腹': 30,
      });
      expect(values[MuscleRegion.pectoralisMajor], 1);
      expect(values[MuscleRegion.latissimusDorsi], .9);
      expect(values[MuscleRegion.trapezius], .9);
      expect(values[MuscleRegion.quadriceps], .4);
      expect(values[MuscleRegion.anteriorDeltoid], .3);
      expect(values[MuscleRegion.triceps], .25);
      expect(values[MuscleRegion.rectusAbdominis], .15);
    },
  );
  test('scale and period length cannot change the balance colors', () {
    final small = bodyTabRelativeIntensities({'胸': 4, '脚': 1});
    final large = bodyTabRelativeIntensities({'胸': 400, '脚': 100});
    expect(small, large);
    for (final region in MuscleRegion.values) {
      expect(
        bodyTabMaterialColor(small[region]!),
        bodyTabMaterialColor(large[region]!),
      );
    }
  });
  test(
    'zero resets every mask; a single set is maximum with no zero division',
    () {
      final zero = bodyTabRelativeIntensities({});
      expect(zero.values.every((v) => v == 0 && v.isFinite), isTrue);
      final one = bodyTabRelativeIntensities({'腕': 1, '有酸素': 100});
      expect(one[MuscleRegion.forearms], 1);
      expect(one[MuscleRegion.pectoralisMajor], 0);
      expect(bodyTabHeatColor(0), isNot(bodyTabHeatColor(.01)));
    },
  );
}
