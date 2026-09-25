import 'package:flutter/material.dart';
import 'package:setkeep/trainer/trainer_repository.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/main.dart' show RecordedSet, ExerciseRecordType;

import 'trainer_widgets.dart';

class MenuEditor extends StatefulWidget {
  const MenuEditor({
    super.key,
    required this.repository,
    required this.clients,
    this.recording = false,
  });
  final TrainerRepository repository;
  final List<Map<String, dynamic>> clients;
  final bool recording;
  @override
  State<MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends State<MenuEditor> {
  final name = TextEditingController(),
      note = TextEditingController(),
      sets = TextEditingController(text: '3'),
      weight = TextEditingController(text: '20'),
      reps = TextEditingController(text: '10');
  final items = <Map<String, dynamic>>[];
  late String clientId = widget.clients.first['client_id'] as String;
  late ExerciseFormDefinition exercise = catalog.first;
  late DateTime date = DateTime.now();
  final requestId = TrainerRepository.requestId();
  bool busy = false;
  String? error;
  List<ExerciseFormDefinition> get catalog => ExerciseFormCatalog.entries
      .where(
        (e) =>
            e.selectable &&
            [
              'weightReps',
              'bodyweightReps',
              'assistedReps',
            ].contains(e.recordType),
      )
      .toList();
  @override
  void dispose() {
    for (final c in [name, note, sets, weight, reps]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? item() {
    final s = int.tryParse(sets.text),
        r = int.tryParse(reps.text),
        w = double.tryParse(weight.text);
    if (s == null ||
        s < 1 ||
        s > 50 ||
        r == null ||
        r < 1 ||
        r > 1000 ||
        w == null ||
        !w.isFinite ||
        w < 0 ||
        w > 2000) {
      return null;
    }
    return {
      'exercise_id': exercise.exerciseId,
      'exercise_name': exercise.exerciseName,
      'body_part': exercise.category,
      'equipment': exercise.equipmentLabel,
      'record_type': exercise.recordType,
      'sets': s,
      'target_weight': w,
      'target_reps': r,
    };
  }

  Future<void> save() async {
    if (!widget.recording && name.text.trim().isEmpty) {
      setState(
        () => error = tr(context, 'メニュー名を入力してください', 'Enter a menu name'),
      );
      return;
    }
    final pending = items.isEmpty ? item() : null;
    final all = [...items, ?pending];
    if (all.isEmpty ||
        all.fold<int>(0, (s, i) => s + (i['sets'] as int)) > 100) {
      setState(
        () => error = tr(
          context,
          '入力値を確認してください（合計100セットまで）',
          'Check values (up to 100 total sets)',
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      if (widget.recording) {
        final recorded = <Map<String, dynamic>>[];
        for (final i in all) {
          for (var s = 0; s < (i['sets'] as int); s++) {
            recorded.add(
              RecordedSet(
                exerciseId: i['exercise_id'] as String,
                exerciseName: i['exercise_name'] as String,
                bodyPart: i['body_part'] as String,
                equipment: i['equipment'] as String,
                recordType: ExerciseRecordType.fromName(
                  i['record_type'] as String,
                ),
                weight: i['target_weight'] as double,
                reps: i['target_reps'] as int,
                completed: true,
              ).toJson(),
            );
          }
        }
        await widget.repository.recordWorkout(
          clientId,
          requestId,
          date,
          recorded,
        );
      } else {
        await widget.repository.addMenu(clientId, name.text, note.text, all);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            context,
            '保存を確認できませんでした。接続・連携権限を確認して再試行してください。',
            'Save could not be confirmed. Check connection and sharing permission, then retry.',
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.recording
            ? tr(context, 'セッションを記録', 'Record session')
            : tr(context, 'メニューを作成', 'Create menu'),
      ),
    ),
    body: AbsorbPointer(
      absorbing: busy,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DropdownButtonFormField<String>(
            initialValue: clientId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr(context, '対象顧客', 'Client'),
            ),
            items: [
              for (final c in widget.clients)
                DropdownMenuItem(
                  value: c['client_id'] as String,
                  child: Text(c['client_name'] as String),
                ),
            ],
            onChanged: (v) => setState(() => clientId = v!),
          ),
          if (!widget.recording)
            TextField(
              controller: name,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: tr(context, 'メニュー名', 'Menu name'),
              ),
            ),
          if (widget.recording)
            ListTile(
              title: Text(dateLabel(date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(
                    () => date = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      date.hour,
                      date.minute,
                      date.second,
                      date.millisecond,
                      date.microsecond,
                    ),
                  );
                }
              },
            ),
          const SizedBox(height: 16),
          Text(
            tr(
              context,
              'SETKEEP共通種目（初期版：重量・回数種目）',
              'Shared SETKEEP exercises (initial version: weight/reps)',
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: exercise.exerciseId,
            isExpanded: true,
            items: [
              for (final e in catalog)
                DropdownMenuItem(
                  value: e.exerciseId,
                  child: Text(
                    tr(
                      context,
                      e.exerciseName,
                      e.englishName ?? e.exerciseName,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) =>
                setState(() => exercise = ExerciseFormCatalog.byId[v]!),
          ),
          Row(
            children: [
              for (final pair in [
                (sets, tr(context, 'セット数', 'Sets')),
                (weight, tr(context, '重量 kg', 'Weight kg')),
                (reps, tr(context, '回数', 'Reps')),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: TextField(
                      controller: pair.$1,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: pair.$2),
                    ),
                  ),
                ),
            ],
          ),
          OutlinedButton(
            onPressed: () {
              final i = item();
              setState(() {
                if (i == null) {
                  error = tr(context, '有効な数値を入力してください', 'Enter valid numbers');
                } else {
                  items.add(i);
                  error = null;
                }
              });
            },
            child: Text(tr(context, '種目をリストに追加', 'Add exercise to list')),
          ),
          for (var n = 0; n < items.length; n++)
            ListTile(
              title: Text('${items[n]['exercise_name']}'),
              subtitle: Text(
                '${items[n]['sets']} × ${items[n]['target_weight']} kg × ${items[n]['target_reps']}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => items.removeAt(n)),
              ),
            ),
          if (!widget.recording)
            TextField(
              controller: note,
              maxLength: 10000,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: tr(context, 'メモ', 'Notes'),
              ),
            ),
          if (widget.recording)
            Text(
              tr(
                context,
                '保存すると顧客本人のクラウド履歴に記録されます。顧客はSETKEEPの連携画面から受信できます。',
                'Saving writes to the client’s cloud history. They can receive it from SETKEEP’s linking page.',
              ),
            ),
          if (error != null) Text(error!),
          if (busy) const LinearProgressIndicator(),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(tr(context, '保存', 'Save')),
          ),
        ],
      ),
    ),
  );
}
