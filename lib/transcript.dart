// Transcript components: an activity timeline for tool calls (one thin line,
// a node and one sentence per step, a single block for detail), lane cards,
// and styled system rows for watches, goals, and compaction.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ambient_loop.dart';
import 'chat/signal_row.dart';
import 'api.dart' show DaemonClient;
import 'crew_widgets.dart' show AgentProviderMark;
import 'mochi.dart';
import 'models.dart';
import 'platform.dart';
import 'theme.dart';
import 'tool_activity.dart';
import 'tool_views.dart';
import 'widgets.dart';

double get _sentenceSize => kMobile ? 14 : 13;

enum _NodeState { ok, failed, running, neutral }

class _Node extends StatefulWidget {
  const _Node(this.state, {this.icon});
  final _NodeState state;

  /// The tool's own icon, in place of the dot.
  final String? icon;

  @override
  State<_Node> createState() => _NodeState2();
}

class _NodeState2 extends State<_Node> {
  final _c = AmbientLoop(const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.bind(context);
    final animate =
        widget.state == _NodeState.running && !reduceMotion(context);
    if (animate) {
      _c.start();
    } else if (_c.isRunning) {
      _c.stop(at: 0);
    }
  }

  @override
  void didUpdateWidget(_Node old) {
    super.didUpdateWidget(old);
    didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    if (icon != null) {
      final color = switch (widget.state) {
        _NodeState.failed => AppColors.danger,
        _NodeState.running => AppColors.accent,
        _ => AppColors.fg3,
      };
      final glyph = SizedBox.square(
        dimension: 16,
        child: Center(child: AppIcon(icon, size: 14, color: color)),
      );
      if (widget.state != _NodeState.running) return Center(child: glyph);
      return RepaintBoundary(
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Opacity(
              opacity: 0.45 + 0.55 * (1 - (2 * _c.value - 1).abs()),
              child: child,
            ),
            child: glyph,
          ),
        ),
      );
    }
    const size = 9.0;
    final (fill, border) = switch (widget.state) {
      _NodeState.ok => (Colors.transparent, AppColors.ok),
      _NodeState.failed => (AppColors.danger, AppColors.danger),
      _NodeState.running => (AppColors.accent, AppColors.accent),
      _NodeState.neutral => (Colors.transparent, AppColors.fg4),
    };
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
    );
    if (widget.state != _NodeState.running) return Center(child: dot);
    return RepaintBoundary(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: (1 - _c.value) * 0.45,
                child: Container(
                  width: size + 8 * _c.value,
                  height: size + 8 * _c.value,
                  decoration: BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle),
                ),
              ),
              dot,
            ],
          ),
        ),
      ),
    );
  }
}

_NodeState _nodeFor(ToolStep step) {
  if (step.running) return _NodeState.running;
  if (step.failed) return _NodeState.failed;
  final r = step.result;
  if (r is Map && r['status'] == null && r['data'] == null) {
    return _NodeState.neutral;
  }
  return _NodeState.ok;
}

/// Inside an expanded work line: steps draw as a target and a result chip.
class StepScope extends InheritedWidget {
  const StepScope({super.key, required super.child});

  static bool active(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StepScope>() != null;

  @override
  bool updateShouldNotify(StepScope old) => false;
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
  const RunSpinner({super.key});

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
              dimension: 12,
              child: CustomPaint(
                painter: _SpinnerPainter(AppColors.run, AppColors.runBg),
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

/// One muted line for a run of tool calls: what the work did, an outcome word
/// and its duration. Running, it names the live step.
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
    final style = sans(kMobile ? 14 : 13, height: 1.4, color: AppColors.fg3);
    final work = describeWork(steps);
    final spans = isRunning
        ? <InlineSpan>[
            TextSpan(
                text: liveStepText(live.last),
                style: style.copyWith(color: AppColors.fg2))
          ]
        : workSpans(work, style);
    final took = isRunning ? null : stepsDuration(steps);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 32 : 26),
        child: Row(children: [
          SizedBox(
            width: 16,
            child: isRunning
                ? const RunSpinner()
                : Center(
                    child: AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: Motion.fast,
                      curve: Curves.easeOutCubic,
                      child: AppIcon('chevron-right',
                          size: 14, color: AppColors.fg4),
                    ),
                  ),
          ),
          SizedBox(width: S.s8),
          Expanded(
            child: Text.rich(TextSpan(children: spans),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          if (took != null) ...[
            SizedBox(width: S.s8),
            Text(formatWorkDuration(took),
                style: mono(12, color: AppColors.fg4)),
          ],
        ]),
      ),
    );
  }
}

/// The indented step list under an open work line: a 1px rule on the left.
class WorkSteps extends StatelessWidget {
  const WorkSteps({super.key, required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: S.of(7), top: S.s2, bottom: S.s4),
        child: Container(
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.border2))),
          padding: EdgeInsets.only(left: S.of(14)),
          child: StepScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
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

  bool get _open => widget.open ?? _localOpen;

  void _toggle() {
    final next = !_open;
    if (widget.onOpenChanged != null) {
      widget.onOpenChanged!(next);
    } else {
      setState(() => _localOpen = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final step =
        ToolStep(tool: widget.tool, args: widget.args, result: widget.result);
    final canExpand = toolHasDetail(step);
    final open = _open && canExpand;
    final asStep = StepScope.active(context);
    final Widget line;
    if (asStep) {
      final chip = stepChip(step);
      final target = stepTarget(step);
      line = Row(children: [
        SizedBox(
            width: 16, child: _Node(_nodeFor(step), icon: toolIcon(step.tool))),
        SizedBox(width: S.s8),
        Expanded(
          child: Text(target.isEmpty ? toolSentence(step) : target,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: codeMono(12, height: 1.4, color: AppColors.fg2)),
        ),
        if (chip != null) ...[SizedBox(width: S.s8), _ResultChip(chip)],
      ]);
    } else {
      final base = sans(_sentenceSize, height: 1.4, color: AppColors.fg3);
      final work = describeWork([step]);
      final spans = step.running
          ? <InlineSpan>[TextSpan(text: liveStepText(step))]
          : workSpans(work, base);
      final took = step.running ? null : stepsDuration([step]);
      line = Row(children: [
        SizedBox(
            width: 16, child: _Node(_nodeFor(step), icon: toolIcon(step.tool))),
        SizedBox(width: S.s8),
        Expanded(
          child: Text.rich(TextSpan(children: spans),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: base),
        ),
        if (took != null) ...[
          SizedBox(width: S.s8),
          Text(formatWorkDuration(took), style: mono(12, color: AppColors.fg4)),
        ],
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canExpand ? _toggle : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: kMobile ? 32 : 26),
            child: line,
          ),
        ),
        AnimatedSize(
          duration: Motion.fast,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: EdgeInsets.fromLTRB(S.s24, S.s2, 0, S.s8),
                  child: _StepDetail(step: step),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _ResultChip extends StatelessWidget {
  const _ResultChip(this.chip);
  final StepResultChip chip;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (chip.tone) {
      StepChipTone.ok => (AppColors.okBg, AppColors.ok),
      StepChipTone.danger => (AppColors.dangerBg, AppColors.danger),
      StepChipTone.neutral => (AppColors.surface2, AppColors.fg3),
    };
    final style = mono(11, color: fg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: chip.added > 0 || chip.removed > 0
          ? Text.rich(TextSpan(children: [
              TextSpan(
                  text: '+${chip.added}',
                  style: style.copyWith(color: AppColors.ok)),
              TextSpan(
                  text: ' −${chip.removed}',
                  style: style.copyWith(color: AppColors.danger)),
            ]))
          : Text(chip.text, style: style),
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

  double get _lineHeight => (kMobile ? 12.5 : 12) * 1.45;

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
    final copy = toolCopyText(step);
    final metaStyle = sans(kMobile ? 12 : 12, color: AppColors.fg3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.of(10)),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.card),
          ),
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
                    padding: EdgeInsets.only(top: S.s8),
                    child: Text(_full ? 'Show less' : more,
                        style: sans(kMobile ? 13 : 13,
                            weight: W.label, color: AppColors.fg3)),
                  ),
                ),
            ],
          ),
        ),
        if (meta.isNotEmpty || copy.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: S.s6, left: S.s2),
            child: Row(children: [
              if (meta.isNotEmpty) Text(meta.join(' · '), style: metaStyle),
              if (meta.isNotEmpty && copy.isNotEmpty)
                Text(' · ', style: metaStyle),
              if (copy.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(ClipboardData(text: copy));
                    toast(context, 'Copied');
                  },
                  child: Text('Copy',
                      style: metaStyle.copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.fg4)),
                ),
            ]),
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
        if (!long) ...rows else if (open) WorkSteps(rows: rows),
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
      false => ('**${widget.subject}** failed', SignalTone.danger, 'alert-triangle'),
      null => ('**${widget.subject}** has new output', SignalTone.neutral, 'activity'),
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
