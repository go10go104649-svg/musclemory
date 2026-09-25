import 'package:setkeep/trainer/tenant_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:setkeep/trainer/trainer_repository.dart';

import 'trainer_widgets.dart';
import 'menu_editor.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key, required this.repository, required this.link});
  final TrainerRepository repository;
  final Map<String, dynamic> link;
  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  List<Map<String, dynamic>> workouts = [], notes = [], menus = [];
  bool loading = true, more = true, busy = false;
  String? error;
  final note = TextEditingController();
  String get clientId => widget.link['client_id'] as String;
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final w =
          widget.link['linked_user_id'] != null &&
              widget.link['share_workouts'] == false
          ? <Map<String, dynamic>>[]
          : await widget.repository.workouts(clientId);
      final n = await widget.repository.notes(clientId);
      final m = await widget.repository.menus(clientId: clientId);
      if (mounted) {
        setState(() {
          workouts = w;
          notes = n;
          menus = m;
          more = w.length == 100;
        });
      }
    } catch (_) {
      if (mounted) {
        error = tr(
          context,
          '読み込めませんでした。連携が解除された可能性があります。',
          'Could not load data. Sharing may have been revoked.',
        );
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> act(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                '保存できませんでした。接続と権限を確認してください。',
                'Could not save. Check connection and permissions.',
              ),
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> comment({String? menu, String? date}) async {
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => TextPromptDialog(title: tr(ctx, 'コメント', 'Comment')),
    );
    if (!mounted || body == null || body.trim().isEmpty) return;
    await act(() async {
      await (widget.repository as TenantRepository).mutate('comment', {
        'client_id': clientId,
        'menu_id': menu,
        'date': date,
        'body': body.trim(),
      });
      await reload();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.link['client_name'] as String),
      actions: [IconButton(onPressed: reload, icon: const Icon(Icons.refresh))],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                tr(context, '基本情報', 'Basic information'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                tr(
                  context,
                  '連携日 ${dateLabel(widget.link['created_at'])}\n体重：非共有',
                  'Linked ${dateLabel(widget.link['created_at'])}\nBody weight: private',
                ),
              ),
              if (widget.repository is TenantRepository &&
                  widget.link['linked_user_id'] == null)
                OutlinedButton(
                  onPressed: () => act(() async {
                    final token = await (widget.repository as TenantRepository)
                        .inviteClient(clientId);
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(
                          tr(
                            ctx,
                            '本人のSETKEEPと連携',
                            'Link the client’s SETKEEP account',
                          ),
                        ),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QrImageView(
                                data:
                                    'setkeep://trainer/invite?v=1&token=$token',
                                size: 180,
                              ),
                              SelectableText(token),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(tr(ctx, '閉じる', 'Close')),
                          ),
                        ],
                      ),
                    );
                  }),
                  child: Text(
                    tr(
                      context,
                      '本人アカウントへの連携コード',
                      'Create account linking code',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: widget.link['allow_recording'] == true
                        ? () async {
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MenuEditor(
                                  repository: widget.repository,
                                  clients: [widget.link],
                                  recording: true,
                                ),
                              ),
                            );
                            if (context.mounted) await reload();
                          }
                        : null,
                    icon: const Icon(Icons.edit),
                    label: Text(tr(context, 'セッションを記録', 'Record session')),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MenuEditor(
                            repository: widget.repository,
                            clients: [widget.link],
                          ),
                        ),
                      );
                      if (context.mounted) await reload();
                    },
                    child: Text(tr(context, 'メニューを作成', 'Create menu')),
                  ),
                  OutlinedButton(
                    onPressed: widget.link['share_heatmap'] == true
                        ? () => act(() async {
                            final repo = widget.repository;
                            final history = repo is TenantRepository
                                ? await repo.heatmapHistory(clientId)
                                : workouts;
                            if (!context.mounted) return;
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HeatmapPage(workouts: history),
                              ),
                            );
                          })
                        : null,
                    child: Text(tr(context, 'ヒートマップ', 'Heatmap')),
                  ),
                ],
              ),
              Text(
                tr(
                  context,
                  '代理記録・ヒートマップは顧客が許可した場合のみ利用できます。',
                  'Session recording and heatmap require client permission.',
                ),
              ),
              const SizedBox(height: 24),
              Text(
                tr(
                  context,
                  '指導メモ（担当者間で共有）',
                  'Coaching notes (assigned trainers)',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextField(
                controller: note,
                maxLength: 10000,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: tr(
                    context,
                    'フォームの注意・次回確認事項など',
                    'Form cues, next session reminders…',
                  ),
                ),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => act(() async {
                        if (note.text.trim().isEmpty) return;
                        await widget.repository.addNote(clientId, note.text);
                        note.clear();
                        await reload();
                      }),
                child: Text(tr(context, 'メモを保存', 'Save note')),
              ),
              for (final n in notes)
                Card(
                  child: ListTile(
                    title: Text(n['body'] as String),
                    subtitle: Text(
                      '${dateLabel(n['created_at'])}${n['workout_date'] != null ? ' · ${n['workout_date']}' : ''}${n['menu_id'] != null ? ' · ${tr(context, 'メニュー', 'Menu')}' : ''}',
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                tr(context, 'トレーニングメニュー', 'Training menus'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final m in menus)
                Column(
                  children: [
                    MenuCard(menu: m),
                    if (widget.repository is TenantRepository)
                      Wrap(
                        children: [
                          if (m['status'] == 'planned')
                            TextButton(
                              onPressed: () async {
                                await Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MenuEditor(
                                      repository: widget.repository,
                                      clients: [widget.link],
                                      existing: m,
                                    ),
                                  ),
                                );
                                if (context.mounted) await reload();
                              },
                              child: Text(tr(context, '編集', 'Edit')),
                            ),
                          for (final status in [
                            'completed',
                            'canceled',
                            'planned',
                          ])
                            if ((m['status'] == 'planned' &&
                                    status == 'completed') ||
                                (m['status'] != 'canceled' &&
                                    status == 'canceled') ||
                                (m['status'] == 'canceled' &&
                                    status == 'planned'))
                              TextButton(
                                onPressed: () => act(() async {
                                  await (widget.repository as TenantRepository)
                                      .menuStatus(m, status);
                                  await reload();
                                }),
                                child: Text(
                                  status == 'completed'
                                      ? tr(context, '実施済み', 'Complete')
                                      : status == 'canceled'
                                      ? tr(context, '取消', 'Cancel')
                                      : tr(context, '復元', 'Restore'),
                                ),
                              ),
                          TextButton(
                            onPressed: () => comment(menu: m['id'] as String),
                            child: Text(tr(context, 'コメント', 'Comment')),
                          ),
                        ],
                      ),
                  ],
                ),
              if (menus.isEmpty)
                Text(tr(context, 'メニューはまだありません', 'No menus yet')),
              const SizedBox(height: 24),
              Text(
                tr(context, '最近のトレーニング・履歴', 'Recent workouts and history'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (workouts.isEmpty)
                EmptyState(
                  text: tr(
                    context,
                    '共有された記録はありません。顧客がSETKEEPの連携画面から記録を共有できます。',
                    'No shared records. Clients can share workouts from the SETKEEP linking page.',
                  ),
                ),
              for (final row in workouts)
                Column(
                  children: [
                    WorkoutCard(row: row),
                    if (widget.repository is TenantRepository)
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () =>
                                comment(date: dateLabel(row['performed_at'])),
                            child: Text(
                              tr(context, 'この日のコメント', 'Comment on this day'),
                            ),
                          ),
                          if (row['record_source'] == 'trainer')
                            TextButton(
                              onPressed: () => act(() async {
                                await (widget.repository as TenantRepository)
                                    .cancelRecord(
                                      clientId,
                                      row['id'] as String,
                                      row['canceled_at'] == null,
                                    );
                                await reload();
                              }),
                              child: Text(
                                row['canceled_at'] == null
                                    ? tr(context, '記録を取消', 'Cancel record')
                                    : tr(context, '記録を復元', 'Restore record'),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              if (more)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => act(() async {
                          final next = await widget.repository.workouts(
                            clientId,
                            offset: workouts.length,
                          );
                          if (context.mounted) {
                            setState(() {
                              workouts.addAll(next);
                              more = next.length == 100;
                            });
                          }
                        }),
                  child: Text(tr(context, 'さらに表示', 'Load more')),
                ),
            ],
          ),
  );
}
