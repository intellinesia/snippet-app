// Transcript components: an activity timeline for tool calls (one thin line,
// a node and one sentence per step, a single block for detail), lane cards,
// and styled system rows for watches, goals, and compaction.

import 'dart:async';

import 'package:flutter/material.dart';

import 'ambient_loop.dart';
import 'chat/signal_row.dart';
import 'api.dart' show DaemonClient;
import 'crew_widgets.dart' show AgentProviderMark;
import 'mochi.dart';
import 'models.dart';
import 'platform.dart';
import 'settings_form.dart' show Grouped;
import 'theme.dart';
import 'tool_activity.dart';
import 'tool_views.dart';
import 'widgets.dart';

/// Marks steps drawn as grouped-card segments and carries each one's corners.
class StepScope extends InheritedWidget {
  const StepScope({super.key, this.radius, required super.child});

  final BorderRadius? radius;

  static bool active(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StepScope>() != null;

  static BorderRadius? radiusOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StepScope>()?.radius;

  @override
  bool updateShouldNotify(StepScope old) => old.radius != radius;
}

/// The summary sentence with file names a step brighter and the outcome word
/// in its own colour.
List<InlineSpan> workSpans(WorkSummary w, TextStyle base) {
  final spans = <InlineSpan>[];
  final text = w.text;
  var pos = 0;
  final hits = <(int, String)>[];
  for (final name in w.emphasis.toSet()) {
    if (name.isEmpty) continue;
    var from = 0;
    while (true) {
      final i = text.indexOf(name, from);
      if (i < 0) break;
      hits.add((i, name));
      from = i + name.length;
    }
  }
  hits.sort((x, y) => x.$1.compareTo(y.$1));
  for (final (i, name) in hits) {
    if (i < pos) continue;
    if (i > pos) spans.add(TextSpan(text: text.substring(pos, i)));
    spans.add(TextSpan(text: name, style: base.copyWith(color: AppColors.fg2)));
    pos = i + name.length;
  }
  if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
  final outcome = w.outcome;
  if (outcome != null) {
    spans.add(TextSpan(
        text: ' $outcome',
        style:
            base.copyWith(color: w.failed ? AppColors.danger : AppColors.ok)));
  }
  return spans;
}

/// The small amber ring for work in progress.
class RunSpinner extends StatefulWidget {
  const RunSpinner({super.key, this.size = 12, this.color});

  final double size;
  final Color? color;

  @override
  State<RunSpinner> createState() => RunSpinnerState();
}

class RunSpinnerState extends State<RunSpinner> {
  final _c = AmbientLoop(const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.bind(context);
    if (reduceMotion(context)) {
      _c.stop(at: 0);
    } else {
      _c.start();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: RepaintBoundary(
          child: RotationTransition(
            turns: _c,
            child: SizedBox.square(
              dimension: widget.size,
              child: CustomPaint(
                painter: _SpinnerPainter(
                    widget.color ?? AppColors.run, AppColors.runBg),
              ),
            ),
          ),
        ),
      );
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter(this.head, this.track);
  final Color head;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = track;
    canvas.drawArc(rect, 0, 6.2832, false, paint);
    canvas.drawArc(rect, -1.5708, 1.5708, false, paint..color = head);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.head != head || old.track != track;
}

BorderRadius _segmentRadius({required bool first, required bool last}) {
  // The desktop design wants 8px group ends and 3px between rows.
  final end = Radius.circular(kMobile ? R.of(Grouped.radiusEnd) : R.of(13));
  final inner = Radius.circular(kMobile ? R.of(Grouped.radiusInner) : R.of(5));
  return BorderRadius.only(
    topLeft: first ? end : inner,
    topRight: first ? end : inner,
    bottomLeft: last ? end : inner,
    bottomRight: last ? end : inner,
  );
}

/// The phrase for a failing step: "3 tests failed" for a test run, else its chip.
String? _failureNote(List<ToolStep> steps) {
  for (final s in steps) {
    if (!(s.failed || verifyOutputFailed(s))) continue;
    final text = stepChip(s)?.text ?? 'failed';
    final count = RegExp(r'(\d+) failed').firstMatch(text)?.group(1);
    if (count != null && stepCommand(s)?.kind == CommandKind.test) {
      return '$count ${count == '1' ? 'test' : 'tests'} failed';
    }
    return text;
  }
  return null;
}

/// The header segment of a run of tool calls: what the work did, how many
/// steps and how long, and the first failure. Running, it names the live step.
class WorkLine extends StatelessWidget {
  const WorkLine({
    super.key,
    required this.steps,
    required this.running,
    required this.open,
    required this.onTap,
  });

  final List<ToolStep> steps;
  final bool running;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final live = steps.where((s) => s.running).toList();
    final isRunning = running && live.isNotEmpty;
    final work = describeWork(steps);
    final titleStyle = sans(kMobile ? (Grouped.compact ? 15 : 16) : 14,
        height: kMobile ? 22 / 16 : 20 / 14, color: AppColors.fg2);
    final subStyle = sans(kMobile ? (Grouped.compact ? 13 : 14) : 13,
        height: kMobile ? 20 / 14 : 18 / 13, color: AppColors.fg3);
    final title = isRunning
        ? <InlineSpan>[
            TextSpan(
                text: liveStepText(live.last),
                style: titleStyle.copyWith(color: AppColors.fg1))
          ]
        : [
            for (final sp in workSpans(
                WorkSummary(work.text,
                    emphasis: work.emphasis,
                    outcome: work.failed ? null : work.outcome,
                    failed: work.failed),
                titleStyle))
              // The emphasis colour is fg2; names go to fg1 over an fg2 sentence.
              if (sp is TextSpan && sp.style?.color == AppColors.fg2)
                TextSpan(
                    text: sp.text,
                    style: sp.style!.copyWith(color: AppColors.fg1))
              else
                sp
          ];
    final took = stepsDuration(steps);
    final note = isRunning ? null : _failureNote(steps);
    final sub = <InlineSpan>[
      if (took != null) TextSpan(text: formatWorkDuration(took)),
      if (note != null)
        TextSpan(
            text: took == null ? note : ' · $note',
            style: subStyle.copyWith(color: AppColors.danger)),
    ];
    if (!kMobile) {
      return _desktopWorkLine(
          title: title,
          titleStyle: titleStyle,
          isRunning: isRunning,
          failed: work.failed,
          took: took,
          note: note);
    }
    final glyph = Grouped.icon;
    final Widget lead = isRunning
        ? SizedBox.square(
            dimension: glyph,
            child: RunSpinner(size: glyph, color: AppColors.accent))
        : AppIcon(work.failed ? 'x-circle' : 'check-circle',
            size: glyph, color: work.failed ? AppColors.danger : AppColors.fg3);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: kMobile ? Grouped.rowMin : 56),
        padding: EdgeInsets.symmetric(
            horizontal: Grouped.padX, vertical: Grouped.padY),
        decoration: BoxDecoration(
          color: Grouped.row,
          borderRadius: _segmentRadius(first: true, last: !open),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          heightFactor: 1,
          child: Row(children: [
            lead,
            SizedBox(width: Grouped.iconGap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(TextSpan(children: title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle),
                  if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(TextSpan(children: sub),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subStyle),
                    ),
                ],
              ),
            ),
            SizedBox(width: S.s8),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: Motion.fast,
              curve: Curves.easeOutCubic,
              child: AppIcon('chevron-down',
                  size: Grouped.chevron, color: AppColors.fg4),
            ),
          ]),
        ),
      ),
    );
  }
}

extension on WorkLine {
  Widget _desktopWorkLine({
    required List<InlineSpan> title,
    required TextStyle titleStyle,
    required bool isRunning,
    required bool failed,
    required Duration? took,
    required String? note,
  }) {
    final style = sans(12.5, color: AppColors.fg2);
    final Widget lead = SizedBox(
      width: 16,
      child: Center(
        child: isRunning
            ? RunSpinner(size: 12, color: AppColors.accent)
            : AppIcon(failed ? 'x-circle' : 'check-circle',
                size: 16, color: failed ? AppColors.danger : AppColors.fg4),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Grouped.row,
          borderRadius: _segmentRadius(first: true, last: !open),
        ),
        child: Row(children: [
          lead,
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                for (final sp in title)
                  if (sp is TextSpan && sp.text != null)
                    TextSpan(
                        text: sp.text,
                        style: sp.style?.color == AppColors.fg1 ||
                                sp.style?.color == AppColors.ok ||
                                sp.style?.color == AppColors.danger
                            ? style.copyWith(
                                color: sp.style!.color == AppColors.fg1
                                    ? AppColors.fg2
                                    : sp.style!.color)
                            : style)
                  else
                    sp,
                if (note != null)
                  TextSpan(
                      text: ' · $note',
                      style: style.copyWith(color: AppColors.danger)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 10),
          Text(took == null ? '' : formatWorkDuration(took),
              style: sans(11, color: AppColors.fg4, tabular: true)),
          const SizedBox(width: 6),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: Motion.fast,
            curve: Curves.easeOutCubic,
            child: AppIcon('chevron-down', size: 14, color: AppColors.fg4),
          ),
        ]),
      ),
    );
  }
}

/// The step segments of a grouped card, 2px apart. Under a header the first
/// segment is square at the top; without one the group rounds at both ends.
class WorkSteps extends StatelessWidget {
  const WorkSteps({super.key, required this.rows, this.header = true});
  final List<Widget> rows;
  final bool header;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: header ? Grouped.gap : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : Grouped.gap),
                child: StepScope(
                  radius: _segmentRadius(
                      first: i == 0 && !header, last: i == rows.length - 1),
                  child: rows[i],
                ),
              ),
          ],
        ),
      );
}

class DenseToolRow extends StatefulWidget {
  final String tool;
  final dynamic args;
  final dynamic result; // null while running
  final bool? open;
  final ValueChanged<bool>? onOpenChanged;
  const DenseToolRow(
      {super.key,
      required this.tool,
      this.args,
      this.result,
      this.open,
      this.onOpenChanged});

  bool get pending => result == null;

  @override
  State<DenseToolRow> createState() => _DenseToolRowState();
}

class _DenseToolRowState extends State<DenseToolRow> {
  bool _localOpen = false;
  bool _touched = false;

  ToolStep get _step =>
      ToolStep(tool: widget.tool, args: widget.args, result: widget.result);

  // A failed step starts open until the reader says otherwise.
  bool get _autoOpen => stepChip(_step)?.tone == StepChipTone.danger;

  bool get _open => !_touched && _autoOpen ? true : (widget.open ?? _localOpen);

  void _toggle() {
    final next = !_open;
    _touched = true;
    widget.onOpenChanged?.call(next);
    setState(() => _localOpen = next);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final step = _step;
    final canExpand = toolHasDetail(step);
    final open = _open && canExpand;
    final chip = stepChip(step);
    final danger = chip?.tone == StepChipTone.danger;
    final (verb, object) = toolSentenceParts(step);
    final valueStyle = sans(kMobile ? 14 : 13, color: AppColors.fg3);
    final Widget? value;
    if (chip == null) {
      value = null;
    } else if (chip.added > 0 || chip.removed > 0) {
      value = Text.rich(TextSpan(children: [
        TextSpan(
            text: '+${chip.added}',
            style: valueStyle.copyWith(color: AppColors.ok)),
        TextSpan(
            text: ' −${chip.removed}',
            style: valueStyle.copyWith(color: AppColors.danger)),
      ]));
    } else {
      // On a failing row the failure count is the news; passes crowd it.
      value = Text(danger ? chip.text.split(', ').last : chip.text,
          maxLines: 1,
          style: valueStyle.copyWith(
              color: switch (chip.tone) {
            StepChipTone.ok => AppColors.ok,
            StepChipTone.danger => AppColors.danger,
            StepChipTone.neutral => AppColors.fg3,
          }));
    }
    final radius =
        StepScope.radiusOf(context) ?? _segmentRadius(first: true, last: true);
    if (!kMobile) {
      return _desktop(step, verb, object, value, radius,
          canExpand: canExpand, open: open, danger: danger);
    }
    final icon = kMobile ? (Grouped.compact ? 18.0 : 20.0) : 18.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canExpand ? _toggle : null,
      child: Container(
        constraints: BoxConstraints(
            minHeight: kMobile ? (Grouped.compact ? 46 : 52) : 44),
        padding: EdgeInsets.symmetric(
            horizontal: Grouped.padX, vertical: kMobile ? 8 : 6),
        decoration: BoxDecoration(color: Grouped.row, borderRadius: radius),
        child: Align(
          alignment: Alignment.centerLeft,
          heightFactor: 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                AppIcon(toolIcon(step.tool),
                    size: icon,
                    color: danger ? AppColors.danger : AppColors.fg2),
                SizedBox(width: Grouped.iconGap),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: verb, style: TextStyle(color: AppColors.fg3)),
                      if (object.isNotEmpty)
                        TextSpan(
                            text: ' $object',
                            style: TextStyle(color: AppColors.fg1)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? (Grouped.compact ? 14 : 15) : 13,
                        height: 20 / 15),
                  ),
                ),
                if (value != null) ...[SizedBox(width: S.s12), value],
              ]),
              SpringExpand(
                open: open,
                child: canExpand
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(
                            icon + Grouped.iconGap, S.s6, 0, S.s4),
                        child: _StepDetail(step: step),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _DenseToolRowState {
  /// One soft line: glyph, verb, mono target, counts and time on the right.
  Widget _desktop(ToolStep step, String verb, String object, Widget? value,
      BorderRadius radius,
      {required bool canExpand, required bool open, required bool danger}) {
    final took = stepDuration(step);
    final live = step.running;
    final Widget lead = live
        ? SizedBox(
            width: 16,
            child: Center(child: RunSpinner(size: 12, color: AppColors.accent)))
        : SizedBox(
            width: 16,
            child: AppIcon(toolIcon(step.tool),
                size: 16, color: danger ? AppColors.danger : AppColors.fg4));
    final trailing = <Widget>[
      if (value != null) ...[
        DefaultTextStyle.merge(
            style: mono(11.5, color: AppColors.fg3), child: value),
        SizedBox(width: 10),
      ],
      if (took != null)
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 38),
          child: Text(took,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: sans(11, color: AppColors.fg4, tabular: true)),
        ),
      if (canExpand) ...[
        SizedBox(width: 6),
        AppIcon(open ? 'chevron-up' : 'chevron-down',
            size: 14, color: AppColors.fg4),
      ],
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canExpand ? _toggle : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Grouped.row, borderRadius: radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34),
              child: Row(children: [
                lead,
                const SizedBox(width: 10),
                Text(verb,
                    maxLines: 1,
                    style: sans(12.5,
                        color: live ? AppColors.fg1 : AppColors.fg2)),
                if (object.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(object,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(12, color: AppColors.fg3)),
                  ),
                ] else
                  const Spacer(),
                if (trailing.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  ...trailing
                ],
              ]),
            ),
            SpringExpand(
              open: open,
              child: canExpand
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(26, 0, 0, 12),
                      child: _StepDetail(step: step),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDetail extends StatefulWidget {
  const _StepDetail({required this.step});
  final ToolStep step;

  @override
  State<_StepDetail> createState() => _StepDetailState();
}

class _StepDetailState extends State<_StepDetail> {
  static const _cap = 240.0;
  final _key = GlobalKey();
  bool _full = false;
  double _height = 0;

  double get _lineHeight => kMobile ? 12.5 * 1.45 : 12 * 1.65;

  void _measure() {
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    if ((box.size.height - _height).abs() > 0.5) {
      setState(() => _height = box.size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    final overflow = _height > _cap + 1;
    final tool = toolBaseName(step.tool);
    final countsLines =
        tool == 'bash' || tool == 'read_file' || tool == 'change_files';
    final lines = (_height / _lineHeight).round();
    final more = countsLines ? 'Show all $lines lines' : 'Show all';
    final meta = toolMetaParts(step);
    final metaStyle = sans(kMobile ? 12 : 12, color: AppColors.fg3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No inner box: the step's own row is the surface.
        Padding(
          padding: EdgeInsets.only(top: S.s2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRect(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: _full ? double.infinity : _cap),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: KeyedSubtree(
                      key: _key,
                      child: safeToolDetailView(context,
                          tool: step.tool,
                          args: step.args,
                          result: step.result),
                    ),
                  ),
                ),
              ),
              if (overflow)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _full = !_full),
                  child: Padding(
                    padding: EdgeInsets.only(top: kMobile ? S.s8 : S.s6),
                    child: Text(_full ? 'Show less' : more,
                        style: sans(kMobile ? 13 : 12,
                            weight: W.label, color: AppColors.fg3)),
                  ),
                ),
            ],
          ),
        ),
        if (meta.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: S.s6),
            child: Text(meta.join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
          ),
      ],
    );
  }
}

/// A run of tool steps. Up to [_directLimit] steps show directly; a longer run
/// shows one work line that opens into the step list.
class ToolRun extends StatefulWidget {
  final List<Widget> rows;
  final bool running;
  final bool open;
  final ValueChanged<bool>? onOpenChanged;
  const ToolRun(this.rows,
      {super.key, this.running = false, this.open = false, this.onOpenChanged});
  @override
  State<ToolRun> createState() => _ToolRunState();
}

class _ToolRunState extends State<ToolRun> {
  static const _directLimit = 3;
  bool _localOpen = false;

  bool get _open => widget.onOpenChanged != null ? widget.open : _localOpen;

  void _toggle() {
    if (widget.onOpenChanged != null) {
      widget.onOpenChanged!(!widget.open);
    } else {
      setState(() => _localOpen = !_localOpen);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final rows = widget.rows;
    final steps = [
      for (final r in rows.whereType<DenseToolRow>())
        ToolStep(tool: r.tool, args: r.args, result: r.result),
    ];
    final long = rows.length > _directLimit;
    final open = _open;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (long)
          WorkLine(
              steps: steps,
              running: widget.running,
              open: open,
              onTap: _toggle),
        if (!long)
          WorkSteps(rows: rows, header: false)
        else
          SpringExpand(open: open, child: WorkSteps(rows: rows)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Lane notice — the transcript keeps only a compact pointer. Full lane output
// belongs in the dedicated lanes screen.
// ---------------------------------------------------------------------------

/// Who runs a lane and on what: provider logo for the effective profile, then
/// the agent identity. Draws nothing when neither resolves.
class LaneWho extends StatelessWidget {
  final DaemonClient? client;
  final String? agent;
  final String? profile;
  final double size;
  final double textSize;
  final double maxTextWidth;
  final Color color;

  const LaneWho({
    super.key,
    this.client,
    this.agent,
    this.profile,
    this.size = 12,
    this.textSize = 11,
    this.maxTextWidth = 72,
    this.color = const Color(0x00000000),
  });

  @override
  Widget build(BuildContext context) {
    final name = agent?.trim() ?? '';
    final model = profile?.trim() ?? '';
    final c = client;
    if (name.isEmpty && c == null) return const SizedBox.shrink();
    final ink = color.a == 0 ? AppColors.fg3 : color;
    return Tooltip(
      message: [name, model.isEmpty ? 'default model' : model]
          .where((e) => e.isNotEmpty)
          .join(' · '),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (c != null)
          AgentProviderMark(
              client: c, profile: model, size: size, orActive: true),
        if (name.isNotEmpty) ...[
          SizedBox(width: S.s4),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTextWidth),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(textSize, color: ink)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Stop (for running lanes) or Retry (for failed/cancelled lanes).
class LaneControlButton extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;
  final LaneInfo lane;

  /// Text-only action, for the footer of the in-chat lane card.
  final bool quiet;

  const LaneControlButton({
    super.key,
    required this.client,
    required this.sessionId,
    required this.lane,
    this.quiet = false,
  });

  @override
  State<LaneControlButton> createState() => _LaneControlButtonState();
}

class _LaneControlButtonState extends State<LaneControlButton> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    final lane = widget.lane;
    if (lane.running) {
      final ok = await confirmAction(
        context,
        title: 'Stop this lane?',
        body: lane.title.trim().isEmpty ? 'Stop this lane?' : lane.title.trim(),
        confirmLabel: 'Stop',
        danger: true,
      );
      if (!ok || !mounted) return;
      setState(() => _busy = true);
      try {
        await widget.client.cancelLane(widget.sessionId, lane.id);
      } catch (e) {
        if (mounted) toast(context, '$e', danger: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    if (lane.retryable) {
      setState(() => _busy = true);
      try {
        await widget.client.retryLane(widget.sessionId, lane.id);
      } catch (e) {
        if (mounted) toast(context, '$e', danger: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.lane.running;
    final retryable = widget.lane.retryable;
    if (!running && !retryable) return const SizedBox.shrink();
    final label = running ? 'Stop' : 'Retry';
    if (widget.quiet) {
      return Opacity(
        opacity: _busy ? 0.5 : 1.0,
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: _busy ? null : _onTap,
          child: Container(
            height: kMobile ? 44.0 : 26.0,
            padding: EdgeInsets.symmetric(horizontal: S.s8),
            alignment: Alignment.center,
            child: Text(label,
                style: sans(12,
                    weight: W.label,
                    color: running ? AppColors.danger : AppColors.fg2)),
          ),
        ),
      );
    }
    final fg = running ? AppColors.danger : AppColors.fg1;
    final bg = running ? AppColors.dangerBg : AppColors.surface2;
    final border =
        running ? AppColors.danger.withValues(alpha: 0.3) : AppColors.border;
    final height = kMobile ? 44.0 : 28.0;
    final radius = BorderRadius.circular(kMobile ? R.pill : R.sm);
    return Opacity(
      opacity: _busy ? 0.5 : 1.0,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
            borderRadius: radius, side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: _busy ? null : _onTap,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s16 : S.s12),
            alignment: Alignment.center,
            child: Text(
              label,
              style: sans(kMobile ? 13 : 12, weight: W.label, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// "3 min", "42 s", "1 h 5 min".
String laneElapsed(LaneInfo? lane, {DateTime? now}) {
  final started = DateTime.tryParse(lane?.startedAt ?? '');
  if (started == null) return '';
  final d = (now ?? DateTime.now()).toUtc().difference(started.toUtc());
  if (d.inMinutes < 1) return '${d.inSeconds < 0 ? 0 : d.inSeconds} s';
  if (d.inHours < 1) return '${d.inMinutes} min';
  return '${d.inHours} h ${d.inMinutes % 60} min';
}

/// The first sentence of a lane summary, plain text.
String laneFirstSentence(String summary, [int max = 90]) {
  final plain = summary
      .replaceAll(RegExp(r'[#*`>_]+'), '')
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  final m = RegExp(r'^(.+?[.!?])(\s|$)').firstMatch(plain);
  final one = m?.group(1) ?? plain;
  return one.length <= max ? one : '${one.substring(0, max - 1)}\u2026';
}

String laneAgentName(String id) => id
    .split(RegExp(r'[-_]'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

// ---------------------------------------------------------------------------
// Styled system rows: watches, goals, compaction, generic decisions — each
// recognizable at a glance instead of identical grey notes.
// ---------------------------------------------------------------------------

class SystemRow extends StatelessWidget {
  final String step;
  final String reasoning;

  /// When it happened, already formatted (HH:MM), if the event says.
  final String? time;
  const SystemRow(
      {super.key, required this.step, required this.reasoning, this.time});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change

    // Full-width quiet dividers (match TUI compaction / tool-prune chrome).
    if (step == 'history_compacted') {
      return _SystemDivider(label: 'context compacted');
    }
    if (step == 'continued_lean') {
      return SignalRow(
          icon: 'archive',
          text: 'Earlier history archived to keep it lean',
          time: time);
    }
    if (step == 'idle_memory_save') {
      return _SystemDivider(label: 'saved memory while you were away');
    }
    if (step == 'history_compaction_pass' ||
        step == 'history_compaction_skipped') {
      return const SizedBox.shrink();
    }
    if (step == 'tool_payloads_pruned') {
      final detail = reasoning.trim();
      final label = detail.isEmpty
          ? 'old tool results cleared'
          : 'tools cleared · $detail';
      return _SystemDivider(label: label);
    }

    final isGoal = step == 'goal_set' ||
        step == 'goal_completed' ||
        step == 'goal_paused' ||
        step == 'goal_cancelled';
    // A goal fire is a scheduled instruction — render it like any normal
    // user message bubble instead of a special card. End states stay as
    // quiet one-line notes so the canvas isn't cluttered with chrome.
    if (isGoal) {
      if (step == 'goal_set') {
        return Padding(
          padding: EdgeInsets.only(top: S.s4, bottom: S.s20),
          child: Bubble(mine: true, text: reasoning),
        );
      }
      final label = switch (step) {
        'goal_completed' => 'goal completed',
        'goal_paused' => 'goal paused',
        _ => 'goal cancelled',
      };
      // The completion summary (the agent's complete_goal report) is the
      // outcome of the run — show it, not just a bare divider. Other end
      // states stay quiet.
      if (step != 'goal_completed') {
        return _SystemDivider(label: label);
      }
      final detail = reasoning.trim();
      return Padding(
        padding: EdgeInsets.only(top: S.s4, bottom: S.s16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SystemDivider(label: label),
          if (detail.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: S.s8),
              child: MarkdownBody(
                data: detail,
                selectable: true,
                styleSheet: markdownStyle(context),
                builders: {'pre': PreBlockBuilder()},
                onTapLink: (txt, href, title) =>
                    openMarkdownLink(href, context, txt),
              ),
            ),
        ]),
      );
    }

    switch (step) {
      case 'watch_added':
        final m = RegExp(r'^watching "(.*)" \((.*)\)$', dotAll: true)
            .firstMatch(reasoning.trim());
        return SignalRow(
          icon: 'eye',
          tone: SignalTone.accent,
          text: 'Watching **${m?.group(1) ?? reasoning.trim()}**',
          time: time,
        );
      case 'watch_removed':
        final m =
            RegExp(r'^stopped watching "(.*)"$').firstMatch(reasoning.trim());
        return SignalRow(
          icon: 'eye',
          text: 'Stopped watching **${m?.group(1) ?? reasoning.trim()}**',
          time: time,
        );
      case 'file_watch':
        final m = RegExp(r'^"(.*?)" — (.*?) grew: ?(.*)$', dotAll: true)
            .firstMatch(reasoning);
        return _WatchFired(
          subject: m?.group(1) ?? 'Watched file',
          path: m?.group(2) ?? '',
          preview: (m?.group(3) ?? reasoning).trim(),
          time: time,
        );
      case 'interrupted':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: S.s6),
          child: Row(children: [
            SizedBox(
                width: 16,
                child: Center(
                    child: AppIcon('stop', size: 14, color: AppColors.danger))),
            SizedBox(width: S.s8),
            Text('You stopped the run', style: TS.label(AppColors.danger)),
          ]),
        );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 16,
            child: Padding(
              padding: EdgeInsets.only(top: S.s2),
              child: Center(
                  child: AppIcon('activity', size: 14, color: AppColors.fg4)),
            )),
        SizedBox(width: S.s8),
        Expanded(
          child: Text(reasoning,
              maxLines: 3, overflow: TextOverflow.ellipsis, style: TS.meta()),
        ),
      ]),
    );
  }
}

/// What a watched file's new lines say: the readable lines, and a verdict
/// (true finished, false failed, null unknown) from sentinels, exit codes and
/// pass or fail words.
({List<String> lines, bool? ok, int? exit}) readWatchPreview(String preview) {
  final sentinel = RegExp(r'^__[A-Z_]+__(?:\s+exit=(-?\d+))?');
  int? exit;
  var sentinelSeen = false;
  final lines = <String>[];
  for (final raw in preview.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    // A sentinel can trail other output on the same line.
    final t = line.trim();
    final at = t.indexOf(RegExp(r'__[A-Z_]+__'));
    if (at >= 0) {
      final m = sentinel.firstMatch(t.substring(at));
      if (m != null) {
        sentinelSeen = true;
        if (m.group(1) != null) exit = int.tryParse(m.group(1)!);
        final before = t.substring(0, at).trim();
        if (before.isNotEmpty) lines.add(before);
        continue;
      }
    }
    lines.add(line);
  }
  final text = lines.join('\n');
  bool? ok;
  if (exit != null) {
    ok = exit == 0;
  } else if (RegExp(r'\b(?:rc|exit|code)[=:]\s*[1-9]\d*\b').hasMatch(text) ||
      RegExp(r'(?<!\b(?:0|no) )\b(?:failed|failure|fails|error|errors)\b',
              caseSensitive: false)
          .hasMatch(text) ||
      text.contains('✗')) {
    ok = false;
  } else if (sentinelSeen ||
      RegExp(r'\b(?:rc|exit|code)[=:]\s*0\b').hasMatch(text) ||
      RegExp(r'\b(?:passed|done|finished|succeeded)\b', caseSensitive: false)
          .hasMatch(text) ||
      text.contains('✓')) {
    ok = true;
  }
  return (lines: lines, ok: ok, exit: exit);
}

class _WatchFired extends StatefulWidget {
  const _WatchFired(
      {required this.subject,
      required this.path,
      required this.preview,
      this.time});

  final String subject;
  final String path;
  final String preview;
  final String? time;

  @override
  State<_WatchFired> createState() => _WatchFiredState();
}

class _WatchFiredState extends State<_WatchFired> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final read = readWatchPreview(widget.preview);
    final (text, tone, icon) = switch (read.ok) {
      true => ('**${widget.subject}** finished', SignalTone.ok, 'check'),
      false => (
          '**${widget.subject}** failed',
          SignalTone.danger,
          'alert-triangle'
        ),
      null => (
          '**${widget.subject}** has new output',
          SignalTone.neutral,
          'activity'
        ),
    };
    final canExpand = read.lines.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignalRow(
          icon: icon,
          tone: tone,
          text: text,
          time: widget.time,
          onTap: canExpand ? () => setState(() => _open = !_open) : null,
        ),
        if (_open && canExpand)
          Padding(
            padding: EdgeInsets.fromLTRB(S.of(28), S.s2, 0, S.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.path.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: S.s4),
                    child: Text(widget.path, style: TS.meta(AppColors.fg4)),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(read.lines.join('\n'),
                        style: sans(11, height: 1.4, color: AppColors.fg3)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A coordination event in the chat canvas: this agent was messaged, or this
/// agent dispatched work into a session.
///
/// Rendered in the CONVERSATION because the event concerns THIS session's agent
/// — a message arriving for it, or work it handed out. It is deliberately a
/// quiet one-line notice, not a chat bubble: the message itself lives in the
/// agent's direct thread, and pretending otherwise here would suggest you are
/// talking in this chat when you are not.
class AgentEventRow extends StatelessWidget {
  const AgentEventRow({
    super.key,
    required this.icon,
    required this.label,
    required this.detail,
    this.accent = false,
  });

  final String icon;
  final String label;
  final String detail;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final color = accent ? AppColors.accent : AppColors.fg3;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s6, horizontal: S.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: S.of(1)),
            child: AppIcon(icon, size: 13, color: color),
          ),
          SizedBox(width: S.of(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: sans(12, weight: W.label, color: color)),
                if (detail.trim().isNotEmpty) ...[
                  SizedBox(height: S.s2),
                  Text(detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, height: 1.35, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width card for goal events in the chat canvas — a distinct block with
/// an accent rail and a status label, instead of a faint one-liner.
/// Centered hairline + label — used for compaction and tool-prune boundaries.
class _SystemDivider extends StatelessWidget {
  final String label;
  const _SystemDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s12),
      child: Row(children: [
        Expanded(child: Container(height: 1, color: AppColors.line)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: S.s12),
          child: Text(label[0].toUpperCase() + label.substring(1),
              style: TS.meta(), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Expanded(child: Container(height: 1, color: AppColors.line)),
      ]),
    );
  }
}

/// A reply the daemon flagged as not needing the user: the thinking style, dimmed.
class QuietAside extends StatelessWidget {
  const QuietAside({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: 0.55, child: ThinkingMarkdown(data: text));
}

/// A `session_handoff` in the transcript. Done: a boundary where the new
/// owner's character rises in over a "takes over from" line and the note.
/// Queued: a centred signal row until the running turn ends.
class HandoffNotice extends StatelessWidget {
  final Map<String, dynamic> event;
  const HandoffNotice({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final from = '${event['from'] ?? ''}'.trim();
    final to = '${event['to'] ?? ''}'.trim();
    final note = '${event['note'] ?? ''}'.trim();
    final by = '${event['by'] ?? ''}'.trim();
    final pending = event['pending'] == true;
    return AgentNamesBuilder(builder: (context, names) {
      final toName = to.isEmpty ? 'Another agent' : agentDisplayName(to, names);
      if (pending) {
        return SignalRow(
          icon: 'arrow-right',
          center: true,
          text: '**$toName** takes over after this turn',
        );
      }
      final fromName =
          from.isEmpty ? 'the last agent' : agentDisplayName(from, names);
      final time = formatEventTime(event['at'] ?? event['created_at']);
      final byLabel = by.isEmpty
          ? ''
          : (by == 'human' ? 'you' : agentDisplayName(by, names));
      final who =
          [if (byLabel.isNotEmpty) byLabel, if (time != null) time].join(', ');
      final quote = [
        if (note.isNotEmpty) '"$note"',
        if (who.isNotEmpty) '${note.isEmpty ? '' : '\u00b7 '}$who',
      ].join(' ');
      final line = sans(kMobile ? 14 : 13, height: 1.4, color: AppColors.fg3);
      final rule =
          Expanded(child: Container(height: 1, color: AppColors.border2));
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s12),
        child: Column(children: [
          _Rise(
              child: to.isEmpty
                  ? const SizedBox(height: 44)
                  : AgentMochi(to, size: 44)),
          SizedBox(height: S.s8),
          Row(children: [
            rule,
            Flexible(
              flex: 0,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s12),
                child: Text.rich(
                  TextSpan(
                    style: line,
                    children: signalSpans(
                        '**$toName** takes over from $fromName', line),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            rule,
          ]),
          if (quote.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: S.s4),
              child: Text(quote,
                  textAlign: TextAlign.center,
                  style: line.copyWith(
                      fontStyle: FontStyle.italic, color: AppColors.fg3)),
            ),
        ]),
      );
    });
  }
}

/// Rises in once; stays put under reduced motion.
class _Rise extends StatelessWidget {
  const _Rise({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
        ),
      ),
    );
  }
}
