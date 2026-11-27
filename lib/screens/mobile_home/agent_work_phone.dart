import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../tasks/task_common.dart' show openTaskDetail;
import 'agents_home.dart';

// Cards and segments sit 16 in from the screen edge on the board.
const double _inset = 16;

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
    return Semantics(
      button: true,
      label: '${inboxKind(e)}, ${_ago(e.createdAt)}, $body${waiting ? ', Needs you' : ''}',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: e.taskId == null || e.taskId!.isEmpty
            ? null
            : () => openTaskDetail(context, widget.client, e.taskId!),
        child: Container(
          key: ValueKey('inbox-${e.id}'),
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(21, 10, _inset, 10),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 1))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AppIcon(
                  switch (inboxKind(e)) {
                    'Question' => 'help-circle',
                    'Assignment' => 'inbox',
                    'Result' => 'check-circle',
                    _ => 'message',
                  },
                  size: 20,
                  color: AppColors.fg2),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(inboxKind(e),
                      style: sans(11, weight: FontWeight.w500, color: AppColors.fg3)),
                  if (waiting) ...[
                    const SizedBox(width: 8),
                    const QuietHand(size: 16),
                    const SizedBox(width: 4),
                    Text('Needs you',
                        style: sans(11, weight: FontWeight.w500, color: quietAmber)),
                  ],
                  const Spacer(),
                  Text(_ago(e.createdAt), style: sans(11, color: AppColors.fg3)),
                ]),
                const SizedBox(height: 2),
                Text(body,
                    maxLines: bigText(context) ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, color: AppColors.fg1)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _inboxBody() {
    final l = _inbox;
    if (l == null) return [const _Note('Loading')];
    if (l.isEmpty) return [const _Note('Nothing in the inbox')];
    return [for (final e in l) _inboxRow(e, l)];
  }

  List<Widget> _boardBody() {
    final l = _tasks;
    if (l == null) return [const _Note('Loading')];
    final cols = <(String, bool Function(TaskItem))>[
      ('Todo', (t) => t.status == TaskStatus.todo),
      ('Doing', (t) =>
          t.status == TaskStatus.inProgress ||
          t.status == TaskStatus.inReview ||
          t.status == TaskStatus.blocked),
      ('Done', (t) => t.status == TaskStatus.done),
    ];
    final out = <Widget>[];
    for (final (label, test) in cols) {
      final items = [for (final t in l) if (test(t)) t];
      out.add(HomeLabel('$label  ${items.length}', top: 16));
      for (final t in items) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, 8),
          child: Semantics(
            button: true,
            label: '${t.title}, ${widget.agentName}',
            excludeSemantics: true,
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openTaskDetail(context, widget.client, t.id),
              child: Container(
                key: const ValueKey('board-card'),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: sans(14, color: AppColors.fg1)),
                      Text(widget.agentName,
                          style: sans(11, color: AppColors.fg3)),
                    ]),
              ),
            ),
          ),
        ));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bg,
        child: SafeArea(
          child: Column(children: [
            PushedBar(title: widget.agentName, subtitle: 'Work and records'),
            SpecTabs(
                labels: const ['Inbox', 'Board'],
                index: _tab,
                onTap: (i) => setState(() => _tab = i)),
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: _tab == 0 ? _inboxBody() : _boardBody())),
          ]),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(_inset * 2),
      child: Center(child: Text(text, style: sans(14, color: AppColors.fg3))));
}
