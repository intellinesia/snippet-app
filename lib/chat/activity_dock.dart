// Phone tool calls: a live capsule above the composer while a run works, and
// one pill in the transcript once it is done. Both open the activity sheet.

import 'dart:async';

import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../tool_sheet.dart' show ToolBatch;
import '../transcript.dart' show PhoneFoldLine, QuietStepLine;
import '../mobile_kit.dart' show MkMorph;
import '../widgets.dart';
import '../tap_detector.dart';

/// A run in flight: its steps so far and when it began.
class DockRun {
  const DockRun(this.batch, this.startedAt);
  final ToolBatch batch;
  final DateTime startedAt;
}

/// Whether a finished step failed, by exit status or by what its output says.
bool stepFailedOut(ToolStep s) =>
    !s.running && (s.failed || verifyOutputFailed(s));

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
    final elapsed = DateTime.now().difference(widget.run.startedAt);
    final clock = formatWorkDuration(
        Duration(seconds: elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds));
    final step = live.isNotEmpty ? liveStepText(live.last) : '';
    if (!kMobile) {
      // XO-01: a floating 28pt s2 pill. Failed steps along the way are routine
      // and never change its state.
      final agent = widget.agentId.isEmpty ? 'Agent' : widget.agentId;
      final label = '$agent running $clock';
      return Semantics(
        button: true,
        label: 'Running, $step',
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpen(null),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 14,
                height: 14,
                child: Center(child: Spinner(size: 12, color: AppColors.fg2)),
              ),
              const SizedBox(width: 7),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, color: AppColors.fg2, tabular: true)),
            ]),
          ),
        ),
      );
    }
    // Board: a quiet centred meta line, "Working · 12s", with the morph.
    return Semantics(
      button: true,
      label: 'Working, $clock${step.isEmpty ? '' : ', $step'}',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(null),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Working · $clock',
                  style: sans(12, color: AppColors.fg4, tabular: true)),
              const SizedBox(width: 6),
              const MkMorph(size: 13),
            ]),
          ),
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
    if (!kMobile) {
      return TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpen(null),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('check', size: 13, color: AppColors.fg3),
            const SizedBox(width: 7),
            Flexible(
              child: Text(describeWork(steps).text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, color: AppColors.fg2)),
            ),
            if (t != null) ...[
              const SizedBox(width: 8),
              Text(formatWorkDuration(t),
                  style: mono(11, color: AppColors.fg3)),
            ],
          ]),
        ),
      );
    }
    return _PhoneActivity(steps: steps, took: t, onOpen: onOpen);
  }
}

/// Phone: two or more steps fold into one summary line that opens into the
/// quiet step lines; a tap on a step opens its detail.
class _PhoneActivity extends StatefulWidget {
  const _PhoneActivity({required this.steps, required this.onOpen, this.took});
  final List<ToolStep> steps;
  final Duration? took;
  final void Function(int? index) onOpen;

  @override
  State<_PhoneActivity> createState() => _PhoneActivityState();
}

class _PhoneActivityState extends State<_PhoneActivity> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    final lines = Padding(
      padding: EdgeInsets.fromLTRB(2, steps.length > 1 ? 0 : 2, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < steps.length; i++)
            Semantics(
              button: true,
              label: describeWork([steps[i]]).text,
              excludeSemantics: true,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onOpen(i),
                child: Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 7),
                  child: QuietStepLine(steps[i]),
                ),
              ),
            ),
        ],
      ),
    );
    if (steps.length < 2) return lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneFoldLine(
            steps: steps,
            running: false,
            open: _open,
            took: widget.took,
            onTap: () => setState(() => _open = !_open)),
        SpringExpand(open: _open, child: lines),
      ],
    );
  }
}
