import 'package:flutter/material.dart';

import '../../widgets.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../tap_detector.dart';

/// Statuses that wait on the user (spec TK-01 "Needs you").
const taskNeedsYou = {
  TaskStatus.inReview,
  TaskStatus.blocked,
  TaskStatus.failed,
};

bool taskWaitsOnUser(TaskStatus s) => taskNeedsYou.contains(s);

/// The daemon stores priority as an integer: 2 and above High, 1 Med, else Low.
String priorityWord(int p) => p >= 2 ? 'High' : (p == 1 ? 'Med' : 'Low');

/// "Review", "Blocked", "Failed" lead the sub line of a needs-you row.
String? needsYouWord(TaskStatus s) => switch (s) {
      TaskStatus.inReview => 'Review',
      TaskStatus.blocked => 'Blocked',
      TaskStatus.failed => 'Failed',
      _ => null,
    };

/// "4m", "3h", "2d".
String shortAgo(String iso, {DateTime? now}) {
  final at = DateTime.tryParse(iso);
  if (at == null) return '';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// The owner is the task's session agent. Nothing is invented: Lead only when
/// Lead created it, otherwise no owner.
({String? id, String name})? taskOwnerAgent(TaskItem t,
    Map<String, SessionInfo> sessions, Map<String, String> agentNames) {
  final s = sessions[t.sessionId];
  for (final id in [s?.agentId, s?.workerAgentId, s?.ownerAgentId]) {
    if (id == null || id.isEmpty) continue;
    final n = agentNames[id];
    if (n != null && n.trim().isNotEmpty) return (id: id, name: n.trim());
  }
  if (t.createdById.toLowerCase() == 'lead') return (id: 'lead', name: 'Lead');
  return null;
}

String? taskOwner(TaskItem t, Map<String, SessionInfo> sessions,
        Map<String, String> agentNames) =>
    taskOwnerAgent(t, sessions, agentNames)?.name;

/// The state word shown on the detail tag and the board.
String taskStateWord(TaskStatus s) => switch (s) {
      TaskStatus.inProgress => 'Doing',
      TaskStatus.todo => 'Todo',
      TaskStatus.inReview => 'Review',
      TaskStatus.blocked => 'Blocked',
      TaskStatus.failed => 'Failed',
      TaskStatus.done => 'Done',
      TaskStatus.cancelled => 'Cancelled',
    };

/// Round 28 (or [size]) initial on surface2.
class OwnerAvatar extends StatelessWidget {
  const OwnerAvatar(this.name, {super.key, this.size = 28});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
        child: Text(t.isEmpty ? '?' : t.characters.first.toUpperCase(),
            style: sans(size * 0.43,
                weight: W.label, height: 1, color: AppColors.fg2)),
      ),
    );
  }
}

/// The state glyph: ring with a gap for Doing (turning unless motion is
/// reduced), empty circle, amber hand, check, x. Amber only on the hand.
class TaskGlyph extends StatelessWidget {
  const TaskGlyph(this.status, {super.key, this.size = 20});
  final TaskStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget g = switch (status) {
      TaskStatus.inReview || TaskStatus.blocked => Center(
          child: Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
          ),
        ),
      TaskStatus.failed || TaskStatus.cancelled =>
        AppIcon('x', size: size, color: AppColors.fg3),
      TaskStatus.inProgress => _Ring(size: size),
      TaskStatus.done => AppIcon('check', size: size, color: AppColors.fg3),
      TaskStatus.todo => AppIcon('circle', size: size, color: AppColors.fg3),
    };
    return ExcludeSemantics(
        child: SizedBox(width: size, height: size, child: g));
  }
}

class _Ring extends StatefulWidget {
  const _Ring({required this.size});
  final double size;
  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _c,
        child: CustomPaint(
            size: Size.square(widget.size),
            painter: _RingPainter(AppColors.fg2)),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round;
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width / 2 - 2);
    canvas.drawArc(r, 0.6, 5.2, false, p);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.color != color;
}

/// A 48 x 48 trailing bar icon, 20 in fg2.
class BarIcon extends StatelessWidget {
  const BarIcon(this.icon, this.label, this.onTap, {super.key, this.toggled});
  final bool? toggled;
  final String icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        toggled: toggled,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
              width: 48,
              height: 48,
              child:
                  Center(child: AppIcon(icon, size: 20, color: AppColors.fg2))),
        ),
      );
}
