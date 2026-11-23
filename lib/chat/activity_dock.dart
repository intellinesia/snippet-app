// Phone tool calls: a live capsule above the composer while a run works, and
// one pill in the transcript once it is done. Both open the activity sheet.

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tool_activity.dart';
import '../tool_sheet.dart' show ToolBatch;
import '../widgets.dart';
import '../tap_detector.dart';
import '../transcript.dart' show RunSpinner;

/// A run in flight: its steps so far and when it began.
class DockRun {
  const DockRun(this.batch, this.startedAt);
  final ToolBatch batch;
  final DateTime startedAt;
}

/// Whether a finished step failed, by exit status or by what its output says.
bool stepFailedOut(ToolStep s) =>
    !s.running && (s.failed || verifyOutputFailed(s));

/// Quiet rule: failures count only when the run ends on one; a failure a
/// later step got past is already behind us.
int runFailures(Iterable<ToolStep> steps) {
  final done = steps.where((s) => !s.running).toList();
  if (done.isNotEmpty && !stepFailedOut(done.last)) return 0;
  return steps.where(stepFailedOut).length;
}

/// Index of the first failed step, so a tap on "1 failed" lands on it.
int? firstFailure(List<ToolStep> steps) {
  final i = steps.indexWhere(stepFailedOut);
  return i < 0 ? null : i;
}

class RunRing extends StatelessWidget {
  const RunRing({
    super.key,
    required this.fraction,
    required this.color,
    this.size = 44,
    this.stroke = 4,
    this.child,
  });

  final double fraction;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
              fraction.clamp(0.0, 1.0), color, AppColors.border2, stroke),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction, this.color, this.track, this.stroke);
  final double fraction;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 6.2832, false, p..color = track);
    if (fraction > 0) {
      canvas.drawArc(rect, -1.5708, 6.2832 * fraction, false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}

class FailedPill extends StatelessWidget {
  const FailedPill(this.count, {super.key, this.onTap, this.compact = false});
  final int count;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 44pt transparent hit area around the 24/28pt visual.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              constraints: BoxConstraints(minHeight: compact ? 24 : 28),
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
              decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(compact ? 12 : 14)),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('alert-triangle', size: 14, color: AppColors.fg1),
                  const SizedBox(width: 6),
                  Text('$count failed',
                      style: sans(compact ? 13 : 14,
                          weight: W.label, color: AppColors.fg1)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// The live capsule: the agent's mascot hopping, the current step, its clock.
class ActivityDock extends StatefulWidget {
  const ActivityDock({
    super.key,
    required this.run,
    required this.onOpen,
    required this.agentId,
  });

  final DockRun run;
  final String agentId;

  /// Opens the sheet; [index] lands on that step, null on the list.
  final void Function(int? index) onOpen;

  @override
  State<ActivityDock> createState() => _ActivityDockState();
}

class _ActivityDockState extends State<ActivityDock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final steps = widget.run.batch.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final live = steps.where((s) => s.running).toList();
    final failed = runFailures(steps);
    final elapsed = DateTime.now().difference(widget.run.startedAt);
    final clock = formatWorkDuration(
        Duration(seconds: elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds));
    final title = live.isNotEmpty ? liveStepText(live.last) : 'Working';
    return Padding(
      padding: EdgeInsets.only(bottom: S.s8),
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(null),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
          child: Row(children: [
            SizedBox(
                width: 16,
                height: 16,
                child: RunSpinner(size: 14, color: AppColors.fg2)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15, color: AppColors.fg1)),
            ),
            const SizedBox(width: 10),
            Text(clock, style: sans(14, color: AppColors.fg2, tabular: true)),
            if (failed > 0) ...[
              const SizedBox(width: 8),
              FailedPill(failed,
                  compact: true,
                  onTap: () => widget.onOpen(firstFailure(steps))),
            ],
            const SizedBox(width: 6),
            AppIcon('chevron-up', size: 16, color: AppColors.fg3),
          ]),
        ),
      ),
    );
  }
}

/// What a finished run leaves in the transcript.
class ActivityPill extends StatelessWidget {
  const ActivityPill({
    super.key,
    required this.steps,
    required this.onOpen,
    required this.agentId,
    this.took,
  });

  final String agentId;
  final List<ToolStep> steps;
  final Duration? took;
  final void Function(int? index) onOpen;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final t = took ?? stepsDuration(steps);
    var failed = runFailures(steps);
    if (failed == 0 && steps.any((x) => !x.running && x.failed)) failed = 1;
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpen(null),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: Row(children: [
          AppIcon(failed > 0 ? 'alert-triangle' : 'terminal',
              size: 16, color: failed > 0 ? AppColors.fg1 : AppColors.fg2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(describeWork(steps).text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(15, color: AppColors.fg2)),
          ),
          if (t != null) ...[
            const SizedBox(width: 10),
            Text(formatWorkDuration(t),
                style: sans(14, color: AppColors.fg2, tabular: true)),
          ],
          if (failed > 0) ...[
            const SizedBox(width: 10),
            FailedPill(failed,
                compact: true, onTap: () => onOpen(firstFailure(steps))),
          ],
          const SizedBox(width: 6),
          AppIcon('chevron-right', size: 16, color: AppColors.fg3),
        ]),
      ),
    );
  }
}
