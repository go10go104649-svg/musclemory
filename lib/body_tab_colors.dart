import 'package:flutter/material.dart';

import 'muscle_targets.dart';

/// Category balance is independent of exercise activation weights. This mapping
/// can later be replaced by per-muscle primary/secondary values without changing
/// the asset's separately named muscle masks.
const bodyTabMuscleCategories = <MuscleRegion, String>{
  MuscleRegion.pectoralisMajor: '胸',
  MuscleRegion.anteriorDeltoid: '肩',
  MuscleRegion.posteriorDeltoid: '肩',
  MuscleRegion.biceps: '腕',
  MuscleRegion.triceps: '腕',
  MuscleRegion.forearms: '腕',
  MuscleRegion.latissimusDorsi: '背中',
  MuscleRegion.trapezius: '背中',
  MuscleRegion.rectusAbdominis: '腹',
  MuscleRegion.obliques: '腹',
  MuscleRegion.gluteus: '脚',
  MuscleRegion.quadriceps: '脚',
  MuscleRegion.hamstrings: '脚',
  MuscleRegion.adductors: '脚',
  MuscleRegion.calves: '脚',
};

Map<MuscleRegion, double> bodyTabRelativeIntensities(Map<String, int> counts) {
  final maximum = bodyTabMuscleCategories.values.toSet().fold<int>(
    0,
    (a, part) => (counts[part] ?? 0) > a ? counts[part]! : a,
  );
  return {
    for (final entry in bodyTabMuscleCategories.entries)
      entry.key: maximum == 0
          ? 0
          : ((counts[entry.value] ?? 0) / maximum).clamp(0.0, 1.0),
  };
}

Color bodyTabHeatColor(double intensity) {
  if (intensity <= 0) return const Color(0xFF8C9499);
  return Color.lerp(
    const Color(0xFFF5D9DA),
    const Color(0xFFA8071A),
    intensity.clamp(0.0, 1.0),
  )!;
}

List<double> bodyTabMaterialColor(double intensity) {
  final color = bodyTabHeatColor(intensity);
  // Compensate the fixed studio lighting so low ratios stay pale red
  // instead of clipping to white. This factor never depends on set counts.
  final exposure = intensity > 0 ? 0.72 : 1.0;
  return [color.r * exposure, color.g * exposure, color.b * exposure, 1];
}
