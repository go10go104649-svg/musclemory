import 'exercise_form_catalog.dart';

enum MuscleRegion {
  pectoralisMajor('大胸筋', [
    'pectoralis_major_l',
    'pectoralis_major_r',
    'pectoralis_upper_l',
    'pectoralis_upper_r',
  ]),
  anteriorDeltoid('三角筋前部', ['deltoid_anterior_l', 'deltoid_anterior_r']),
  posteriorDeltoid('三角筋後部', ['deltoid_posterior_l', 'deltoid_posterior_r']),
  biceps('上腕二頭筋', ['biceps_brachii_l', 'biceps_brachii_r']),
  triceps('上腕三頭筋', ['triceps_brachii_l', 'triceps_brachii_r']),
  forearms('前腕筋群', [
    'forearm_flexors_l',
    'forearm_flexors_r',
    'forearm_extensors_l',
    'forearm_extensors_r',
  ]),
  latissimusDorsi('広背筋', ['latissimus_dorsi_l', 'latissimus_dorsi_r']),
  trapezius('僧帽筋', ['trapezius']),
  rectusAbdominis('腹直筋', [
    'rectus_abdominis_1_l',
    'rectus_abdominis_1_r',
    'rectus_abdominis_2_l',
    'rectus_abdominis_2_r',
    'rectus_abdominis_3_l',
    'rectus_abdominis_3_r',
    'rectus_abdominis_4_l',
    'rectus_abdominis_4_r',
  ]),
  obliques('腹斜筋', [
    'external_oblique_l',
    'external_oblique_r',
    'serratus_anterior_l',
    'serratus_anterior_r',
  ]),
  gluteus('大臀筋', ['gluteus_maximus_l', 'gluteus_maximus_r']),
  quadriceps('大腿四頭筋', ['quadriceps_l', 'quadriceps_r']),
  hamstrings('ハムストリングス', ['hamstrings_l', 'hamstrings_r']),
  adductors('内転筋群', ['adductors_l', 'adductors_r']),
  calves('下腿筋群', [
    'tibialis_anterior_l',
    'tibialis_anterior_r',
    'gastrocnemius_l',
    'gastrocnemius_r',
  ]);

  const MuscleRegion(this.label, this.meshNames);
  final String label;
  final List<String> meshNames;
}

class ExerciseMuscleProfile {
  const ExerciseMuscleProfile({
    required this.primary,
    this.secondary = const [],
  });
  final List<MuscleRegion> primary;
  final List<MuscleRegion> secondary;
}

class MuscleSetUsage {
  const MuscleSetUsage(this.exerciseName, this.bodyPart);
  final String exerciseName;
  final String bodyPart;
}

const exerciseMuscleProfiles = <String, ExerciseMuscleProfile>{
  'インクラインフライマシン': ExerciseMuscleProfile(
    primary: [MuscleRegion.pectoralisMajor],
    secondary: [MuscleRegion.anteriorDeltoid],
  ),
  'ベンチプレス': ExerciseMuscleProfile(
    primary: [MuscleRegion.pectoralisMajor],
    secondary: [MuscleRegion.anteriorDeltoid, MuscleRegion.triceps],
  ),
  'チェストプレス': ExerciseMuscleProfile(
    primary: [MuscleRegion.pectoralisMajor],
    secondary: [MuscleRegion.anteriorDeltoid, MuscleRegion.triceps],
  ),
  'インクラインダンベルプレス': ExerciseMuscleProfile(
    primary: [MuscleRegion.pectoralisMajor],
    secondary: [MuscleRegion.anteriorDeltoid, MuscleRegion.triceps],
  ),
  'ダンベルフライ': ExerciseMuscleProfile(
    primary: [MuscleRegion.pectoralisMajor],
    secondary: [MuscleRegion.anteriorDeltoid],
  ),
  'ラットプルダウン': ExerciseMuscleProfile(
    primary: [MuscleRegion.latissimusDorsi],
    secondary: [MuscleRegion.biceps, MuscleRegion.trapezius],
  ),
  '懸垂': ExerciseMuscleProfile(
    primary: [MuscleRegion.latissimusDorsi],
    secondary: [MuscleRegion.biceps, MuscleRegion.forearms],
  ),
  'バーベルロウ': ExerciseMuscleProfile(
    primary: [MuscleRegion.latissimusDorsi, MuscleRegion.trapezius],
    secondary: [MuscleRegion.biceps, MuscleRegion.posteriorDeltoid],
  ),
  'シーテッドロウ': ExerciseMuscleProfile(
    primary: [MuscleRegion.latissimusDorsi, MuscleRegion.trapezius],
    secondary: [MuscleRegion.biceps, MuscleRegion.posteriorDeltoid],
  ),
  'デッドリフト': ExerciseMuscleProfile(
    primary: [MuscleRegion.hamstrings, MuscleRegion.gluteus],
    secondary: [MuscleRegion.latissimusDorsi, MuscleRegion.trapezius],
  ),
  'スクワット': ExerciseMuscleProfile(
    primary: [MuscleRegion.quadriceps, MuscleRegion.gluteus],
    secondary: [MuscleRegion.hamstrings, MuscleRegion.adductors],
  ),
  'レッグプレス': ExerciseMuscleProfile(
    primary: [MuscleRegion.quadriceps, MuscleRegion.gluteus],
    secondary: [MuscleRegion.hamstrings],
  ),
  'レッグエクステンション': ExerciseMuscleProfile(primary: [MuscleRegion.quadriceps]),
  'レッグカール': ExerciseMuscleProfile(primary: [MuscleRegion.hamstrings]),
  'ブルガリアンスクワット': ExerciseMuscleProfile(
    primary: [MuscleRegion.quadriceps, MuscleRegion.gluteus],
    secondary: [MuscleRegion.hamstrings, MuscleRegion.adductors],
  ),
  'ショルダープレス': ExerciseMuscleProfile(
    primary: [MuscleRegion.anteriorDeltoid],
    secondary: [MuscleRegion.triceps, MuscleRegion.trapezius],
  ),
  'サイドレイズ': ExerciseMuscleProfile(
    primary: [MuscleRegion.anteriorDeltoid, MuscleRegion.posteriorDeltoid],
    secondary: [MuscleRegion.trapezius],
  ),
  'リアレイズ': ExerciseMuscleProfile(
    primary: [MuscleRegion.posteriorDeltoid],
    secondary: [MuscleRegion.trapezius],
  ),
  'アームカール': ExerciseMuscleProfile(
    primary: [MuscleRegion.biceps],
    secondary: [MuscleRegion.forearms],
  ),
  'ハンマーカール': ExerciseMuscleProfile(
    primary: [MuscleRegion.biceps, MuscleRegion.forearms],
  ),
  'トライセプスプッシュダウン': ExerciseMuscleProfile(primary: [MuscleRegion.triceps]),
  'クランチ': ExerciseMuscleProfile(
    primary: [MuscleRegion.rectusAbdominis],
    secondary: [MuscleRegion.obliques],
  ),
  'トレッドミル': ExerciseMuscleProfile(
    primary: [MuscleRegion.quadriceps, MuscleRegion.calves],
    secondary: [MuscleRegion.gluteus, MuscleRegion.hamstrings],
  ),
  'エアロバイク': ExerciseMuscleProfile(
    primary: [MuscleRegion.quadriceps],
    secondary: [MuscleRegion.gluteus, MuscleRegion.calves],
  ),
  'クロストレーナー': ExerciseMuscleProfile(
    primary: [MuscleRegion.quadriceps, MuscleRegion.gluteus],
    secondary: [MuscleRegion.hamstrings, MuscleRegion.calves],
  ),
  'ステアクライマー': ExerciseMuscleProfile(
    primary: [MuscleRegion.gluteus, MuscleRegion.quadriceps],
    secondary: [MuscleRegion.hamstrings, MuscleRegion.calves],
  ),
  'ローイングマシン': ExerciseMuscleProfile(
    primary: [MuscleRegion.latissimusDorsi, MuscleRegion.quadriceps],
    secondary: [MuscleRegion.biceps, MuscleRegion.hamstrings],
  ),
};

ExerciseMuscleProfile muscleProfileForExercise(
  String name,
  String bodyPart, {
  String? exerciseId,
}) {
  final form = exerciseId == null ? null : ExerciseFormCatalog.byId[exerciseId];
  if (form != null) {
    List<MuscleRegion> regions(List<String> ids) =>
        MuscleRegion.values.where((m) => ids.contains(m.name)).toList();
    return ExerciseMuscleProfile(
      primary: regions(form.primaryMuscles),
      secondary: regions(form.secondaryMuscles),
    );
  }
  return exerciseMuscleProfiles[name] ??
      switch (bodyPart) {
        '胸' => const ExerciseMuscleProfile(
          primary: [MuscleRegion.pectoralisMajor],
        ),
        '背中' => const ExerciseMuscleProfile(
          primary: [MuscleRegion.latissimusDorsi],
          secondary: [MuscleRegion.trapezius],
        ),
        '肩' => const ExerciseMuscleProfile(
          primary: [MuscleRegion.anteriorDeltoid],
        ),
        '腕' => const ExerciseMuscleProfile(
          primary: [MuscleRegion.biceps, MuscleRegion.triceps],
        ),
        '脚' => const ExerciseMuscleProfile(
          primary: [MuscleRegion.quadriceps, MuscleRegion.gluteus],
        ),
        '腹' || '腹筋' => const ExerciseMuscleProfile(
          primary: [MuscleRegion.rectusAbdominis],
        ),
        '有酸素' => const ExerciseMuscleProfile(
          primary: [MuscleRegion.quadriceps, MuscleRegion.calves],
        ),
        _ => const ExerciseMuscleProfile(primary: []),
      };
}

Map<MuscleRegion, double> muscleScoresForSets(Iterable<MuscleSetUsage> sets) {
  final scores = <MuscleRegion, double>{};
  for (final set in sets) {
    final profile = muscleProfileForExercise(set.exerciseName, set.bodyPart);
    for (final muscle in profile.primary) {
      scores.update(muscle, (value) => value + 1, ifAbsent: () => 1);
    }
    for (final muscle in profile.secondary) {
      scores.update(muscle, (value) => value + 0.35, ifAbsent: () => 0.35);
    }
  }
  return scores;
}
