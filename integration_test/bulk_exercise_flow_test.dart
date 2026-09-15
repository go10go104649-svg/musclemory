import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/bulk_exercise_flow.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bulk menu selection and recording on dedicated QA device', (
    tester,
  ) async {
    var converted = false;
    await verifyBulkExerciseFlow(
      tester,
      screenshot: (name) async {
        if (Platform.isAndroid && !converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pumpAndSettle();
        }
        await binding.takeScreenshot(name);
      },
    );
  });
}
