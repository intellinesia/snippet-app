import 'package:flutter/material.dart';

import '../../api.dart';
import '../../mobile_kit.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../theme.dart';
import '../tasks/task_common.dart' show openTaskDetail;

/// Kind label for an inbox entry: Assignment, Question or Result.
String inboxKind(InboxEntry e) {
  if (e.postKind == 'question') return 'Question';
  if (e.source == 'offer') return 'Assignment';
  if (e.postKind == 'result' || e.envelope == 'result') return 'Result';
  return 'Message';
}

/// A question is waiting when no later entry in its thread came from the user.
bool inboxWaiting(InboxEntry e, List<InboxEntry> all) =>
    e.postKind == 'question' &&
    e.fromKind != 'human' &&
    !all.any((o) =>
        o.threadId == e.threadId && o.fromKind == 'human' && o.id > e.id);

String _ago(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'now';
  if (m < 60) return '${m}m';
  if (m < 1440) return '${m ~/ 60}h';
  return '${m ~/ 1440}d';
}

/// Agent work and records (HM-08): Inbox and Board tabs.
class AgentWorkPage extends StatefulWidget {
  const AgentWorkPage(
      {super.key,
      required this.client,
      required this.agentId,
      required this.agentName,
      this.initialTab = 0});
  final DaemonClient client;
  final String agentId, agentName;
  final int initialTab;

  @override
  State<AgentWorkPage> createState() => _AgentWorkPageState();
}

class _AgentWorkPageState extends State<AgentWorkPage> {
  late int _tab = widget.initialTab;
  List<InboxEntry>? _inbox;
  List<TaskItem>? _tasks;

  @override
  void initState() {
    super.initState();
    widget.client.agentInbox(widget.agentId, limit: 50).then((l) {
      if (mounted) setState(() => _inbox = l);
    }).catchError((_) {
      if (mounted) setState(() => _inbox = const []);
    });
    widget.client.tasks(agentId: widget.agentId).then((l) {
      if (mounted) setState(() => _tasks = l);
    }).catchError((_) {
      if (mounted) setState(() => _tasks = const []);
    });
  }

  Widget _inboxRow(InboxEntry e, List<InboxEntry> all) {
    final waiting = inboxWaiting(e, all);
    final body = (e.title?.isNotEmpty == true ? e.title! : e.text)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return MkGroupRow(
      key: ValueKey('inbox-${e.id}'),
      icon: switch (inboxKind(e)) {
        'Question' => 'help-circle',
        'Assignment' => 'inbox',
        'Result' => 'check-circle',
        _ => 'message',
      },
      label: body,
      subtitle:
          '${inboxKind(e)} \u00b7 ${_ago(e.createdAt)}${waiting ? ' \u00b7 Needs you' : ''}',
      chevron: false,
      trailing: waiting ? const QuietHand(size: 18) : null,
      onTap: e.taskId == null || e.taskId!.isEmpty
          ? null
          : () => openTaskDetail(context, widget.client, e.taskId!),
    );
  }

  List<Widget> _inboxBody() {
    final l = _inbox;
    if (l == null) return [const MkEmpty('Loading')];
    if (l.isEmpty) return [const MkEmpty('Nothing in the inbox')];
    return [
      MkGroup(children: [for (final e in l) _inboxRow(e, l)])
    ];
  }

  List<Widget> _boardBody() {
    final l = _tasks;
    if (l == null) return [const MkEmpty('Loading')];
    final cols = <(String, bool Function(TaskItem))>[
      ('Todo', (t) => t.status == TaskStatus.todo),
      (
        'Doing',
        (t) =>
            t.status == TaskStatus.inProgress ||
            t.status == TaskStatus.inReview ||
            t.status == TaskStatus.blocked
      ),
      ('Done', (t) => t.status == TaskStatus.done),
    ];
    final out = <Widget>[];
    for (final (label, test) in cols) {
      final items = [
        for (final t in l)
          if (test(t)) t
      ];
      if (items.isEmpty) continue;
      out.add(MkGroup(header: '$label  ${items.length}', children: [
        for (final t in items)
          MkGroupRow(
            key: const ValueKey('board-card'),
            icon: 'list-checks',
            label: t.title,
            subtitle: widget.agentName,
            chevron: false,
            onTap: () => openTaskDetail(context, widget.client, t.id),
          ),
      ]));
    }
    if (out.isEmpty) out.add(const MkEmpty('No tasks yet'));
    return out;
  }

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bg,
        child: MkPage(
          title: 'Work',
          onBack: () => Navigator.of(context).pop(),
          bottomClearance: false,
          filters: MkFilterGroup<int>(
            selected: _tab,
            onSelect: (i) => setState(() => _tab = i),
            options: const [MkFilter(0, 'Inbox'), MkFilter(1, 'Board')],
          ),
          slivers: [
            SliverList(
                delegate: SliverChildListDelegate([
              const SizedBox(height: 8),
              ..._tab == 0 ? _inboxBody() : _boardBody(),
              const SizedBox(height: 24),
            ])),
          ],
        ),
      );
}
