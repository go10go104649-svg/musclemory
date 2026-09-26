import 'package:flutter/services.dart';

import 'exercise_form_catalog.dart';

/// Optional media is keyed by SETKEEP's stable exercise ID, never the provider ID.
class ExerciseMedia {
  const ExerciseMedia({
    required this.exerciseId,
    required this.provider,
    required this.providerAssetId,
    required this.mediaType,
    required this.assetPath,
    this.thumbnailAssetPath,
    this.videoUrl,
    this.isActive = true,
  });

  final String exerciseId;
  final String provider;
  final String providerAssetId;
  final String mediaType;
  final String assetPath;
  final String? thumbnailAssetPath;
  final Uri? videoUrl;
  final bool isActive;
}

class ExerciseMediaCatalog {
  static const _trialRoot = 'local_assets/vital_animations/free50/videos';
  static const _trialThumbnails =
      'local_assets/vital_animations/free50/thumbnails';

  // Trial-only mapping. Provider IDs never replace exercise IDs or form status.
  static const _trial = <String, ExerciseMedia>{
    'pec_fly': ExerciseMedia(
      exerciseId: 'pec_fly',
      provider: 'vital_animations',
      providerAssetId: '0051',
      mediaType: 'video',
      assetPath: '$_trialRoot/0051.mp4',
      thumbnailAssetPath: '$_trialThumbnails/0051.png',
    ),
    'barbell_squat': ExerciseMedia(
      exerciseId: 'barbell_squat',
      provider: 'vital_animations',
      providerAssetId: '0054',
      mediaType: 'video',
      assetPath: '$_trialRoot/0054.mp4',
      thumbnailAssetPath: '$_trialThumbnails/0054.png',
    ),
    'leg_press': ExerciseMedia(
      exerciseId: 'leg_press',
      provider: 'vital_animations',
      providerAssetId: '0074',
      mediaType: 'video',
      assetPath: '$_trialRoot/0074.mp4',
      thumbnailAssetPath: '$_trialThumbnails/0074.png',
    ),
    'rope_pushdown': ExerciseMedia(
      exerciseId: 'rope_pushdown',
      provider: 'vital_animations',
      providerAssetId: '0085',
      mediaType: 'video',
      assetPath: '$_trialRoot/0085.mp4',
      thumbnailAssetPath: '$_trialThumbnails/0085.png',
    ),
    'machine_lateral_raise': ExerciseMedia(
      exerciseId: 'machine_lateral_raise',
      provider: 'vital_animations',
      providerAssetId: '0097',
      mediaType: 'video',
      assetPath: '$_trialRoot/0097.mp4',
      thumbnailAssetPath: '$_trialThumbnails/0097.png',
    ),
  };

  static List<ExerciseMedia> get trialEntries =>
      List.unmodifiable(_trial.values);

  static ExerciseMedia? forExerciseId(String? exerciseId) {
    if (exerciseId == null) return null;
    final media = _trial[ExerciseFormCatalog.canonicalId(exerciseId)];
    return media?.isActive == true ? media : null;
  }

  static Future<bool> isAvailable(
    ExerciseMedia media, {
    AssetBundle? bundle,
  }) async {
    if (media.videoUrl != null) return true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(
        bundle ?? rootBundle,
      );
      return manifest.listAssets().contains(media.assetPath);
    } catch (_) {
      return false;
    }
  }
}
