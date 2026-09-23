/// Test-only selection and reporting. Never changes catalog review state.
class FormQaPlan {
  FormQaPlan._(this.mode, this.ids, this.baselineEvidence);

  static const defaultIds = [
    'bench_press',
    'incline_dumbbell_press',
    'incline_press_machine',
    'lat_pulldown',
    'mag_narrow',
    'mag_medium',
    'mag_wide',
    'linear_row',
    'decline_fly_machine',
    'decline_press_machine',
    'assisted_chin_up',
    'mag_narrow',
  ];

  factory FormQaPlan.parse({
    String mode = 'full',
    String selected = '',
    String baselineEvidence = '',
    required Set<String> knownIds,
    required Set<String> assetIds,
  }) {
    if (mode != 'full' && mode != 'light') {
      throw ArgumentError('FORM_QA_MODE must be full or light: $mode');
    }
    if (mode == 'light' &&
        (selected.trim().isEmpty || baselineEvidence.trim().isEmpty)) {
      throw ArgumentError(
        'Light mode requires FORM_QA_IDS and FORM_QA_BASELINE '
        '(reference to valid full checks for the unchanged shared behavior).',
      );
    }
    final ids = selected.isEmpty
        ? List<String>.from(defaultIds)
        : selected.split(',').map((id) => id.trim()).toList();
    for (final id in ids) {
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) || !knownIds.contains(id)) {
        throw ArgumentError('Invalid or unknown FORM_QA_IDS entry: $id');
      }
      if (!assetIds.contains(id)) {
        throw ArgumentError('No authored asset for FORM_QA_IDS entry: $id');
      }
    }
    if (mode == 'light' && ids.toSet().length != ids.length) {
      throw ArgumentError('Light mode reopens each ID itself; do not repeat IDs.');
    }
    return FormQaPlan._(mode, List<String>.unmodifiable(ids), baselineEvidence);
  }

  final String mode;
  final List<String> ids;
  // A caller-supplied evidence reference, not verification of that evidence.
  final String baselineEvidence;
  bool get isLight => mode == 'light';

  List<String> get executionIds => isLight
      ? [for (final id in ids) ...[id, id]]
      : ids;

  Map<String, Object?> report() => {
    'mode': mode,
    'requestedIds': ids,
    'executionIds': executionIds,
    'declaredBaselineEvidence': baselineEvidence,
    'reviewApproved': false,
    'notChecked': [
      if (isLight) ...['four motion frames', 'pause/resume'],
      'anatomical correctness',
      'complete motion loop appearance',
      'production route (separate test)',
      'other OS (separate run)',
      'user appearance approval',
    ],
  };
}
