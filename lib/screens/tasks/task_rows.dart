import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../mochi.dart';
import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import 'task_common.dart';

/// Hairline for the tasks screens: one quiet 1px line, never a heavy outline.
Color get taskHairline => AppColors.fg1.withValues(alpha: 0.07);

/// Status as a 14pt mark: dashed ring (to do), half fill (in progress), ring
/// with a dot (review), dash (blocked), check (done), cross (failed).
class TaskStatusIcon extends StatelessWidget {
  const TaskStatusIcon(this.status, {super.key, this.size = 14});
  final TaskStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
            painter: _StatusPainter(status, statusMarkColor(status))),
      );
}

Color statusMarkColor(TaskStatus s) => !kMobile
    // Desktop reserves amber for the blocked/needs-you dot alone; every other
    // mark is neutral and the adjacent word carries the state.
    ? (s == TaskStatus.blocked ? AppColors.run : statusColor(s))
    : switch (s) {
        TaskStatus.todo => AppColors.fg4,
        TaskStatus.inProgress => const Color(0xFFE5B13A),
        TaskStatus.inReview => AppColors.accent,
        TaskStatus.blocked => AppColors.danger,
        TaskStatus.done => AppColors.ok,
        TaskStatus.failed => AppColors.danger,
        TaskStatus.cancelled => AppColors.fg4,
      };

class _StatusPainter extends CustomPainter {
  _StatusPainter(this.status, this.color);
  final TaskStatus status;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final fill = Paint()..color = color;
    switch (status) {
      case TaskStatus.todo:
        const n = 8;
        for (var i = 0; i < n; i++) {
          final a = 2 * math.pi * i / n;
          canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, math.pi / n,
              false, stroke);
        }
      case TaskStatus.inProgress:
        canvas.drawCircle(c, r, stroke);
        canvas.drawArc(Rect.fromCircle(center: c, radius: r - 2.5),
            -math.pi / 2, math.pi, true, fill);
      case TaskStatus.inReview:
        canvas.drawCircle(c, r, stroke);
        canvas.drawCircle(c, 2, fill);
      case TaskStatus.blocked:
        if (!kMobile) {
          canvas.drawCircle(c, 3, fill);
        } else {
          canvas.drawCircle(c, r, stroke);
          canvas.drawLine(
              c - const Offset(3, 0), c + const Offset(3, 0), stroke);
        }
      case TaskStatus.done:
        canvas.drawCircle(c, r + 0.5, fill);
        final tick = Paint()
          ..color = AppColors.bg
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        final p = Path()
          ..moveTo(c.dx - 3, c.dy)
          ..lineTo(c.dx - 0.8, c.dy + 2.3)
          ..lineTo(c.dx + 3, c.dy - 2.2);
        canvas.drawPath(p, tick);
      case TaskStatus.failed:
      case TaskStatus.cancelled:
        canvas.drawCircle(c, r, stroke);
        canvas.drawLine(
            c - const Offset(2.5, 2.5), c + const Offset(2.5, 2.5), stroke);
        canvas.drawLine(
            c - const Offset(2.5, -2.5), c + const Offset(2.5, -2.5), stroke);
    }
  }

  @override
  bool shouldRepaint(_StatusPainter old) =>
      old.status != status || old.color != color;
}

/// Left inset of a row's content from the list edge: 6 margin plus 8 padding.
const double kTaskRowInset = 14;

/// Id column width, shared so the fold text can align to the title.
const double kTaskIdWidth = 62;

/// A status group's heading: mark, label, count.
class TaskGroupHeader extends StatelessWidget {
  const TaskGroupHeader(this.status, this.count,
      {super.key, this.first = false});
  final TaskStatus status;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        // Same 22pt mark column and left edge as DenseTaskRow, so the heading
        // mark and the row marks share one centre line.
        padding: EdgeInsets.fromLTRB(kTaskRowInset, first ? 8 : 18, 14, 6),
        child: Row(children: [
          SizedBox(width: 22, child: Center(child: TaskStatusIcon(status))),
          const SizedBox(width: 4),
          Text(status.label,
              style: sans(12.5, weight: W.label, color: AppColors.fg2)),
          const SizedBox(width: 8),
          Text('$count', style: sans(12, color: AppColors.fg4)),
        ]),
      );
}

/// The dense desktop row: status, id, title, assignee, workspace and age on
/// one 32pt line. Selection and hover are fills, not outlines.
class DenseTaskRow extends StatefulWidget {
  const DenseTaskRow({
    super.key,
    required this.task,
    required this.onTap,
    this.selected = false,
    this.checked = false,
    this.workspace,
    this.onStatus,
  });
  final TaskItem task;
  final bool selected;
  final bool checked;
  final String? workspace;
  final VoidCallback onTap;

  /// Opens the quick status menu from the status mark.
  final void Function(BuildContext anchor)? onStatus;

  @override
  State<DenseTaskRow> createState() => _DenseTaskRowState();
}

class _DenseTaskRowState extends State<DenseTaskRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final finished =
        const {TaskStatus.done, TaskStatus.cancelled}.contains(t.status);
    final num = RegExp(r'^t-?(\d+)$', caseSensitive: false).firstMatch(t.id);
    final id = num != null
        ? 'T-${num.group(1)}'
        : (t.id.length > 8 ? t.id.substring(0, 8) : t.id).toUpperCase();
    final agent = t.createdByKind == 'agent' ? t.createdById : '';
    final age = taskAge(t);
    final fill = widget.selected || widget.checked
        ? AppColors.fg1.withValues(alpha: 0.08)
        : _hover
            ? AppColors.fg1.withValues(alpha: 0.04)
            : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
              color: fill, borderRadius: BorderRadius.circular(R.md)),
          child: Row(children: [
            Builder(
              builder: (anchor) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onStatus == null
                    ? widget.onTap
                    : () => widget.onStatus!(anchor),
                child: SizedBox(
                    width: 22,
                    height: 32,
                    child: Center(child: TaskStatusIcon(t.status))),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
                width: kTaskIdWidth,
                child: Text(id,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: mono(11.5, color: AppColors.fg4))),
            Expanded(
              child: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      weight: widget.selected ? W.label : W.body,
                      color: finished ? AppColors.fg3 : AppColors.fg1)),
            ),
            if (agent.isNotEmpty) ...[
              const SizedBox(width: 10),
              AgentMochi(agent, size: rowAvatarSize(32)),
            ],
            if ((widget.workspace ?? '').isNotEmpty) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(widget.workspace!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg4)),
              ),
            ],
            const SizedBox(width: 10),
            SizedBox(
                width: 28,
                child: Text(age,
                    textAlign: TextAlign.right,
                    style: sans(12, color: AppColors.fg4))),
          ]),
        ),
      ),
    );
  }
}
