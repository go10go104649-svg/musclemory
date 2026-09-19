import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/form_qa_plan.dart';

void main() {
  final known = {...FormQaPlan.defaultIds, 'low_row', 'dy_row', 'planned'};
  final assets = {...known}..remove('planned');
  FormQaPlan plan({String mode = 'full', String ids = '', String baseline = ''}) =>
      FormQaPlan.parse(
        mode: mode,
        selected: ids,
        baselineEvidence: baseline,
        knownIds: known,
        assetIds: assets,
      );

  test('default retains the full legacy sequence including reopening', () {
    final value = plan();
    expect(value.mode, 'full');
    expect(value.executionIds, FormQaPlan.defaultIds);
    expect(value.executionIds.length, 12);
    expect(value.executionIds.where((id) => id == 'mag_narrow').length, 2);
  });

  test('full explicit sequence preserves deliberate repeats', () {
    expect(plan(ids: ' low_row,dy_row,low_row ').executionIds,
        ['low_row', 'dy_row', 'low_row']);
  });

  test('invalid modes never silently fall back to full', () {
    for (final mode in ['', 'FULL', 'lite', ' light ']) {
      expect(() => plan(mode: mode), throwsArgumentError);
    }
  });

  test('unknown empty and path-like IDs are rejected', () {
    for (final ids in ['missing', 'low_row,', ' ', '../low_row']) {
      expect(() => plan(ids: ids), throwsArgumentError);
      expect(() => plan(mode: 'light', ids: ids, baseline: 'qa/evidence'),
          throwsArgumentError);
    }
  });

  test('entries without authored assets cannot run', () {
    expect(() => plan(ids: 'planned'), throwsArgumentError);
  });

  test('light mode requires explicit IDs and baseline evidence', () {
    expect(() => plan(mode: 'light'), throwsArgumentError);
    expect(() => plan(mode: 'light', ids: 'low_row'), throwsArgumentError);
    expect(() => plan(mode: 'light', baseline: 'qa/evidence'), throwsArgumentError);
    expect(() => plan(mode: 'light', ids: 'low_row', baseline: ' '),
        throwsArgumentError);
  });

  test('light mode opens and reopens every selected scene', () {
    final value = plan(mode: 'light', ids: 'low_row,dy_row', baseline: 'qa/evidence');
    expect(value.executionIds, ['low_row', 'low_row', 'dy_row', 'dy_row']);
    expect(value.isLight, isTrue);
  });

  test('light rejects redundant IDs instead of multiplying work', () {
    expect(() => plan(mode: 'light', ids: 'low_row,low_row', baseline: 'qa/evidence'),
        throwsArgumentError);
  });

  test('selection cannot change after validation', () {
    expect(() => plan(ids: 'low_row').ids.add('planned'), throwsUnsupportedError);
  });

  test('light report records omissions and grants no review approval', () {
    final value = plan(mode: 'light', ids: 'low_row', baseline: 'qa/full-ios');
    final report = value.report();
    expect(report['reviewApproved'], isFalse);
    expect(report['declaredBaselineEvidence'], 'qa/full-ios');
    expect(report['notChecked'], contains('half-speed playback'));
    expect(report['notChecked'], contains('production route (separate test)'));
    expect(report.containsKey('verified'), isFalse);
    expect(known, contains('planned'));
    expect(assets, isNot(contains('planned')));
  });
}
