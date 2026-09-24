import 'dart:async';

import 'package:flutter/material.dart';

import '../exercise_form_catalog.dart';
import 'custom_gym_preference.dart';
import 'gym_repository.dart';
import 'gym_pages.dart';

/// Catalog IDs are explicitly selected; free text never infers a mapping.
Future<String?> selectPlaceExercise(
  BuildContext context, {
  Set<String>? allowed,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ExerciseChoice(allowed: allowed),
);

class _ExerciseChoice extends StatefulWidget {
  const _ExerciseChoice({this.allowed});
  final Set<String>? allowed;
  @override
  State<_ExerciseChoice> createState() => _ExerciseChoiceState();
}

class _ExerciseChoiceState extends State<_ExerciseChoice> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final forms =
        availableForms(
              widget.allowed ??
                  ExerciseFormCatalog.entries.map((e) => e.exerciseId).toSet(),
            )
            .where(
              (e) => '${e.exerciseName} ${e.englishName} ${e.equipmentLabel}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.exerciseName.compareTo(b.exerciseName));
    return AlertDialog(
      title: const Text('種目を選択'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(
          children: [
            TextField(
              key: const Key('placeExerciseSearch'),
              decoration: const InputDecoration(labelText: '種目を検索'),
              onChanged: (v) => setState(() => query = v),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final e in forms)
                    ListTile(
                      key: ValueKey('choosePlaceExercise${e.exerciseId}'),
                      title: Text(e.exerciseName),
                      subtitle: Text(e.equipmentLabel),
                      onTap: () => Navigator.pop(context, e.exerciseId),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
      ],
    );
  }
}

Future<void> showStoreExerciseReport(
  BuildContext context,
  String storeId,
  Set<String> currentIds,
) async {
  final repo = GymServices.repository;
  if (!repo.canReport) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('マイページのアカウントからログインすると報告できます。')),
    );
    return;
  }
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ExerciseReport(storeId: storeId, currentIds: currentIds),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('報告を受け付けました。確認後に対応種目情報を更新します。')),
    );
  }
}

class _ExerciseReport extends StatefulWidget {
  const _ExerciseReport({required this.storeId, required this.currentIds});
  final String storeId;
  final Set<String> currentIds;
  @override
  State<_ExerciseReport> createState() => _ExerciseReportState();
}

class _ExerciseReportState extends State<_ExerciseReport> {
  String kind = 'missing_exercise';
  String? exerciseId, error;
  bool busy = false;
  final comment = TextEditingController();
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy) return;
    if ((kind != 'other' && exerciseId == null) ||
        (kind == 'other' && comment.text.trim().isEmpty)) {
      setState(() => error = kind == 'other' ? '内容を入力してください' : '対象種目を選択してください');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await GymServices.repository.reportExercise(
        storeId: widget.storeId,
        kind: kind,
        exerciseId: kind == 'other' ? null : exerciseId,
        comment: comment.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '報告を送信できませんでした。再度お試しください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('対応種目を報告'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('exerciseReportKind'),
            initialValue: kind,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: 'missing_exercise',
                child: Text('できるのに表示されていない'),
              ),
              DropdownMenuItem(
                value: 'incorrect_exercise',
                child: Text('表示されているができない'),
              ),
              DropdownMenuItem(value: 'other', child: Text('その他')),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    kind = v!;
                    exerciseId = null;
                  }),
          ),
          if (kind != 'other')
            TextButton(
              key: const Key('exerciseReportTarget'),
              onPressed: busy
                  ? null
                  : () async {
                      final id = await selectPlaceExercise(
                        context,
                        allowed: kind == 'incorrect_exercise'
                            ? widget.currentIds
                            : null,
                      );
                      if (id != null && mounted) {
                        setState(() => exerciseId = id);
                      }
                    },
              child: Text(
                exerciseId == null
                    ? '対象種目を選択'
                    : ExerciseFormCatalog.byId[exerciseId]?.exerciseName ??
                          exerciseId!,
              ),
            ),
          TextField(
            key: const Key('exerciseReportComment'),
            controller: comment,
            maxLength: 2000,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: kind == 'other' ? '内容' : 'コメント（任意）',
            ),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('sendExerciseReport'),
        onPressed: busy ? null : send,
        child: Text(busy ? '送信中…' : '報告を送信'),
      ),
    ],
  );
}

class PrivatePlaceEquipmentPage extends StatefulWidget {
  const PrivatePlaceEquipmentPage({
    super.key,
    required this.placeId,
    required this.name,
    this.onAdd,
    this.existingIds = const {},
  });
  final String placeId, name;
  final Future<void> Function(Set<String>)? onAdd;
  final Set<String> existingIds;
  @override
  State<PrivatePlaceEquipmentPage> createState() =>
      _PrivatePlaceEquipmentPageState();
}

class _PrivatePlaceEquipmentPageState extends State<PrivatePlaceEquipmentPage> {
  final repo = GymServices.repository;
  List<PrivatePlaceEquipment> items = [];
  List<GymExerciseEvidence> evidence = [];
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
      evidence = [];
    });
    try {
      final rows = await repo.privateEquipment(widget.placeId);
      if (mounted) setState(() => items = rows);
      final result = await repo.privateEvidence(widget.placeId);
      if (mounted) setState(() => evidence = result);
    } catch (_) {
      if (mounted) setState(() => error = '設備・対応種目を取得できませんでした。再読み込みしてください。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) await load();
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '設備を保存できませんでした。再度お試しください。';
        });
      }
    }
  }

  Future<void> add() async {
    final selected = await Navigator.push<PrivatePlaceEquipment>(
      context,
      MaterialPageRoute(builder: (_) => const _EquipmentSearch()),
    );
    if (selected != null && mounted) {
      await change(() => repo.savePrivateEquipment(widget.placeId, selected));
    }
  }

  Future<void> edit(PrivatePlaceEquipment item) async {
    final updated = await showDialog<PrivatePlaceEquipment>(
      context: context,
      builder: (_) => _PrivateEquipmentEditor(item: item),
    );
    if (updated != null && mounted) {
      await change(() => repo.savePrivateEquipment(widget.placeId, updated));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('この場所の設備は本人専用です。共有店舗の情報は変更されません。'),
          if (busy) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            TextButton(onPressed: load, child: const Text('再読み込み')),
          ],
          for (final item in items)
            Card(
              child: Column(
                children: [
                  ListTile(
                    key: ValueKey('privateEquipment${item.id}'),
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.quantity == null ? '' : '${item.quantity}台 ・ '}対応${availableForms(evidence.where((e) => e.equipmentIds.contains(item.equipmentId ?? item.id)).map((e) => e.exerciseId)).length}種目',
                    ),
                    onTap: busy
                        ? null
                        : () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GymEquipmentExercisesPage(
                                store: GymStore(
                                  id: '',
                                  chainName: '',
                                  name: widget.name,
                                ),
                                equipment: GymEquipment(
                                  id: item.equipmentId ?? item.id,
                                  name: item.name,
                                  category: '本人専用',
                                  quantity: item.quantity,
                                ),
                                evidence: evidence
                                    .where(
                                      (e) => e.equipmentIds.contains(
                                        item.equipmentId ?? item.id,
                                      ),
                                    )
                                    .toList(),
                                onAdd: widget.onAdd,
                                existingIds: widget.existingIds,
                                allowReports: false,
                              ),
                            ),
                          ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: ValueKey('editPrivateEquipment${item.id}'),
                        onPressed: busy ? null : () => edit(item),
                        child: Text(
                          item.equipmentId == null ? '台数・対応種目を編集' : '台数を編集',
                        ),
                      ),
                      IconButton(
                        key: ValueKey('deletePrivateEquipment${item.id}'),
                        tooltip: '設備を削除',
                        onPressed: busy
                            ? null
                            : () => change(
                                () => repo.deletePrivateEquipment(
                                  widget.placeId,
                                  itemId: item.id,
                                ),
                              ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (!busy && items.isEmpty) const Text('設備が登録されていません'),
          FilledButton.icon(
            key: const Key('addPrivateEquipment'),
            onPressed: busy ? null : add,
            icon: const Icon(Icons.add),
            label: const Text('設備を追加'),
          ),
        ],
      ),
    ),
  );
}

class _EquipmentSearch extends StatefulWidget {
  const _EquipmentSearch();
  @override
  State<_EquipmentSearch> createState() => _EquipmentSearchState();
}

class _EquipmentSearchState extends State<_EquipmentSearch> {
  List<GymEquipment> rows = [];
  String query = '';
  bool busy = true, failed = false, more = false;
  int request = 0;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> load({bool append = false}) async {
    final n = ++request;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final result = await GymServices.repository.searchEquipment(
        query,
        offset: append ? rows.length : 0,
      );
      if (mounted && n == request) {
        setState(() {
          rows = append ? [...rows, ...result] : result;
          more = result.length == 30;
        });
      }
    } catch (_) {
      if (mounted && n == request) setState(() => failed = true);
    } finally {
      if (mounted && n == request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('設備を追加')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('equipmentMasterSearch'),
              decoration: const InputDecoration(labelText: '設備名・メーカーで検索'),
              onChanged: (v) {
                query = v;
                ++request;
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => load(),
                );
              },
            ),
          ),
          TextButton(
            key: const Key('addFreeEquipment'),
            onPressed: () async {
              final item = await showDialog<PrivatePlaceEquipment>(
                context: context,
                builder: (_) => _PrivateEquipmentEditor(
                  item: PrivatePlaceEquipment(
                    id: CustomGymPreference.newId(),
                    name: '',
                  ),
                ),
              );
              if (item != null && context.mounted) Navigator.pop(context, item);
            },
            child: const Text('一覧にない設備を自分で登録'),
          ),
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                if (failed) ...[
                  const Text('設備を取得できませんでした'),
                  TextButton(
                    onPressed: () => load(),
                    child: const Text('再読み込み'),
                  ),
                ],
                if (!busy && !failed && rows.isEmpty)
                  const ListTile(title: Text('検索結果がありません')),
                for (final e in rows)
                  ListTile(
                    key: ValueKey('selectMasterEquipment${e.id}'),
                    title: Text(e.name),
                    subtitle: Text(e.manufacturer ?? e.category),
                    onTap: () => Navigator.pop(
                      context,
                      PrivatePlaceEquipment(
                        id: 'master:${e.id}',
                        name: e.name,
                        equipmentId: e.id,
                      ),
                    ),
                  ),
                if (more)
                  TextButton(
                    onPressed: busy ? null : () => load(append: true),
                    child: const Text('さらに表示'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PrivateEquipmentEditor extends StatefulWidget {
  const _PrivateEquipmentEditor({required this.item});
  final PrivatePlaceEquipment item;
  @override
  State<_PrivateEquipmentEditor> createState() =>
      _PrivateEquipmentEditorState();
}

class _PrivateEquipmentEditorState extends State<_PrivateEquipmentEditor> {
  late final name = TextEditingController(text: widget.item.name),
      quantity = TextEditingController(
        text: widget.item.quantity?.toString() ?? '',
      );
  late final ids = {...widget.item.exerciseIds};
  String? error;
  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    super.dispose();
  }

  void save() {
    final q = quantity.text.trim().isEmpty ? null : int.tryParse(quantity.text);
    if (name.text.trim().isEmpty || name.text.trim().length > 120) {
      setState(() => error = '設備名を1〜120文字で入力してください');
      return;
    }
    if (quantity.text.trim().isNotEmpty && (q == null || q < 1 || q > 999)) {
      setState(() => error = '台数は1〜999、または空欄にしてください');
      return;
    }
    Navigator.pop(
      context,
      PrivatePlaceEquipment(
        id: widget.item.id,
        name: name.text.trim(),
        equipmentId: widget.item.equipmentId,
        quantity: q,
        exerciseIds: ids,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('設備を編集'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('privateEquipmentName'),
            controller: name,
            readOnly: widget.item.equipmentId != null,
            decoration: const InputDecoration(labelText: '設備名'),
          ),
          TextField(
            key: const Key('privateEquipmentQuantity'),
            controller: quantity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '台数（任意）'),
          ),
          if (widget.item.equipmentId == null) ...[
            for (final id in ids)
              ListTile(
                title: Text(ExerciseFormCatalog.byId[id]?.exerciseName ?? id),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => ids.remove(id)),
                ),
              ),
            TextButton(
              key: const Key('choosePrivateExercise'),
              onPressed: () async {
                final id = await selectPlaceExercise(context);
                if (id != null && mounted) setState(() => ids.add(id));
              },
              child: const Text('この設備でできる種目を選択'),
            ),
          ],
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('savePrivateEquipment'),
        onPressed: save,
        child: const Text('保存'),
      ),
    ],
  );
}
