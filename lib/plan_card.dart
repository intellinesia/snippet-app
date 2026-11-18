import 'package:flutter/material.dart';

import 'platform.dart';
import 'settings_form.dart';
import 'motion.dart';
import 'theme.dart';
import 'transcript.dart';
import 'widgets.dart';

/// The run's plan in the transcript: where it is, a segment per step and
/// what comes next. Tap to see every step. Only the latest update is drawn.
class PlanProgressCard extends StatefulWidget {
  const PlanProgressCard(
      {super.key, required this.steps, this.explanation = ''});

  final List<Map> steps;
  final String explanation;

  @override
  State<PlanProgressCard> createState() => _PlanProgressCardState();
}

enum _St { done, now, open }

_St _status(Map step) => switch (step['status']?.toString()) {
      'done' || 'completed' => _St.done,
      'in_progress' => _St.now,
      _ => _St.open,
    };

String _text(Map step) => step['step']?.toString() ?? '';

class _PlanProgressCardState extends State<PlanProgressCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    final st = [for (final s in steps) _status(s)];
    final done = st.where((s) => s == _St.done).length;
    final total = steps.length;
    final finished = done == total;
    // The live step, or the first one not done when none is marked live.
    var cur = st.indexOf(_St.now);
    if (cur < 0 && !finished) cur = st.indexOf(_St.open);
    final next = cur < 0 ? -1 : st.indexWhere((s) => s == _St.open, cur + 1);
    if (!kMobile) {
      return _desktop(st, cur, next, done, total, finished,
          () => setState(() => _open = !_open));
    }
    final r = Grouped.radiusEnd;
    const ri = Radius.circular(Grouped.radiusInner);
    final head = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Container(
        padding: EdgeInsets.fromLTRB(
            Grouped.padX, kMobile ? 14 : 10, Grouped.padX, kMobile ? 14 : 10),
        decoration: BoxDecoration(
          color: Grouped.row,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(r),
            bottom: _open ? ri : Radius.circular(r),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: finished
                  ? AppIcon('check-circle', size: _dot, color: AppColors.fg3)
                  : PlanStepDot(state: 1, size: _dot),
            ),
            SizedBox(width: Grouped.iconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      finished
                          ? 'Plan done · $total of $total'
                          : 'Plan ${cur + 1} of $total',
                      style: _meta()),
                  if (!finished && cur >= 0)
                    Text(_text(steps[cur]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: kMobile
                            ? sans(16, height: 22 / 16, color: AppColors.fg1)
                            : sans(13, height: 18 / 13, color: AppColors.fg1)),
                  SizedBox(height: S.s8),
                  _Segments(st),
                  if (next >= 0) ...[
                    SizedBox(height: S.s8),
                    Text('Next: ${_text(steps[next])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _meta()),
                  ],
                ],
              ),
            ),
            SizedBox(width: S.s8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AppIcon(_open ? 'chevron-up' : 'chevron-down',
                  size: Grouped.chevron, color: AppColors.fg4),
            ),
          ],
        ),
      ),
    );
    if (!_open) return head;
    final rows = <Widget>[
      if (widget.explanation.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(Grouped.padX, 10, Grouped.padX, 12),
          child: Text(widget.explanation, style: _meta()),
        ),
      for (var i = 0; i < total; i++)
        Container(
          constraints:
              BoxConstraints(minHeight: kMobile ? (i == cur ? 56 : 48) : 32),
          padding: EdgeInsets.symmetric(horizontal: Grouped.padX, vertical: 8),
          child: Row(children: [
            PlanStepDot(
                state: st[i] == _St.done
                    ? 2
                    : i == cur
                        ? 1
                        : 0),
            SizedBox(width: Grouped.iconGap),
            Expanded(
              child: Text(_text(steps[i]),
                  style: sans(kMobile ? 15 : 13,
                      height: kMobile ? 20 / 15 : 18 / 13,
                      color: st[i] == _St.done
                          ? AppColors.fg4
                          : i == cur
                              ? AppColors.fg1
                              : Grouped.label)),
            ),
          ]),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        for (var i = 0; i < rows.length; i++) ...[
          const SizedBox(height: Grouped.gap),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Grouped.row,
              borderRadius: BorderRadius.vertical(
                top: ri,
                bottom: i == rows.length - 1 ? Radius.circular(r) : ri,
              ),
            ),
            child: rows[i],
          ),
        ],
      ],
    );
  }
}

extension on _PlanProgressCardState {
  /// Desktop: a borderless surface card, header, segment bar, one row per step.
  Widget _desktop(List<_St> st, int cur, int next, int done, int total,
      bool finished, VoidCallback toggle) {
    final steps = widget.steps;
    final live = finished ? -1 : cur;
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.of(8)),
      child: ColoredBox(
        color: AppColors.surface2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(children: [
                  AppIcon('list', size: 14, color: AppColors.fg3),
                  const SizedBox(width: 8),
                  Text('Plan',
                      style: sans(13, weight: W.label, color: AppColors.fg1)),
                  const SizedBox(width: 8),
                  Text('$done of $total',
                      style: sans(12, color: AppColors.fg3)),
                  const Spacer(),
                  AppIcon(_open ? 'chevron-up' : 'chevron-down',
                      size: 14, color: AppColors.fg4),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _Segments(st, height: 3, desktop: true),
            ),
            if (_open) ...[
              if (widget.explanation.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(widget.explanation,
                      style: sans(12, height: 1.4, color: AppColors.fg3)),
                ),
              const SizedBox(height: 2),
              for (var i = 0; i < total; i++)
                _deskRow(_text(steps[i]), st[i], i == live),
              const SizedBox(height: 6),
            ] else if (live >= 0) ...[
              _deskRow(_text(steps[live]), st[live], true),
              const SizedBox(height: 6),
            ] else
              const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _deskRow(String text, _St state, bool current) {
    final isDone = state == _St.done;
    final style = sans(13,
            height: 1.35,
            color: isDone
                ? AppColors.fg3
                : current
                    ? AppColors.fg1
                    : AppColors.fg2)
        .copyWith(
            decoration: isDone ? TextDecoration.lineThrough : null,
            decorationColor: AppColors.fg4);
    final label = Text(text, style: style);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(children: [
        SizedBox.square(
          dimension: 16,
          child: Center(
            child: isDone
                ? AppIcon('check', size: 14, color: AppColors.ok)
                : current
                    ? const RunSpinner(size: 12)
                    : Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.fg4, width: 1.5),
                        ),
                      ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: current ? Shimmer(color: AppColors.fg1, child: label) : label,
        ),
      ]),
    );
  }
}

/// One short bar per step: done muted, live accent, the rest a track.
class _Segments extends StatelessWidget {
  const _Segments(this.st, {this.height = 4, this.desktop = false});
  final List<_St> st;
  final double height;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final live =
        st.contains(_St.now) ? st.indexOf(_St.now) : st.indexOf(_St.open);
    return Row(children: [
      for (var i = 0; i < st.length; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: desktop
                  ? (st[i] == _St.done
                      ? AppColors.ok
                      : i == live
                          ? AppColors.run
                          : AppColors.fg1.withValues(alpha: 0.11))
                  : st[i] == _St.done
                      ? AppColors.fg3
                      : i == live
                          ? AppColors.accent
                          : Grouped.pillBorder,
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Step marker: 0 open ring, 1 live ring with a dot, 2 done check.
class PlanStepDot extends StatelessWidget {
  const PlanStepDot({super.key, required this.state, this.size = 20});
  final int state;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (state == 2) {
      return AppIcon('check-circle', size: size, color: AppColors.fg3);
    }
    final ring = state == 1 ? AppColors.accent : AppColors.fg4;
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Container(
          width: size * 0.78,
          height: size * 0.78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 1.5),
          ),
          alignment: Alignment.center,
          child: state == 1
              ? Container(
                  width: size * 0.34,
                  height: size * 0.34,
                  decoration: BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle))
              : null,
        ),
      ),
    );
  }
}

// Desktop cards run denser than the phone's.
double get _dot => kMobile ? 22 : 16;
TextStyle _meta() => kMobile
    ? sans(14, height: 20 / 14, color: AppColors.fg3)
    : sans(12, height: 16 / 12, color: AppColors.fg3);
