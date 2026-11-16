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
        padding: EdgeInsets.only(top: S.s24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel(label),
          SizedBox(height: S.s8),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final title = d?.goal.title.isNotEmpty == true ? d!.goal.title : 'Goal';
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (kMobile)
            MobileBackBar(
                title: title,
                onBack: widget.onClose ?? () => Navigator.of(context).pop(),
                onTitleTap: () {})
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
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.label, color: AppColors.fg1)),
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
          Wrap(spacing: 8, runSpacing: 6, children: [
            Tag(g.status == 'open' ? 'Open' : _cap(g.status),
                tone: g.status == 'closed' ? Tone.ok : Tone.neutral),
            if (g.attention != null) AttentionChip(g.attention!),
          ]),
          if (g.outcome.trim().isNotEmpty) ...[
            SizedBox(height: S.s12),
            Text(g.outcome, style: sans(14, height: 1.5, color: AppColors.fg2)),
          ],
          SizedBox(height: S.s16),
          _metric('Slices', g.progress, 'slices done'),
          SizedBox(height: S.s12),
          _metric('Evidence', g.evidence, 'criteria evidenced',
              colour: AppColors.ok),
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

  Widget _metric(String label, GoalProgress p, String unit, {Color? colour}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: sans(13, color: AppColors.fg3)),
          const Spacer(),
          Text('${p.done} of ${p.total} $unit',
              style: sans(13, color: AppColors.fg2, tabular: true)),
        ]),
        SizedBox(height: S.s6),
        GoalProgressBar(p, colour: colour),
      ]);

  Widget _criterion(int i, GoalCriterion c) {
    final on = _open.contains(i);
    final has = c.hasEvidence;
    final gone = c.isDropped;
    final expandable = c.method.isNotEmpty || has || gone;
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
            Container(
              key: ValueKey('criterion-tick-$i'),
              width: 18,
              height: 18,
              margin: EdgeInsets.only(top: S.of(1)),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: has ? AppColors.okBg : Colors.transparent,
                border:
                    Border.all(color: has ? AppColors.ok : AppColors.border2),
              ),
              child: has
                  ? Center(
                      child: AppIcon('check', size: 11, color: AppColors.ok))
                  : null,
            ),
            SizedBox(width: S.of(10)),
            Expanded(
              child: Text(c.criterion,
                  style: sans(13,
                          height: 1.4,
                          color: gone
                              ? AppColors.fg4
                              : has
                                  ? AppColors.fg1
                                  : AppColors.fg2)
                      .copyWith(
                          decoration: gone ? TextDecoration.lineThrough : null)),
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
          padding: EdgeInsets.fromLTRB(S.s32, 0, S.s4, S.of(10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (c.method.isNotEmpty) _kv('Check', c.method),
            if (c.evidence != null) _kv('Evidence', c.evidence!),
            if (gone) _kv('Dropped', c.dropped!),
            if (!has && !gone) _kv('Evidence', 'None recorded yet'),
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

  Widget _slice(GoalDetail d, GoalPlanStep s) {
    final t = d.taskFor(s);
    final status = TaskStatus.parse(t?.status);
    final deps = d.dependencyTitles(s);
    final titles = {for (final x in d.tasks) x.id: x.title};
    final note = t == null
        ? null
        : taskNote(
            status: t.status,
            statusReason: t.statusReason,
            waitingOn: t.waitingOn,
            currentStep: null,
            titleOf: (id) => titles[id],
          ).line;
    final waitingLine = note ??
        ((t == null || t.status != 'done') && deps.isNotEmpty
            ? 'After ${deps.join(', ')}'
            : null);
    final meta = [
      t == null ? 'Not started' : status.label,
      if (t?.agent != null) t!.agent!,
    ].join('  ·  ');
    final id = t?.id ?? s.taskId;
    return HoverSurface(
      key: ValueKey('slice-${s.n}'),
      radius: 8,
      onTap:
          id == null ? null : () => openTaskDetail(context, widget.client, id),
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: S.s4, vertical: kMobile ? S.of(10) : S.of(7)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 22,
            child: Text('${s.n}', style: mono(12, color: AppColors.fg4)),
          ),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title.isEmpty ? (t?.title ?? '') : s.title,
                  style: sans(13, height: 1.4, color: AppColors.fg1)),
              SizedBox(height: S.of(3)),
              Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t == null ? AppColors.fg4 : statusColor(status)),
                ),
                SizedBox(width: S.s6),
                Flexible(
                  child: Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ),
              ]),
              if (waitingLine != null)
                Padding(
                  padding: EdgeInsets.only(top: S.s2),
                  child: Text(waitingLine,
                      key: ValueKey('slice-note-${s.n}'),
                      style: sans(12,
                          color: status == TaskStatus.blocked
                              ? AppColors.danger
                              : AppColors.fg4)),
                ),
            ]),
          ),
          AppIcon('chevron-right', size: 13, color: AppColors.fg4),
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
