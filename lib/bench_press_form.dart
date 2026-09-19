import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import 'exercise_form_catalog.dart';

/// Shared playback for explicitly authored, local exercise animations.
class ExerciseFormView extends StatefulWidget {
  const ExerciseFormView({
    super.key,
    this.exerciseName = 'ベンチプレス',
    this.definition,
  });
  final ExerciseFormDefinition? definition;

  final String exerciseName;
  static bool supports(String name) =>
      ExerciseFormCatalog.forName(name)?.available ?? false;

  @override
  State<ExerciseFormView> createState() => _BenchPressFormViewState();
}

class _BenchPressFormViewState extends State<ExerciseFormView>
    with WidgetsBindingObserver {
  bool _playing = true;
  bool _foreground = true;
  bool _ready = false;
  bool _failed = false;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(covariant ExerciseFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldForm =
        oldWidget.definition ??
        ExerciseFormCatalog.forName(oldWidget.exerciseName);
    final newForm =
        widget.definition ?? ExerciseFormCatalog.forName(widget.exerciseName);
    if (oldForm?.assetPath != newForm?.assetPath) {
      _ready = false;
      _failed = false;
      _playing = true;
      _speed = 1;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form =
        widget.definition ?? ExerciseFormCatalog.forName(widget.exerciseName);
    if (form?.assetPath == null) return const SizedBox.shrink();
    return Container(
      key: const Key('benchPressForm3D'),
      decoration: BoxDecoration(
        color: const Color(0xFF111820),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
            child: Row(
              children: [
                Text(
                  '3Dフォーム',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Spacer(),
                Flexible(
                  child: Text(
                    exerciseDisplayName(widget.exerciseName),
                    maxLines: 2,
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_failed)
                  IgnorePointer(
                    key: ValueKey(form!.assetPath),
                    child: Interactive3d(
                      key: const Key('benchPressNativeScene'),
                      modelPath: form.assetPath,
                      formCamera: form.camera,
                      solidBackgroundColor: const [0.067, 0.094, 0.125, 1],
                      backgroundColor: const Color(0xFF111820),
                      formAnimation: true,
                      animationPlaying: _playing && _foreground,
                      animationSpeed: _speed * form.animationSpeed,
                      onModelReady: () {
                        if (mounted) setState(() => _ready = true);
                      },
                      onModelError: (_) {
                        if (mounted) setState(() => _failed = true);
                      },
                    ),
                  ),
                if (!_ready && !_failed)
                  const Center(
                    child: CircularProgressIndicator(color: Color(0xFFE9636A)),
                  ),
                if (_failed)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '3Dフォームを読み込めませんでした。\n画面を開き直してください。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                FilledButton.icon(
                  key: const Key('benchPressPlayPause'),
                  onPressed: _ready && !_failed
                      ? () => setState(() => _playing = !_playing)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFBD3344),
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_playing ? '一時停止' : '再生'),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'ループ再生',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    key: const Key('benchPressPlaybackSpeed'),
                    value: _speed,
                    dropdownColor: const Color(0xFF222C35),
                    iconEnabledColor: Colors.white70,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    items: const [
                      DropdownMenuItem(value: 0.5, child: Text('0.5倍速')),
                      DropdownMenuItem(value: 1, child: Text('1倍速')),
                      DropdownMenuItem(value: 1.5, child: Text('1.5倍速')),
                    ],
                    onChanged: _ready && !_failed
                        ? (value) {
                            if (value != null) setState(() => _speed = value);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compatibility wrapper for existing callers and baseline regression tests.
class BenchPressFormView extends ExerciseFormView {
  const BenchPressFormView({super.key, super.exerciseName});
  static const models = {
    'ベンチプレス': 'assets/models/bench_press.glb',
    'インクラインダンベルプレス': 'assets/models/incline_dumbbell_press.glb',
  };
  static bool supports(String name) => ExerciseFormView.supports(name);
}
