// Authoring-only entry point; never referenced by the production app.
// flutter run -t tool/exercise_forms/preview.dart --dart-define=FORM_PREVIEW_ID=mag_narrow
import 'package:flutter/material.dart';
import 'package:setkeep/bench_press_form.dart';
import 'package:setkeep/exercise_form_catalog.dart';

void main() {
  const id = String.fromEnvironment(
    'FORM_PREVIEW_ID',
    defaultValue: 'mag_narrow',
  );
  final form = ExerciseFormCatalog.byId[id];
  if (form?.assetPath == null) throw StateError('No authored form for $id');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF111820),
        body: SafeArea(
          child: SingleChildScrollView(
            child: ExerciseFormView(
              exerciseName: form!.exerciseName,
              definition: form,
            ),
          ),
        ),
      ),
    ),
  );
}
