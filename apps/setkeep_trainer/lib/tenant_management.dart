import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:setkeep/trainer/tenant_repository.dart';

import 'trainer_widgets.dart';

class TenantManagement extends StatefulWidget {
  const TenantManagement({
    super.key,
    required this.repository,
    required this.tenant,
  });
  final TenantRepository repository;
  final Map<String, dynamic> tenant;
  @override
  State<TenantManagement> createState() => _TenantManagementState();
}

class _TenantManagementState extends State<TenantManagement> {
  List<Map<String, dynamic>>? members, clients, assignments;
  Map<String, dynamic>? billing;
  String? error;
  bool busy = false, inviteAdmin = false, inviteTrainer = true;
  final name = TextEditingController(),
      email = TextEditingController(),
      code = TextEditingController();
  bool get owner =>
      widget.tenant['billing_owner_id'] == widget.repository.userId;
  bool get admin =>
      members
          ?.where((m) => m['user_id'] == widget.repository.userId)
          .firstOrNull?['is_admin'] ==
      true;
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final m = await widget.repository.members();
      final c = await widget.repository.clients();
      final a = await widget.repository.assignments();
      final b = owner ? await widget.repository.billing() : null;
      if (mounted) {
        setState(() {
          members = m;
          clients = c;
          assignments = a;
          billing = b;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(context, '読み込めませんでした', 'Could not load settings'),
        );
      }
    }
  }

  Future<void> run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
      await reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            context,
            '処理できませんでした。権限・招待先・トライアルの人数上限を確認してください。',
            'Action failed. Check permissions, invitation email and trial seat limit.',
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> showCode(String token) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr(ctx, '24時間・1回限りの招待', 'One-use invitation, valid 24 hours'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: 'setkeep://trainer/invite?v=1&token=$token',
                size: 180,
              ),
              SelectableText(token),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: token)),
            child: Text(tr(ctx, 'コピー', 'Copy')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(ctx, '閉じる', 'Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.tenant['name'] as String)),
    body: AbsorbPointer(
      absorbing: busy,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (error != null) Text(error!),
          if (busy || members == null) const LinearProgressIndicator(),
          TextField(
            controller: code,
            decoration: InputDecoration(
              labelText: tr(
                context,
                '別テナントのスタッフ招待コード',
                'Staff invitation to another tenant',
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => run(() async {
              await widget.repository.acceptInvite(
                code.text.trim(),
                '',
                recording: false,
                heatmap: false,
              );
              if (context.mounted) Navigator.pop(context);
            }),
            child: Text(tr(context, '招待を受ける', 'Accept invitation')),
          ),
          if (billing != null) ...[
            Text(
              tr(context, '契約・請求', 'Subscription & billing'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${billing!['status']} · ${billing!['active_trainers']} Trainer IDs\n¥${billing!['monthly_jpy']} / ${tr(context, '月', 'month')}',
            ),
            Text(
              tr(
                context,
                '月額3,980円（5名まで）、追加1名500円。14日間のトライアルはカード登録後に開始し、5名までです。決済画面の接続は準備中です。',
                '¥3,980/month includes 5 trainers, then ¥500 per trainer. The 14-day trial requires a card and allows 5 trainers. Checkout integration is pending.',
              ),
            ),
          ],
          if (admin) ...[
            const SizedBox(height: 24),
            Text(
              tr(context, 'オフライン顧客を登録', 'Create an offline client'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextField(
              controller: name,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: tr(context, '顧客名', 'Client name'),
              ),
            ),
            FilledButton(
              onPressed: () => run(() async {
                await widget.repository.mutate('client', {
                  'name': name.text.trim(),
                });
                name.clear();
              }),
              child: Text(tr(context, '登録', 'Create')),
            ),
            const SizedBox(height: 24),
            Text(
              tr(context, 'スタッフを招待', 'Invite staff'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: tr(context, '招待先メール', 'Invited email'),
              ),
            ),
            CheckboxListTile(
              value: inviteAdmin,
              onChanged: (v) => setState(() => inviteAdmin = v!),
              title: const Text('Admin'),
            ),
            CheckboxListTile(
              value: inviteTrainer,
              onChanged: (v) => setState(() => inviteTrainer = v!),
              title: const Text('Trainer'),
            ),
            FilledButton(
              onPressed: !inviteAdmin && !inviteTrainer
                  ? null
                  : () => run(() async {
                      final r = await widget.repository.mutate('staff_invite', {
                        'email': email.text.trim(),
                        'admin': inviteAdmin,
                        'trainer': inviteTrainer,
                      });
                      await showCode(r['id'] as String);
                    }),
              child: Text(tr(context, 'コードを発行', 'Create code')),
            ),
          ],
          for (final m in members ?? <Map<String, dynamic>>[])
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(m['display_name'] as String? ?? 'Member'),
                    subtitle: Text(
                      '${m['status']}${widget.tenant['billing_owner_id'] == m['user_id'] ? ' · Billing Owner' : ''}',
                    ),
                  ),
                  if (admin) ...[
                    for (final role in ['admin', 'trainer'])
                      CheckboxListTile(
                        title: Text(role == 'admin' ? 'Admin' : 'Trainer'),
                        value: m['is_$role'] == true,
                        onChanged: (v) => run(() async {
                          await widget.repository.mutate('member', {
                            'user_id': m['user_id'],
                            'admin': role == 'admin' ? v : m['is_admin'],
                            'trainer': role == 'trainer' ? v : m['is_trainer'],
                            'status': m['status'],
                          });
                        }),
                      ),
                    TextButton(
                      onPressed: () => run(() async {
                        await widget.repository.mutate('member', {
                          'user_id': m['user_id'],
                          'admin': m['is_admin'],
                          'trainer': m['is_trainer'],
                          'status': m['status'] == 'active'
                              ? 'removed'
                              : 'active',
                        });
                      }),
                      child: Text(
                        m['status'] == 'active'
                            ? tr(context, '所属を解除', 'Remove membership')
                            : tr(context, '再有効化', 'Reactivate'),
                      ),
                    ),
                    if (owner &&
                        m['user_id'] != widget.repository.userId &&
                        m['status'] == 'active')
                      TextButton(
                        onPressed: () => run(() async {
                          await widget.repository.mutate('owner', {
                            'user_id': m['user_id'],
                          });
                          if (context.mounted) Navigator.pop(context);
                        }),
                        child: Text(
                          tr(
                            context,
                            '請求責任者をこのメンバーに移譲',
                            'Transfer billing ownership',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          if (admin)
            for (final c in clients ?? <Map<String, dynamic>>[])
              Card(
                child: ExpansionTile(
                  title: Text(c['client_name'] as String),
                  subtitle: Text(tr(context, '担当者の割当', 'Trainer assignments')),
                  children: [
                    for (final m in members ?? <Map<String, dynamic>>[])
                      if (m['is_trainer'] == true && m['status'] == 'active')
                        CheckboxListTile(
                          title: Text(m['display_name'] as String? ?? 'Member'),
                          value: assignments!.any(
                            (a) =>
                                a['client_id'] == c['id'] &&
                                a['user_id'] == m['user_id'],
                          ),
                          onChanged: (v) => run(() async {
                            await widget.repository.mutate(
                              v! ? 'assign' : 'unassign',
                              {'client_id': c['id'], 'user_id': m['user_id']},
                            );
                          }),
                        ),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}
