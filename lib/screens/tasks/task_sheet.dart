import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api.dart';
import '../../markdown_preview.dart';
import '../../models.dart';
import '../../panel.dart' show presentScreen;
import '../../platform.dart';
import '../../shell_panel.dart' show openSessionInTab;
import '../../theme.dart';
import '../../widgets.dart';
import '../session.dart' show SessionScreen;
import 'task_detail_screen.dart';

/// The phone's task detail: a tall sheet with the summary, what the agent did,
/// the decisions logged on the task and what it touched. Anything deeper stays
/// one tap away under "Open full details".
Future<void> showTaskSheet(
    BuildContext context, DaemonClient client, String taskId) {
  return showModalBottomSheet<void>(
    sheetAnimationStyle: sheetMotion,
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (sheet) {
      final media = MediaQuery.of(sheet);
      final top = media.padding.top + 8;
      return SizedBox(
        height: media.size.height - top,
        child: TaskSheet(
            client: client,
            taskId: taskId,
            onClose: () => Navigator.of(sheet).pop()),
      );
    },
  );
}

class TaskSheet extends StatefulWidget {
  const TaskSheet(
      {super.key,
      required this.client,
      required this.taskId,
      required this.onClose});
  final DaemonClient client;
  final String taskId;
  final VoidCallback onClose;

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  TaskItem? task;
  List<BoardEntry> log = const [];
  List<TaskTurn> turns = const [];
  String agent = '';
  String folder = '';
  String? sessionId;
  Object? error;
  bool loading = true;
  bool busy = false;

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
      final results = await Future.wait<Object?>([
        _try(c.taskLog(widget.taskId)),
        _try(c.taskTurns(widget.taskId)),
        _try(c.coordinationAgents()),
        _try(c.sessions()),
      ]);
      if (!mounted) return;
      final agents = (results[2] as List<CoordinationAgent>?) ?? const [];
      final sessions = (results[3] as List<SessionInfo>?) ?? const [];
      final id = t.createdByKind == 'agent' ? t.createdById : '';
      final named = agents.where((a) => a.id == id).firstOrNull;
      final s = sessions.where((s) => s.id == t.sessionId).firstOrNull;
      final parts = (s?.projectFolder ?? '').split('/').where((p) => p.isNotEmpty);
      setState(() {
        task = t;
        log = (results[0] as List<BoardEntry>?) ?? const [];
        turns = (results[1] as List<TaskTurn>?) ?? const [];
        agent = named != null && named.displayName.trim().isNotEmpty
            ? named.displayName.trim()
            : (id.isEmpty ? '' : id[0].toUpperCase() + id.substring(1));
        folder = parts.isEmpty ? '' : parts.last;
        sessionId = t.sessionId.isEmpty ? null : t.sessionId;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    await _load();
  }

  Future<void> _verdict(TaskStatus to) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.client.setTaskStatus(widget.taskId, to);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _openFull() {
    final nav = Navigator.of(context);
    widget.onClose();
    nav.push(MaterialPageRoute<void>(
      builder: (page) => Material(
        color: AppColors.bg,
        child: SafeArea(
          child: TaskDetailScreen(
              client: widget.client,
              taskId: widget.taskId,
              onClose: () => Navigator.of(page).pop()),
        ),
      ),
    ));
  }

  void _openSession() {
    final id = sessionId;
    if (id == null) return;
    final tab = openSessionInTab;
    if (!kMobile && tab != null) {
      tab(widget.client, id, agent.isEmpty ? 'Session' : agent);
      return;
    }
    presentScreen(context,
        builder: (_, close) => SessionScreen(
            client: widget.client,
            sessionId: id,
            title: agent.isEmpty ? 'Session' : agent,
            onMenu: close));
  }

  static String _hhmm(String iso) {
    final at = DateTime.tryParse(iso)?.toLocal();
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color.alphaBlend(AppColors.fg1.withValues(alpha: 0.07), AppColors.bg);
    final t = task;
    return Material(
      color: bg,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      child: Column(children: [
        SizedBox(height: 10),
        Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(3)),
        ),
        SizedBox(height: 10),
        Expanded(
          child: t == null
              ? _stub()
              : ListView(
                  key: const ValueKey('task-sheet-scroll'),
                  padding: EdgeInsets.only(
                      bottom: 24 + MediaQuery.of(context).padding.bottom),
                  children: _content(t)),
        ),
      ]),
    );
  }

  Widget _stub() => Stack(children: [
        Positioned(top: 0, right: 20, child: _icons()),
        Center(
          child: loading
              ? const AppLoading(label: 'Loading task')
              : Text('Could not load this task',
                  style: sans(15, color: AppColors.fg3)),
        ),
      ]);

  Widget _icons() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _iconBtn(LucideIcons.rotateCcw300, 'Refresh', _refresh),
          _iconBtn(LucideIcons.x300, 'Close', widget.onClose),
        ]),
      );

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) =>
      Semantics(
        button: true,
        label: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 22, color: AppColors.fg2)),
        ),
      );

  List<Widget> _content(TaskItem t) {
    final who = agent;
    final first = _summary(t.description);
    final updated = _hhmm(t.updatedAt);
    final meta = [
      if (updated.isNotEmpty) 'Last updated $updated',
      if (who.isNotEmpty) who,
      if (folder.isNotEmpty) folder,
    ].join(' · ');
    final plan = t.workPlan;
    final entries = log.take(8).toList();
    final commits = {for (final x in turns) ...x.commits}.length;
    final files = {for (final x in turns) ...x.files}.length;
    final inReview = t.status == TaskStatus.inReview;
    return [
      Padding(
        padding: const EdgeInsets.only(left: 20, right: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Text(t.title,
                  key: const ValueKey('task-sheet-title'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 23 : 18,
                      weight: W.label,
                      height: 30 / 23,
                      spacing: -0.2,
                      color: AppColors.fg1)),
            ),
          ),
          SizedBox(width: 4),
          _icons(),
        ]),
      ),
      if (first.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(first,
              style: sans(16, height: 24 / 16, color: AppColors.fg1)),
        ),
      if (meta.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(meta, style: sans(14, color: AppColors.fg3)),
        ),
      if (plan.isNotEmpty) ...[
        _h2(who.isEmpty ? 'What was done' : 'What $who did', 26),
        for (final s in plan) _step(s),
      ],
      _Wave(),
      _h2('Decisions and updates', 26),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Text('Nothing logged yet.',
              style: sans(14, color: AppColors.fg3)),
        )
      else
        for (final e in entries) _update(e),
      _h2('Resources', 30),
      if (sessionId != null)
        _resource(LucideIcons.terminal300, 'Session',
            [if (who.isNotEmpty) who, if (folder.isNotEmpty) folder].join(' · '),
            onTap: _openSession),
      if (commits > 0 || files > 0)
        _resource(LucideIcons.gitBranch300, 'Changes',
            [
              if (commits > 0) '$commits ${commits == 1 ? 'commit' : 'commits'}',
              if (files > 0) '$files ${files == 1 ? 'file' : 'files'}',
            ].join(' · ')),
      _resource(LucideIcons.fileText300, 'Open full details',
          'Chat, crew, links and history',
          onTap: _openFull),
      if (inReview)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          child: Row(children: [
            Expanded(
              child: Btn('Send back',
                  key: const ValueKey('task-sheet-send-back'),
                  variant: BtnVariant.surface,
                  full: true,
                  disabled: busy,
                  onTap: () => _verdict(TaskStatus.inProgress)),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Btn('Approve',
                  key: const ValueKey('task-sheet-approve'),
                  full: true,
                  disabled: busy,
                  onTap: () => _verdict(TaskStatus.done)),
            ),
          ]),
        ),
    ];
  }

  static String _summary(String raw) {
    final paras = raw
        .split(RegExp(r'\n\s*\n'))
        .map((p) => plainPreview(p).trim())
        .where((p) => p.isNotEmpty);
    return paras.isEmpty ? '' : paras.first;
  }

  Widget _h2(String text, double top) => Padding(
        padding: EdgeInsets.fromLTRB(20, top, 20, 10),
        child: Text(text,
            style: sans(15, weight: W.label, color: AppColors.fg1)),
      );

  Widget _step(WorkStep s) {
    final Widget mark;
    if (s.done) {
      mark = Container(
        width: 20,
        height: 20,
        decoration:
            BoxDecoration(color: AppColors.fg3, shape: BoxShape.circle),
        child: Icon(LucideIcons.check, size: 12, color: AppColors.bg),
      );
    } else if (s.current) {
      mark = Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accent, width: 1.5)),
        child: Center(
          child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: AppColors.accent, shape: BoxShape.circle)),
        ),
      );
    } else {
      mark = Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.fg4, width: 1.5)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: mark),
        SizedBox(width: 14),
        Expanded(
          child: Text(s.step,
              style: sans(16,
                  height: 23 / 16,
                  color: s.current ? AppColors.fg1 : AppColors.fg2)),
        ),
      ]),
    );
  }

  Widget _update(BoardEntry e) {
    final text = e.summary.trim();
    final turn = RegExp(r'\b(turn|lease|handed|passed)\b', caseSensitive: false)
        .hasMatch(text);
    final time = _hhmm(e.createdAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 20,
          height: 23,
          child: Center(
            child: turn
                ? Icon(LucideIcons.arrowRightLeft300,
                    size: 16, color: AppColors.fg3)
                : Text('•', style: sans(14, color: AppColors.fg3)),
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: sans(16, height: 23 / 16, color: AppColors.fg1)),
            if (time.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(time, style: sans(14, color: AppColors.fg3)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _resource(IconData icon, String title, String sub,
      {VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: Color.alphaBlend(
                    AppColors.fg1.withValues(alpha: 0.06), AppColors.bg),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.fg2),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(16, height: 22 / 16, color: AppColors.fg1)),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, color: AppColors.fg3)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Wave extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: CustomPaint(
          size: const Size(double.infinity, 8),
          painter: _WavePainter(AppColors.border2),
        ),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..moveTo(0, 4);
    for (double x = 0; x < size.width; x += 16) {
      path.quadraticBezierTo(x + 4, 0, x + 8, 4);
      path.quadraticBezierTo(x + 12, 8, x + 16, 4);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}
