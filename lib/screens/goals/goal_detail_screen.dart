import 'package:flutter/material.dart';

import '../mobile_chrome.dart';

import '../../api.dart';
import '../../goal_models.dart';
import '../../models.dart';
import '../../platform.dart';
import '../../task_reason.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../tasks/task_common.dart';
import 'goal_widgets.dart';

class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({
    super.key,
    required this.client,
    required this.goalId,
    this.onClose,
  });

  final DaemonClient client;
  final String goalId;
  final VoidCallback? onClose;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  GoalDetail? _detail;
  String? _error;
  final _open = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.client.goal(widget.goalId);
      if (mounted) {
        setState(() {
          _detail = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Widget _section(String label, Widget child) => Padding(
        padding: EdgeInsets.only(top: S.s16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6),
            child: Text(label, style: sans(13, color: AppColors.fg3)),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s4),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.of(14)),
              border: Border.all(color: AppColors.line),
            ),
            child: child,
          ),
        ]),
      );

  Widget _stat(String value, String label) => Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.of(10)),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.of(12)),
            border: Border.all(color: AppColors.line),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: codeMono(16, weight: W.label, color: AppColors.fg1)),
            SizedBox(height: S.s2),
            Text(label, style: sans(12, color: AppColors.fg3)),
          ]),
        ),
      );

  Widget _tick(bool done, {Key? key}) => SizedBox(
        key: key,
        width: 18,
        height: 18,
        child: Center(
          child: done
              ? AppIcon('check', size: 15, color: AppColors.ok)
              : Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.fg4, width: 1.5),
                  ),
                ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (kMobile)
            MobileBackBar(
                title: 'Goal',
                onBack: widget.onClose ?? () => Navigator.of(context).pop())
          else
          Padding(
            padding: EdgeInsets.fromLTRB(S.s6, S.s8, S.of(10), S.s4),
            child: Row(children: [
              IconBtn('chevron-left',
                  size: kMobile ? M.minTarget : 28,
                  iconSize: 15,
                  tooltip: 'Back',
                  onTap: widget.onClose ?? () => Navigator.of(context).pop()),
              SizedBox(width: S.s4),
              Expanded(
                child: Text('Goal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, weight: W.label, color: AppColors.fg1)),
              ),
            ]),
          ),
          Expanded(child: _body(d)),
        ]),
      ),
    );
  }

  Widget _body(GoalDetail? d) {
    if (d == null) {
      return _error != null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(S.s24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: sans(12, color: AppColors.danger)),
              ),
            )
          : const Center(child: DelayedSpinner(size: 22));
    }
    final g = d.goal;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(M.gutter + S.s4, S.s8, M.gutter + S.s4, S.s32),
        children: [
          if (g.title.isNotEmpty)
            Text(g.title,
                style: sans(kMobile ? 17 : 15,
                    weight: W.strong, height: 1.3, color: AppColors.fg1)),
          SizedBox(height: S.s6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Tag(g.status == 'open' ? 'Open' : _cap(g.status),
                tone: g.status == 'closed' || g.status == 'open'
                    ? Tone.ok
                    : Tone.neutral),
            if (g.attention != null) AttentionChip(g.attention!),
          ]),
          if (g.outcome.trim().isNotEmpty) ...[
            SizedBox(height: S.s12),
            Text(g.outcome, style: sans(14, height: 1.5, color: AppColors.fg2)),
          ],
          SizedBox(height: S.s12),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _stat('${g.progress.done} of ${g.progress.total}', 'slices done'),
            SizedBox(width: S.s8),
            _stat('${g.evidence.done} of ${g.evidence.total}',
                'criteria evidenced'),
            SizedBox(width: S.s8),
            _stat('${d.blockers.length}', 'Blockers'),
          ])),
          if (d.blockers.isNotEmpty)
            _section(
                'Blockers',
                Column(children: [
                  for (final b in d.blockers) _blocker(b),
                ])),
          if (d.acceptance.isNotEmpty)
            _section(
                'Acceptance criteria',
                Column(children: [
                  for (final (i, c) in d.acceptance.indexed) _criterion(i, c),
                ])),
          if (d.plan.isNotEmpty)
            _section(
                'Plan',
                Column(children: [
                  for (final s in d.plan) _slice(d, s),
                ])),
        ],
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _criterion(int i, GoalCriterion c) {
    final on = _open.contains(i);
    final has = c.hasEvidence;
    final gone = c.isDropped;
    final expandable = c.method.isNotEmpty || gone;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HoverSurface(
        radius: 8,
        onTap: expandable
            ? () => setState(() => on ? _open.remove(i) : _open.add(i))
            : null,
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: S.s4, vertical: kMobile ? S.of(10) : S.of(7)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _tick(has, key: ValueKey('criterion-tick-$i')),
            SizedBox(width: S.of(10)),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.criterion,
                        style: sans(13,
                                height: 1.4,
                                color: gone
                                    ? AppColors.fg4
                                    : has
                                        ? AppColors.fg2
                                        : AppColors.fg1)
                            .copyWith(
                                decoration:
                                    gone ? TextDecoration.lineThrough : null)),
                    if (!gone)
                      Padding(
                        padding: EdgeInsets.only(top: S.s2),
                        child: Text(
                            'Evidence · ${has ? c.evidence! : 'None recorded yet'}',
                            style: sans(12, color: AppColors.fg4)),
                      ),
                  ]),
            ),
            if (expandable) ...[
              SizedBox(width: S.s6),
              AnimatedRotation(
                turns: on ? 0.5 : 0,
                duration: reduceMotion(context) ? Duration.zero : Motion.fast,
                child: AppIcon('chevron-down', size: 13, color: AppColors.fg4),
              ),
            ],
          ]),
        ),
      ),
      Reveal(
        show: on,
        child: Padding(
          padding: EdgeInsets.fromLTRB(S.of(30), 0, S.s4, S.of(10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (c.method.isNotEmpty) _kv('Check', c.method),
            if (gone) _kv('Dropped', c.dropped!),
          ]),
        ),
      ),
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: EdgeInsets.only(top: S.s4),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k  ', style: sans(12, color: AppColors.fg4)),
          TextSpan(
              text: v, style: sans(13, height: 1.45, color: AppColors.fg2)),
        ])),
      );

  /// 'T-241' for the daemon's short task ids, else null so long ids stay out of the row.
  static String? _shortId(String? id) {
    final m = RegExp(r'^t-?(\d+)$', caseSensitive: false).firstMatch(id ?? '');
    return m == null ? null : 'T-${m.group(1)}';
  }

  Widget _slice(GoalDetail d, GoalPlanStep s) {
    final t = d.taskFor(s);
    final status = TaskStatus.parse(t?.status);
    final done = t != null && status == TaskStatus.done;
    final titles = {for (final x in d.tasks) x.id: x.title};
    final deps = [
      for (final n in s.dependsOn)
        for (final p in d.plan.where((p) => p.n == n))
          _shortId(d.taskFor(p)?.id ?? p.taskId) ??
              (p.title.isEmpty ? 'Slice $n' : p.title),
    ];
    final blocked = t != null && status == TaskStatus.blocked;
    final active = t != null && !done && status != TaskStatus.todo;
    final note = blocked
        ? taskNote(
            status: t.status,
            statusReason: t.statusReason,
            waitingOn: t.waitingOn,
            currentStep: null,
            titleOf: (id) => titles[id],
          ).line
        : null;
    final id = t?.id ?? s.taskId;
    final label = _shortId(id);
    final title = s.title.isEmpty ? (t?.title ?? '') : s.title;
    final after = !done && deps.isNotEmpty ? ' \u00b7 After ${deps.join(', ')}' : '';
    return HoverSurface(
      key: ValueKey('slice-${s.n}'),
      radius: 8,
      onTap:
          id == null ? null : () => openTaskDetail(context, widget.client, id),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: S.s4, vertical: kMobile ? S.of(5) : S.of(3)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _tick(done),
          SizedBox(width: S.of(10)),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${label == null ? '' : '$label '}$title$after',
                  key: ValueKey('slice-title-${s.n}'),
                  style: sans(13,
                      height: 1.4, color: done ? AppColors.fg2 : AppColors.fg1)),
              // Work under way says who holds it; a slice not started stays one line.
              if (active)
                Padding(
                  padding: EdgeInsets.only(top: S.s2),
                  child: Text(
                      [status.label, if (t.agent != null) t.agent!]
                          .join('  \u00b7  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ),
              if (note != null && note.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: S.s2),
                  child: Text(note,
                      key: ValueKey('slice-note-${s.n}'),
                      style: sans(12, color: AppColors.danger)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _blocker(GoalBlocker b) {
    final detail = [
      if (b.reason != null) b.reason!,
      if (b.waitingOn.isNotEmpty)
        'Waiting on ${b.waitingOn.length} task${b.waitingOn.length == 1 ? '' : 's'}',
    ].join('. ');
    return HoverSurface(
      radius: 8,
      onTap: b.taskId.isEmpty
          ? null
          : () => openTaskDetail(context, widget.client, b.taskId),
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: S.s4, vertical: kMobile ? S.of(10) : S.of(7)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 7,
            height: 7,
            margin: EdgeInsets.only(top: S.s6, right: S.of(10), left: S.s4),
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: AppColors.danger),
          ),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.title,
                  style: sans(13, height: 1.4, color: AppColors.fg1)),
              if (detail.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: S.s2),
                  child: Text(detail, style: sans(12, color: AppColors.fg3)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
