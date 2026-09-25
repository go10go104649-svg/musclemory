import 'package:flutter/material.dart';
import 'package:setkeep/trainer/trainer_repository.dart';
import 'package:setkeep/main.dart' show WorkoutRecord, BodyMapPage, RecordedSet;

String tr(BuildContext context, String ja, String en) =>
    Localizations.localeOf(context).languageCode == 'ja' ? ja : en;

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        const Icon(Icons.inbox_outlined, size: 44),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

String dateLabel(Object? date) =>
    DateTime.tryParse('$date')?.toLocal().toString().split(' ').first ?? '—';
WorkoutRecord decodeWorkout(Map<String, dynamic> row) =>
    WorkoutRecord.fromJson({
      'date': row['performed_at'],
      'durationSeconds': row['duration_seconds'],
      'gymName': row['gym_name'],
      'sets': row['sets'],
    });

class LatestWorkout extends StatefulWidget {
  const LatestWorkout({
    super.key,
    required this.repository,
    required this.clientId,
  });
  final TrainerRepository repository;
  final String clientId;
  @override
  State<LatestWorkout> createState() => _LatestWorkoutState();
}

class _LatestWorkoutState extends State<LatestWorkout> {
  late Future<List<Map<String, dynamic>>> future = widget.repository.workouts(
    widget.clientId,
  );
  @override
  void didUpdateWidget(covariant LatestWorkout oldWidget) {
    super.didUpdateWidget(oldWidget);
    future = widget.repository.workouts(widget.clientId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text(tr(context, '履歴を取得できません', 'History unavailable'));
      }
      if (!snapshot.hasData) return Text(tr(context, '読み込み中', 'Loading'));
      if (snapshot.data!.isEmpty) {
        return Text(tr(context, '共有された記録はありません', 'No shared workouts'));
      }
      final w = decodeWorkout(snapshot.data!.first);
      return Text(
        '${dateLabel(w.date)} · ${w.exerciseNames.join(' / ')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    },
  );
}

class WorkoutCard extends StatelessWidget {
  const WorkoutCard({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final w = decodeWorkout(row);
    return Card(
      child: ExpansionTile(
        title: Text(dateLabel(w.date)),
        subtitle: Text(
          '${w.exerciseNames.join(' / ')} · ${w.sets.length} ${tr(context, 'セット', 'sets')}',
        ),
        children: [
          for (final group in w.exerciseGroups.values)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.first.exerciseName),
                  for (var i = 0; i < group.length; i++)
                    Text(
                      '${i + 1}. ${group[i].weight} kg × ${group[i].reps} ${tr(context, '回', 'reps')}',
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class MenuCard extends StatelessWidget {
  const MenuCard({super.key, required this.menu, this.clientName});
  final Map<String, dynamic> menu;
  final String? clientName;
  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text(menu['name'] as String),
      subtitle: Text(
        '${clientName ?? dateLabel(menu['created_at'])} · ${menu['status'] ?? 'planned'} · ${menu['schedule'] ?? 'single'}',
      ),
      children: [
        for (final i in menu['items'] as List)
          ListTile(
            title: Text('${i['exercise_name']}'),
            subtitle: Text(
              i['set_values'] is List
                  ? (i['set_values'] as List)
                        .map(
                          (s) => RecordedSet.fromJson(
                            Map<String, dynamic>.from(s as Map),
                          ).displaySummary,
                        )
                        .join(' / ')
                  : '${i['sets']} ${tr(context, 'セット', 'sets')} · ${i['target_weight']} kg × ${i['target_reps']}',
            ),
          ),
        if ('${menu['note']}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(menu['note'] as String),
          ),
      ],
    ),
  );
}

class HeatmapPage extends StatelessWidget {
  const HeatmapPage({super.key, required this.workouts});
  final List<Map<String, dynamic>> workouts;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, '部位ヒートマップ', 'Body-part heatmap'))),
    body: BodyMapPage(
      history: workouts
          .where((w) => w['canceled_at'] == null)
          .map(decodeWorkout)
          .toList(),
    ),
  );
}

class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({super.key, required this.title});
  final String title;
  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: controller, maxLength: 10000, maxLines: 3),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(tr(context, '保存', 'Save')),
      ),
    ],
  );
}
