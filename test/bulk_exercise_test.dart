import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bulk_exercise_flow.dart';

void main() {
  testWidgets(
    'menu multi-select keeps order, sets and edits without duplicates',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await verifyBulkExerciseFlow(tester);
    },
  );
}
