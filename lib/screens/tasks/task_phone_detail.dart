import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api.dart';
import '../../models.dart';
import '../../motion_routes.dart';
import '../../panel.dart' show presentScreen;
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../toast_avoid.dart';
import '../../widgets.dart';
import '../agent_messaging.dart' show openAgentThread;
import '../artifact_viewer.dart' show openArtifact;
import '../session.dart' show SessionScreen;
import '../goals/goal_phone_page.dart' show openGoalPhonePage;
import 'task_phone.dart';

/// Push the phone task detail page (TK-01 detail): a page, not a sheet.
Future<void> openTaskPhoneDetail(
        BuildContext context, DaemonClient client, String taskId) =>
    Navigator.of(context).push<void>(AppPageRoute<void>(
      builder: (_) => TaskPhoneDetail(client: client, taskId: taskId),
    ));

/// Bar A, title, state and priority tags, fact rows, brief, activity, results,
/// session row and a pinned Mark done.
class TaskPhoneDetail extends StatefulWidget {
  const TaskPhoneDetail({super.key, required this.client, required this.taskId});
  final DaemonClient client;
  final String taskId;

  @override
  State<TaskPhoneDetail> createState() => _TaskPhoneDetailState();
}

class _TaskPhoneDetailState extends State<TaskPhoneDetail> {
  TaskItem? task;
  List<BoardEntry> log = const [];
  TaskLinks links = const TaskLinks();
  Map<String, String> titles = const {};
  Map<String, String> agentNames = const {};
  Map<String, SessionInfo> sessions = const {};
  List<ArtifactInfo> results = const [];
  Object? error;
  bool loading = true;
  bool busy = false;
  bool briefOpen = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<T?> _try<T>(Future<T> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final c = widget.client;
    try {
      final t = await c.getTask(widget.taskId);
      final r = await Future.wait<Object?>([
        _try(c.taskLog(widget.taskId)),
        _try(c.taskLinks(widget.taskId)),
        _try(c.tasks()),
        _try(c.coordinationAgents()),
        _try(c.sessions()),
        if (t.sessionId.isNotEmpty) _try(c.artifacts(t.sessionId)),
      ]);
      if (!mounted) return;
      final tasks = (r[2] as List<TaskItem>?) ?? const [];
      final agents = (r[3] as List<CoordinationAgent>?) ?? const [];
      final ss = (r[4] as List<SessionInfo>?) ?? const [];
      setState(() {
        task = t;
        log = (r[0] as List<BoardEntry>?) ?? const [];
        links = (r[1] as TaskLinks?) ?? const TaskLinks();
        titles = {for (final x in tasks) x.id: x.title};
        agentNames = {
          for (final a in agents)
            if (a.displayName.trim().isNotEmpty) a.id: a.displayName.trim(),
        };
        sessions = {for (final s in ss) s.id: s};
        results = r.length > 5 ? ((r[5] as List<ArtifactInfo>?) ?? const []) : const [];
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool get _canComplete => const {
        TaskStatus.todo,
        TaskStatus.inProgress,
        TaskStatus.inReview,
      }.contains(task?.status);

  Future<void> _setStatus(TaskStatus to, {String? done}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final t = await widget.client.setTaskStatus(widget.taskId, to);
      if (!mounted) return;
      setState(() => task = t);
      if (done != null) toast(context, done);
    } catch (e) {
      if (mounted) {
        toast(context, '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await confirmAction(context,
        title: 'Cancel this task?',
        body: task?.title ?? '',
        confirmLabel: 'Cancel task',
        danger: false);
    if (ok && mounted) await _setStatus(TaskStatus.cancelled);
  }

  void _openSession() {
    final id = task?.sessionId ?? '';
    if (id.isEmpty) return;
    final title = _sessionTitle();
    presentScreen(context,
        builder: (_, close) => SessionScreen(
            client: widget.client, sessionId: id, title: title, onMenu: close));
  }

  String _sessionTitle() {
    final s = sessions[task?.sessionId ?? ''];
    final name = taskOwner(task!, sessions, agentNames);
    if (name != null) return name;
    final t = (s?.title ?? '').trim();
    return t.isEmpty ? 'Session' : t;
  }

  Future<void> _more(BuildContext anchor) async {
    final t = task;
    if (t == null) return;
    final closed = t.status == TaskStatus.done || t.status == TaskStatus.cancelled;
    final picked = await showAppMenu<String>(context, anchor: anchor, below: true,
        alignEnd: true, items: [
      appMenuItem(value: 'copy', icon: 'link', label: 'Copy link'),
      if (t.sessionId.isNotEmpty)
        appMenuItem(value: 'session', icon: 'terminal', label: 'Open session'),
      if (!closed)
        appMenuItem(value: 'cancel', icon: 'x', label: 'Cancel task'),
      if (closed)
        appMenuItem(value: 'reopen', icon: 'arrow-counter-clockwise', label: 'Reopen'),
    ]);
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: 'task:${t.id}'));
        if (mounted) toast(context, 'Link copied');
      case 'session':
        _openSession();
      case 'cancel':
        await _cancel();
      case 'reopen':
        await _setStatus(TaskStatus.todo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = task;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _bar(),
          Expanded(child: t == null ? _stub() : _body(t)),
          if (t != null && _canComplete) _pinned(t),
        ]),
      ),
    );
  }

  Widget _bar() => ToastAvoid(
        child: SizedBox(
          height: 52,
          child: Row(children: [
            BarIcon('chevron-left', 'Back', () => Navigator.of(context).maybePop()),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Task',
                    style: sans(16, weight: W.label, color: AppColors.fg1)),
              ),
            ),
            if (task != null)
              Builder(
                builder: (a) => BarIcon('more-horizontal', 'More', () => _more(a)),
              ),
            const SizedBox(width: 4),
          ]),
        ),
      );

  Widget _stub() {
    if (loading) return const AppLoading(label: 'Loading task');
    return EmptyState(
      icon: 'alert-circle',
      title: "Couldn't load this task",
      body: 'Check the connection and try again.',
      action: StateButton('Retry', onTap: () {
        setState(() => loading = true);
        _load();
      }),
    );
  }

  Widget _tag(Widget? glyph, String word) => Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (glyph != null) ...[glyph, const SizedBox(width: 6)],
          Flexible(
            child: Text(word, style: sans(13, color: AppColors.fg2)),
          ),
        ]),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Semantics(
          header: true,
          child: Text(t, style: sans(12, weight: W.label, color: AppColors.fg3)),
        ),
      );

  Widget _fact(String label, Widget value, {VoidCallback? onTap}) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        const SizedBox(width: 16),
        SizedBox(
          width: 108,
          child: Text(label, style: sans(13, color: AppColors.fg3)),
        ),
        Expanded(child: value),
        const SizedBox(width: 16),
      ]),
    );
    final hair = Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: AppColors.border);
    final inner = Column(children: [row, hair]);
    if (onTap == null) return inner;
    return Semantics(
      button: true,
      label: label,
      child: TapDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: inner),
    );
  }

  Widget _person(String name) => Row(children: [
        OwnerAvatar(name, size: 24),
        const SizedBox(width: 8),
        Flexible(
          child: Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(15, color: AppColors.fg1)),
        ),
      ]);

  Widget _navRow(String text, VoidCallback onTap,
          {Key? key, double minHeight = 56, String? icon}) =>
      Semantics(
        button: true,
        label: text,
        excludeSemantics: true,
        child: TapDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                if (icon != null) ...[
                  AppIcon(icon, size: 16, color: AppColors.fg1),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15, color: AppColors.fg1)),
                ),
                AppIcon('chevron-right', size: 16, color: AppColors.fg3),
              ]),
            ),
          ),
        ),
      );

  static String _hhmm(String iso) {
    final at = DateTime.tryParse(iso)?.toLocal();
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }

  Widget _body(TaskItem t) {
    final owner = taskOwnerAgent(t, sessions, agentNames);
    final creator = t.createdByKind == 'agent'
        ? (agentNames[t.createdById] ??
            (t.createdById.isEmpty
                ? null
                : t.createdById[0].toUpperCase() + t.createdById.substring(1)))
        : (t.createdByKind == 'human' ? 'You' : null);
    final brief = t.description.trim();
    final briefLong = brief.split('\n').length > 8 || brief.length > 480;
    final entries = log.take(8).toList();
    return ListView(
      key: const ValueKey('task-detail-scroll'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 5, 16, 12),
          child: Semantics(
            header: true,
            child: Text(t.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: sans(20,
                    weight: W.label, height: 26 / 20, color: AppColors.fg1)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            _tag(TaskGlyph(t.status, size: 14), taskStateWord(t.status)),
            _tag(null, '${priorityWord(t.priority)} priority'),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: AppColors.border),
        if (owner != null)
          _fact('Owner', _person(owner.name),
              onTap: owner.id == null || owner.id == 'lead'
                  ? null
                  : () => openAgentThread(context,
                      client: widget.client,
                      agentId: owner.id!,
                      agentName: owner.name)),
        if (creator != null) _fact('Created by', _person(creator)),
        if (brief.isNotEmpty) ...[
          _label('Brief'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(brief,
                maxLines: briefOpen ? null : 8,
                overflow: briefOpen ? TextOverflow.visible : TextOverflow.ellipsis,
                style: sans(15, height: 21 / 15, color: AppColors.fg1)),
          ),
          if (briefLong && !briefOpen)
            _navRow('More', () => setState(() => briefOpen = true),
                minHeight: 48, key: const ValueKey('brief-more')),
        ],
        if (entries.isNotEmpty) ...[
          _label('Activity'),
          for (final e in entries)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(width: 17.5),
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                            color: AppColors.fg3, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 11.5),
                  SizedBox(
                    width: 58,
                    child: Text(_hhmm(e.createdAt),
                        style: sans(12, color: AppColors.fg3)),
                  ),
                  Expanded(
                    child: Text(e.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg2)),
                  ),
                  const SizedBox(width: 16),
                ]),
              ),
            ),
        ],
        if (results.isNotEmpty) ...[
          _label('Results'),
          for (final a in results) _result(t, a, owner?.name),
        ],
        if (t.sessionId.isNotEmpty ||
            links.blockedBy.isNotEmpty ||
            t.goalId != null) ...[
          const SizedBox(height: 8),
          for (final b in links.blockedBy)
            _navRow('Blocked by ${titles[b] ?? b}',
                () => openTaskPhoneDetail(context, widget.client, b),
                icon: 'x', key: ValueKey('blocked-$b')),
          if (t.goalId != null && (t.goalTitle ?? '').isNotEmpty)
            _navRow('Goal: ${t.goalTitle}',
                () => openGoalPhonePage(context, widget.client, t.goalId!),
                key: const ValueKey('goal-row')),
          if (t.sessionId.isNotEmpty)
            _navRow('Session: ${_sessionTitle()}', _openSession,
                key: const ValueKey('session-row')),
        ],
      ],
    );
  }

  Widget _result(TaskItem t, ArtifactInfo a, String? owner) {
    final at = a.latest == null
        ? ''
        : shortAgo(DateTime.fromMillisecondsSinceEpoch(a.latest!.createdAt * 1000)
            .toUtc()
            .toIso8601String());
    final kind = a.kind == 'canvas' ? 'Canvas' : (a.kind == 'document' ? 'Document' : 'File');
    final sub = [kind, if (owner != null) owner, if (at.isNotEmpty) at].join(' - ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        button: true,
        label: '${a.title}, $sub',
        excludeSemantics: true,
        child: TapDetector(
          key: ValueKey('result-${a.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => openArtifact(context,
              client: widget.client,
              session: t.sessionId,
              id: a.id,
              version: a.latest?.n),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              AppIcon('file-text', size: 20, color: AppColors.fg2),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(14, weight: W.label, color: AppColors.fg1)),
                        const SizedBox(height: 2),
                        Text(sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12.5, color: AppColors.fg3)),
                      ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pinned(TaskItem t) {
    final review = t.status == TaskStatus.inReview;
    final label = busy
        ? 'Marking done...'
        : (review ? 'Approve and mark done' : 'Mark done');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Semantics(
        button: true,
        enabled: !busy,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          key: const ValueKey('mark-done'),
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : () => _setStatus(TaskStatus.done, done: 'Marked done'),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: busy ? AppColors.surface3 : AppColors.fg1,
                borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('check',
                  size: 16, color: busy ? AppColors.fg3 : AppColors.bg),
              const SizedBox(width: 8),
              Flexible(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.35,
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: sans(14,
                          weight: W.label,
                          color: busy ? AppColors.fg3 : AppColors.bg)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
