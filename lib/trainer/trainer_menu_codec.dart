import '../main.dart'
    show RecordedSet, WorkoutExercise, WorkoutSet, WorkoutRecord;

/// One codec for TRAINER editing and SK execution; no persisted client copy.
abstract final class TrainerMenuCodec {
  static Map<String, dynamic> fromRow(Map<String, dynamic> menu) {
    final exercises = List<Map<String, dynamic>>.from(
      menu['tenant_menu_exercises'] as List,
    )..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return {
      ...menu,
      'items': [
        for (final e in exercises)
          {
            ...e,
            'set_values':
                (List<Map<String, dynamic>>.from(e['tenant_menu_sets'] as List)
                      ..sort(
                        (a, b) => (a['position'] as int).compareTo(
                          b['position'] as int,
                        ),
                      ))
                    .map((s) => s['values'])
                    .toList(),
          },
      ],
    };
  }

  static List<RecordedSet> setsForItem(Map item) {
    final values =
        item['set_values'] as List? ??
        List.generate(
          item['sets'] as int,
          (_) => {'weight': item['target_weight'], 'reps': item['target_reps']},
        );
    return [
      for (final v in values)
        RecordedSet.fromJson({
          ...Map<String, dynamic>.from(v as Map),
          'exerciseId': item['exercise_id'],
          'exerciseName': item['exercise_name'],
          'bodyPart': item['body_part'] ?? '',
          'equipment': item['equipment'] ?? '',
          'recordType': item['record_type'],
          'completed': false,
        }),
    ];
  }

  static WorkoutSet editable(RecordedSet s) => WorkoutSet(
    weight: s.weight,
    reps: s.reps,
    durationSeconds: s.durationSeconds,
    distanceKm: s.distanceKm,
    speedKmh: s.speedKmh,
    inclinePercent: s.inclinePercent,
    resistanceLevel: s.resistanceLevel,
    paceSecondsPerKm: s.paceSecondsPerKm,
  );

  static List<WorkoutExercise> exercises(List items) => [
    for (final item in items)
      for (final sets in [setsForItem(item as Map)])
        if (sets.isNotEmpty)
          WorkoutExercise(
            name: sets.first.exerciseName,
            exerciseId: sets.first.exerciseId,
            distanceUnit: sets.first.distanceUnit,
            bodyPart: sets.first.bodyPart,
            equipment: sets.first.equipment,
            recordType: sets.first.recordType,
            sets: sets.map(editable).toList(),
          ),
  ];

  static WorkoutRecord workout(Map<String, dynamic> menu) => WorkoutRecord(
    date: DateTime.now(),
    sets: [
      for (final item in menu['items'] as List) ...setsForItem(item as Map),
    ],
  );
}
