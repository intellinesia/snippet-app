import 'package:flutter/material.dart';

import 'platform.dart';
import 'motion.dart';
import 'theme.dart';
import 'transcript.dart';
import 'widgets.dart';
import 'tap_detector.dart';

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
    // Phone spec CH-13: title, count, 4 high track, then every step at 44.
    final track = total == 0 ? 0.0 : done / total;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          color: AppColors.surface1, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
                child: Text('Plan',
                    style: sans(13, weight: W.label, color: AppColors.fg1))),
            Text('$done of $total steps',
                style: sans(12, color: AppColors.fg3)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: LayoutBuilder(
                builder: (_, c) => Stack(children: [
                  Container(color: AppColors.surface3),
                  Container(width: c.maxWidth * track, color: AppColors.fg2),
                ]),
              ),
            ),
          ),
          if (widget.explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(widget.explanation, style: _meta()),
            ),
          const SizedBox(height: 4),
          for (var i = 0; i < total; i++)
            Semantics(
              label:
                  '${st[i] == _St.done ? 'Done' : st[i] == _St.now ? 'In progress' : 'To do'}: ${_text(steps[i])}',
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  const SizedBox(width: 5),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: switch (st[i]) {
                      _St.done =>
                        AppIcon('check', size: 16, color: AppColors.fg2),
                      _St.now => Container(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: AppColors.fg1, width: 2))),
                      _St.open => Container(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.fg3, width: 1.5))),
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_text(steps[i]),
                          style: sans(13.5,
                              height: 1.35,
                              color: st[i] == _St.done
                                  ? AppColors.fg3
                                  : AppColors.fg1)),
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

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
            TapDetector(
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
TextStyle _meta() => kMobile
    ? sans(14, height: 20 / 14, color: AppColors.fg2)
    : sans(12, height: 16 / 12, color: AppColors.fg3);
