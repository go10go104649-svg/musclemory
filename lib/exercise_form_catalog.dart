import 'exercise_form_catalog.g.dart';
import 'muscle_targets.dart';

/// Stable form identity is independent from legacy record names and asset paths.
class ExerciseFormDefinition {
  ExerciseFormDefinition(Map<String, Object?> value)
    : _value = Map.unmodifiable(value);
  final Map<String, Object?> _value;
  String get exerciseId => _value['exerciseId']! as String;
  String? get englishName => _value['englishName'] as String?;
  String get exerciseName => _value['exerciseName']! as String;
  String get category => _value['category']! as String;
  String get modelId => _value['modelId']! as String;
  String get animationId => _value['animationId']! as String;
  String get equipmentId => _value['equipmentId']! as String;
  String get gripType => _value['gripType']! as String;
  String get movementVariant => _value['movementVariant']! as String;
  String get recordType => _value['recordType']! as String;
  String get loadMode => _value['loadMode']! as String;
  String get status => _value['status']! as String;
  String? get assetPath => _value['assetPath'] as String?;
  bool get available => status == 'verified' && assetPath != null;
  double get animationSpeed => (_value['animationSpeed']! as num).toDouble();
  double get rangeOfMotion => (_value['rangeOfMotion']! as num).toDouble();
  List<String> get aliases => (_value['aliases']! as List).cast<String>();
  List<String> get primaryMuscles =>
      (_value['primaryMuscles']! as List).cast<String>();
  List<String> get secondaryMuscles =>
      (_value['secondaryMuscles']! as List).cast<String>();
  List<String> get primaryMuscleLabels =>
      primaryMuscles.map(_muscleLabel).toList();
  List<String> get secondaryMuscleLabels =>
      secondaryMuscles.map(_muscleLabel).toList();
  static String _muscleLabel(String id) {
    if (id == 'erectorSpinae') return '脊柱起立筋';
    return MuscleRegion.values.firstWhere((muscle) => muscle.name == id).label;
  }

  Map<String, Object?> get parameters =>
      Map<String, Object?>.from(_value['parameters']! as Map);
  Map<String, Object?>? get camera => _value['cameraPreset'] == 'legacy_press'
      ? null
      : {
          'position': _value['cameraAngle'],
          'target': _value['cameraTarget'],
          'scale': _value['cameraScale'],
        };
}

class ExerciseFormCatalog {
  static final entries = List<ExerciseFormDefinition>.unmodifiable(
    exerciseFormData.map(ExerciseFormDefinition.new),
  );
  static final Map<String, ExerciseFormDefinition> byId = {
    for (final item in entries) item.exerciseId: item,
  };
  static final Map<String, ExerciseFormDefinition> _byName = {
    for (final item in entries)
      for (final name in [item.exerciseName, ...item.aliases]) name: item,
  };
  static ExerciseFormDefinition? forName(String name) => _byName[name];
}

// Leave persisted names, favorites and grouping keys unchanged.
String exerciseDisplayName(String storedName, {String languageCode = 'ja'}) =>
    languageCode == 'en' &&
        ExerciseFormCatalog.forName(storedName)?.englishName != null
    ? ExerciseFormCatalog.forName(storedName)!.englishName!
    : storedName == '懸垂'
    ? 'チンニング'
    : storedName;

bool usesAdditionalWeight(String storedName) =>
    ExerciseFormCatalog.forName(storedName)?.loadMode == 'additional';
