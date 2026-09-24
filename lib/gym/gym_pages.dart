import 'dart:async';

import 'package:flutter/material.dart';

import '../exercise_form_catalog.dart';
import '../config/supabase_config.dart';
import 'gym_repository.dart';

Widget gymError(VoidCallback retry) => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    children: [
      Text(
        GymServices.override == null && !SupabaseConfig.initialized
            ? '店舗情報への接続設定が読み込まれていません。アカウント画面の状態も確認してください。アプリの再起動で改善しない場合は、接続設定を含むアプリへの更新が必要です。'
            : '店舗情報を取得できませんでした。通信状態を確認してください。',
      ),
      TextButton(onPressed: retry, child: const Text('再読み込み')),
    ],
  ),
);

class GymStoreSearchPage extends StatefulWidget {
  const GymStoreSearchPage({super.key});
  @override
  State<GymStoreSearchPage> createState() => _GymStoreSearchPageState();
}

class _GymStoreSearchPageState extends State<GymStoreSearchPage> {
  final _repo = GymServices.repository;
  final _controller = TextEditingController();
  Timer? _debounce;
  List<GymStore> _stores = [], _registered = [];
  bool _busy = true, _failed = false, _more = false;
  int _request = 0;
  bool _registeredFailed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      var registered = _registered;
      var registeredFailed = _registeredFailed;
      if (!more) {
        try {
          registered = await _repo.registered();
          registeredFailed = false;
        } catch (_) {
          registered = [];
          registeredFailed = true;
        }
      }
      final rows = await _repo.search(
        _controller.text,
        offset: more ? _stores.length : 0,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _registered = registered;
        _registeredFailed = registeredFailed;
        _stores = more ? [..._stores, ...rows] : rows;
        _more = rows.length == 30;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Widget _tile(GymStore s) => ListTile(
    key: ValueKey('selectGymStore${s.id}'),
    leading: const Icon(Icons.location_on_outlined),
    title: Text(s.displayName),
    subtitle: Text(
      [
        s.city,
        s.station,
        s.address,
      ].whereType<String>().where((v) => v.isNotEmpty).join(' ・ '),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.pop(context, s),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('店舗を探す')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('gymStoreSearchField'),
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '店名・市区町村・駅名で検索',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) {
                ++_request;
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => _load(),
                );
              },
              onSubmitted: (_) {
                _debounce?.cancel();
                _load();
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                if (_controller.text.trim().isEmpty &&
                    _registered.isNotEmpty) ...[
                  const ListTile(title: Text('登録済みの利用ジム')),
                  ..._registered.map(_tile),
                  const Divider(),
                ],
                if (_registeredFailed && !_failed)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('登録済みの利用ジムを読み込めませんでした。店舗検索は利用できます。'),
                  ),
                if (_failed) gymError(() => _load()),
                if (!_busy && !_failed && _stores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('検索結果がありません。別の店名・市区町村でお試しください。'),
                  ),
                ..._stores
                    .where(
                      (s) =>
                          _controller.text.trim().isNotEmpty ||
                          !_registered.any((r) => r.id == s.id),
                    )
                    .map(_tile),
                if (_more && !_failed)
                  TextButton(
                    onPressed: _busy ? null : () => _load(more: true),
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

class RegisteredGymsPage extends StatefulWidget {
  const RegisteredGymsPage({super.key});
  @override
  State<RegisteredGymsPage> createState() => _RegisteredGymsPageState();
}

class _RegisteredGymsPageState extends State<RegisteredGymsPage> {
  final _repo = GymServices.repository;
  List<GymStore> _stores = [];
  bool _busy = true, _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final stores = await _repo.registered();
      if (mounted) setState(() => _stores = stores);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final store = await Navigator.push<GymStore>(
      context,
      MaterialPageRoute(builder: (_) => const GymStoreSearchPage()),
    );
    if (store == null || !mounted) return;
    await _change(() => _repo.register(store));
  }

  Future<void> _change(Future<void> Function() operation) async {
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('利用ジムを保存できませんでした。再度お試しください。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('利用ジム')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('登録した店舗は本人だけに表示されます。未ログイン時はこの端末に保存します。'),
          if (_busy) const LinearProgressIndicator(),
          if (_failed) gymError(_load),
          if (!_busy && !_failed && _stores.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('利用ジムはまだ登録されていません'),
            ),
          for (final store in _stores)
            Card(
              child: ListTile(
                title: Text(store.displayName),
                subtitle: const Text('設備を見る'),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GymStoreEquipmentPage(store: store),
                  ),
                ),
                trailing: IconButton(
                  key: ValueKey('removeRegisteredGym${store.id}'),
                  tooltip: '利用ジムから削除',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _busy
                      ? null
                      : () => _change(() => _repo.unregister(store.id)),
                ),
              ),
            ),
          FilledButton.icon(
            key: const Key('registerGymButton'),
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('ジムを追加'),
          ),
        ],
      ),
    ),
  );
}

class GymStoreEquipmentPage extends StatefulWidget {
  const GymStoreEquipmentPage({
    super.key,
    required this.store,
    this.onAdd,
    this.existingIds = const {},
  });
  final GymStore store;
  final Future<void> Function(Set<String>)? onAdd;
  final Set<String> existingIds;
  @override
  State<GymStoreEquipmentPage> createState() => _GymStoreEquipmentPageState();
}

class _GymStoreEquipmentPageState extends State<GymStoreEquipmentPage> {
  final _repo = GymServices.repository;
  List<GymEquipment> _equipment = [];
  late final Set<String> _added = {...widget.existingIds};
  bool _busy = true, _failed = false, _more = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final rows = await _repo.equipment(
        widget.store.id,
        offset: more ? _equipment.length : 0,
      );
      if (mounted) {
        setState(() {
          _equipment = more ? [..._equipment, ...rows] : rows;
          _more = rows.length == 50;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _equipment.map((e) => e.category).toSet().toList()
      ..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.store.displayName, maxLines: 2),
        actions: [
          IconButton(
            key: const Key('reportNewGymEquipment'),
            tooltip: '設備情報を報告',
            icon: const Icon(Icons.outlined_flag),
            onPressed: () =>
                showGymEquipmentReport(context, widget.store, null),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.store.address != null) Text(widget.store.address!),
            const SizedBox(height: 8),
            const Text('掲載情報に基づく設備一覧です。未掲載の設備や変更がある場合があります。'),
            if (_busy) const LinearProgressIndicator(),
            if (_failed) gymError(() => _load()),
            if (!_busy && !_failed && _equipment.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.store.equipmentStatus == 'not_collected'
                      ? 'この店舗の設備情報は未取得です。通常の種目追加をご利用ください。'
                      : '設備情報がまだ登録されていません。設備がないことを示すものではありません。',
                ),
              ),
            for (final category in categories) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text(
                  category,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final e in _equipment.where((e) => e.category == category))
                Card(
                  child: ListTile(
                    key: ValueKey('gymEquipment${e.id}'),
                    title: Text(e.name),
                    subtitle: Text(
                      [
                        if (e.quantity != null) '${e.quantity}台',
                        if (e.exerciseIds.isEmpty &&
                            e.compositeRuleIds.isNotEmpty)
                          '他の設備と組み合わせて対応',
                        if (e.exerciseIds.isEmpty &&
                            e.compositeRuleIds.isEmpty)
                          '対応種目は現在準備中です',
                      ].join(' ・ '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GymEquipmentExercisesPage(
                          store: widget.store,
                          equipment: e,
                          existingIds: _added,
                          onAdd: widget.onAdd == null
                              ? null
                              : (ids) async {
                                  await widget.onAdd!(ids);
                                  _added.addAll(ids);
                                },
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            if (_more && !_failed)
              TextButton(
                onPressed: _busy ? null : () => _load(more: true),
                child: const Text('さらに表示'),
              ),
          ],
        ),
      ),
    );
  }
}

class GymEquipmentExercisesPage extends StatefulWidget {
  const GymEquipmentExercisesPage({
    super.key,
    required this.store,
    required this.equipment,
    this.onAdd,
    this.existingIds = const {},
  });
  final GymStore store;
  final GymEquipment equipment;
  final Future<void> Function(Set<String>)? onAdd;
  final Set<String> existingIds;
  @override
  State<GymEquipmentExercisesPage> createState() =>
      _GymEquipmentExercisesPageState();
}

class _GymEquipmentExercisesPageState extends State<GymEquipmentExercisesPage> {
  bool _busy = false;
  late final Set<String> _added = {...widget.existingIds};
  Future<void> _add(String id) async {
    setState(() => _busy = true);
    try {
      await widget.onAdd!({id});
      if (mounted) setState(() => _added.add(id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('種目を追加できませんでした。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forms =
        widget.equipment.exerciseIds
            .map(ExerciseFormCatalog.canonicalDefinition)
            .whereType<ExerciseFormDefinition>()
            .where((e) => e.selectable)
            .toSet()
            .toList()
          ..sort((a, b) => a.exerciseName.compareTo(b.exerciseName));
    return Scaffold(
      appBar: AppBar(title: Text(widget.equipment.name, maxLines: 2)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.store.displayName),
            if (widget.equipment.manufacturer != null)
              Text(widget.equipment.manufacturer!),
            if (widget.equipment.model != null) Text(widget.equipment.model!),
            const SizedBox(height: 16),
            const Text(
              'この設備でできる種目',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (forms.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  widget.equipment.compositeRuleIds.isNotEmpty
                      ? 'この設備は、ラック＋ベンチなど他の設備との組み合わせで対応種目を判定します。'
                      : '対応種目は現在準備中です',
                ),
              ),
            for (final f in forms)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        f.exerciseName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('${f.category} ・ ${f.equipmentLabel}'),
                      if (widget.onAdd != null)
                        TextButton.icon(
                          key: ValueKey('addGymExercise${f.exerciseId}'),
                          onPressed: _busy || _added.contains(f.exerciseId)
                              ? null
                              : () => _add(f.exerciseId),
                          icon: Icon(
                            _added.contains(f.exerciseId)
                                ? Icons.check
                                : Icons.add,
                          ),
                          label: Text(
                            _added.contains(f.exerciseId)
                                ? '追加済み'
                                : 'トレーニングへ追加',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              key: const Key('reportGymEquipment'),
              onPressed: () => showGymEquipmentReport(
                context,
                widget.store,
                widget.equipment,
              ),
              icon: const Icon(Icons.outlined_flag),
              label: const Text('設備情報の誤りを報告'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showGymEquipmentReport(
  BuildContext context,
  GymStore store,
  GymEquipment? equipment,
) async {
  final repo = GymServices.repository;
  if (!repo.canReport) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ログインが必要です'),
        content: const Text('マイページのアカウントからログインすると設備情報を報告できます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
    return;
  }
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ReportDialog(store: store, equipment: equipment, repo: repo),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.store,
    required this.equipment,
    required this.repo,
  });
  final GymStore store;
  final GymEquipment? equipment;
  final GymRepository repo;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late String _kind = widget.equipment == null ? 'added' : 'not_present';
  final _name = TextEditingController(), _comment = TextEditingController();
  bool _busy = false;
  String? _error;
  static const _kinds = {
    'not_present': '設置されていない',
    'removed': '撤去された',
    'added': '新しく追加された',
    'wrong_name': '名称が違う',
    'other': 'その他',
  };
  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_kind == 'added' && _name.text.trim().isEmpty) {
      setState(() => _error = '追加された設備名を入力してください');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.report(
        storeId: widget.store.id,
        equipmentId: _kind == 'added' ? null : widget.equipment?.id,
        kind: _kind,
        equipmentName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        comment: _comment.text,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('報告を受け付けました。確認後に情報を更新します。')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '送信できませんでした。連続送信は制限されています。時間をおいて再度お試しください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('設備情報を報告'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('gymReportKind'),
              initialValue: _kind,
              isExpanded: true,
              items: [
                for (final entry in _kinds.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _kind = v!),
            ),
            if (_kind == 'added' || _kind == 'wrong_name')
              TextField(
                key: const Key('gymReportEquipmentName'),
                controller: _name,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: _kind == 'added' ? '設備名（必須）' : '正しい設備名（任意）',
                ),
              ),
            TextField(
              key: const Key('gymReportComment'),
              controller: _comment,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'コメント（任意）'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('submitGymEquipmentReport'),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? '送信中…' : '報告を送信'),
        ),
      ],
    ),
  );
}
