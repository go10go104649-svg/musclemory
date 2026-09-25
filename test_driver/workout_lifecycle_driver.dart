import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['SETKEEP_QA_OUTPUT'] ??
        Platform.environment['MUSCLEMORY_QA_OUTPUT'] ??
        'docs/qa/workout_lifecycle_2026-09-14',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
