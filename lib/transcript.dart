// Transcript components: an activity timeline for tool calls (one thin line,
// a node and one sentence per step, a single block for detail), lane cards,
// and styled system rows for watches, goals, and compaction.

import 'dart:async';

import 'package:flutter/material.dart';

import 'ambient_loop.dart';
import 'chat/ledger_line.dart';
import 'chat/tool_call_row.dart';
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
import 'tap_detector.dart';

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
            base.copyWith(color: w.failed ? AppColors.fg1 : AppColors.fg2, fontWeight: w.failed ? W.label : null)));
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

/// The phrase for a failing step: "3 tests failed" for a test run, else its chip.
String? _failureNote(List<ToolStep> steps) {
  // Quiet rule: only a run that ends on a failure reports it.
  final finished = steps.where((s) => !s.running).toList();
  if (finished.isNotEmpty &&
      !(finished.last.failed || verifyOutputFailed(finished.last))) {
    return null;
  }
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

/// The fold line of a finished run of tool calls: "Worked for 38s", flush
/// left with the text, then any failure note; tap to open.
/// Open, a thin rule runs out to the right. Running, it names the live step.
class WorkLine extends StatelessWidget {
  const WorkLine({
    super.key,
    required this.steps,
    required this.running,
    required this.open,
    required this.onTap,
    this.took,
  });

  final List<ToolStep> steps;

  /// Wall time from the event stamps; falls back to the steps' own timings.
  final Duration? took;
  final bool running;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final live = steps.where((s) => s.running).toList();
    final isRunning = running && live.isNotEmpty;
    final style = sans(kMobile ? 14 : 13,
        height: 1.3, color: AppColors.fg2, tabular: true);
    // The lead truncates; the counts after it always stay in view.
    var lead = TextSpan(
        text: isRunning ? liveStepText(live.last) : '',
        style: isRunning ? style.copyWith(color: AppColors.fg1) : null);
    final spans = <InlineSpan>[];
    if (!isRunning) {
      final took = this.took ?? stepsDuration(steps);
      lead = TextSpan(
          text: took != null
              ? 'Worked for ${formatWorkDuration(took)}'
              : 'Worked');
      final note = _failureNote(steps);
      if (note != null) {
        spans.add(TextSpan(
            text: ' · $note',
            style: style.copyWith(color: AppColors.fg1, fontWeight: W.label)));
      }
    }
    Widget rule() => Expanded(
          child: open
              ? ColoredBox(
                  color: AppColors.border,
                  child: const SizedBox(height: 1, width: double.infinity))
              : const SizedBox.shrink(),
        );
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: kMobile ? 48 : 32,
        child: LayoutBuilder(
          // The label is sized first so the rules only take what it leaves.
          builder: (context, c) => Row(children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: (c.maxWidth - (open ? 72 : 32)).clamp(0, 560)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text.rich(lead,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style),
                ),
                if (spans.isNotEmpty)
                  Text.rich(TextSpan(children: spans),
                      maxLines: 1, softWrap: false, style: style),
              ]),
            ),
            if (isRunning) ...[
              const SizedBox(width: 6),
              RunSpinner(size: 12, color: AppColors.fg2),
            ],
            if (open) ...[const SizedBox(width: 12), rule()],
          ]),
        ),
      ),
    );
  }
}

/// Steps that only look something up; a run of them folds into one group row.
bool isLookupStep(ToolStep s) => switch (toolBaseName(s.tool)) {
      'read_file' ||
      'view_file' ||
      'search_content' ||
      'grep_search' ||
      'find_by_name' ||
      'list_dir' ||
      'glob' =>
        true,
      _ => false,
    };

const double _rowGap = 2;

/// The step rows of an open run: flat, [_rowGap] apart. Two or more lookups in
/// a row fold into an "Explored" group.
class WorkSteps extends StatelessWidget {
  const WorkSteps({super.key, required this.rows, this.header = true});
  final List<Widget> rows;

  /// Whether a fold line sits above, which adds a little air before the rows.
  final bool header;

  @override
  Widget build(BuildContext context) {
    final items = _groupLookups(rows);
    // Desktop: steps sit in under the fold line, on a faint rail.
    final rail = !kMobile && header;
    return Container(
      margin: rail ? const EdgeInsets.only(left: 7) : null,
      padding: EdgeInsets.only(top: header ? 2 : 0, left: rail ? 20 : 0),
      decoration: rail
          ? BoxDecoration(
              border: Border(
                  left:
                      BorderSide(color: AppColors.fg1.withValues(alpha: 0.07))))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : _rowGap),
              child: items[i],
            ),
        ],
      ),
    );
  }
}

List<Widget> _groupLookups(List<Widget> rows) {
  final out = <Widget>[];
  var run = <DenseToolRow>[];
  void flush() {
    if (run.length >= 2) {
      final key = run.first.key;
      out.add(_ExploreGroup(
          key: key == null ? null : ValueKey('explore-$key'), rows: run));
    } else {
      out.addAll(run);
    }
    run = <DenseToolRow>[];
  }

  for (final r in rows) {
    if (r is DenseToolRow &&
        isLookupStep(ToolStep(tool: r.tool, args: r.args, result: r.result))) {
      run.add(r);
    } else {
      flush();
      out.add(r);
    }
  }
  flush();
  return out;
}

/// "Explored 3 files": consecutive lookups, open while their run is open.
class _ExploreGroup extends StatefulWidget {
  const _ExploreGroup({super.key, required this.rows});
  final List<DenseToolRow> rows;

  @override
  State<_ExploreGroup> createState() => _ExploreGroupState();
}

class _ExploreGroupState extends State<_ExploreGroup> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final steps = [
      for (final r in widget.rows)
        ToolStep(tool: r.tool, args: r.args, result: r.result),
    ];
    final live = steps.any((s) => s.running);
    final searches = steps.where(isSearchStep).length;
    final files = steps.length - searches;
    final object = [
      if (files > 0) '$files ${files == 1 ? 'file' : 'files'}',
      if (searches > 0) '$searches ${searches == 1 ? 'search' : 'searches'}',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FlatRow(
          live: live,
          onTap: () => setState(() => _open = !_open),
          title: TextSpan(children: [
            TextSpan(
                text: live ? 'Exploring' : 'Explored',
                style:
                    TextStyle(color: kMobile ? AppColors.fg1 : AppColors.fg3)),
            TextSpan(
                text: ' $object',
                style: kMobile
                    ? TextStyle(color: AppColors.fg3)
                    : TextStyle(
                        color: AppColors.fg2, fontWeight: FontWeight.w500)),
          ]),
        ),
        SpringExpand(
          open: _open,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, top: _rowGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.rows.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : _rowGap),
                    child: widget.rows[i],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

bool isSearchStep(ToolStep s) => switch (toolBaseName(s.tool)) {
      'read_file' || 'view_file' || 'list_dir' => false,
      _ => true,
    };

/// One flat line of the step list: title, trailing meta, live spinner.
class _FlatRow extends StatelessWidget {
  const _FlatRow({
    required this.title,
    required this.onTap,
    this.live = false,
    this.meta = const [],
  });

  final InlineSpan title;
  final VoidCallback? onTap;
  final bool live;
  final List<Widget> meta;

  @override
  Widget build(BuildContext context) {
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 36 : 30),
        // Text only: the verb carries the kind, so rows need no glyphs.
        child: Row(children: [
          Expanded(
            child: Text.rich(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 15 : 13, height: 1.35)),
          ),
          for (final m in meta) ...[const SizedBox(width: 10), m],
          if (live) ...[
            const SizedBox(width: 8),
            RunSpinner(size: 12, color: AppColors.accent),
          ],
        ]),
      ),
    );
  }
}

enum _Object { text, path, code }

/// A step as (verb, object, how to draw the object).
(String, String, _Object) _rowParts(ToolStep step) {
  final name = toolBaseName(step.tool);
  final running = step.running;
  final a = step.args is Map ? step.args as Map : const {};
  final (verb, object) = toolSentenceParts(step);
  switch (name) {
    case 'bash':
      final label = (a['label'] ?? '').toString().trim();
      // A label already reads as a sentence; a bare command is "Ran <command>".
      if (label.isNotEmpty) return (label, '', _Object.text);
      return (running ? 'Running' : 'Ran', stepTarget(step), _Object.code);
    case 'read_file':
    case 'view_file':
      final listing = step.data?['entries'] is List;
      return (
        listing ? (running ? 'Listing' : 'Listed') : verb,
        stepTarget(step),
        _Object.path
      );
    case 'list_dir':
      return (running ? 'Listing' : 'Listed', object, _Object.path);
    case 'search_content':
    case 'grep_search':
    case 'find_by_name':
    case 'glob':
      return (running ? 'Searching' : 'Searched', object, _Object.code);
    case 'view_image':
    case 'present_file':
      return (verb, stepTarget(step), _Object.path);
    case 'change_files':
      final many = RegExp(r'^\d+ files?$').hasMatch(object);
      return (
        verb,
        object,
        many || object.isEmpty ? _Object.text : _Object.path
      );
  }
  return (verb, object, _Object.text);
}

/// Trailing facts of a step: lines, hits, +/− counts, a result, the time.
List<Widget> _rowMeta(ToolStep step) {
  final base = kMobile
      ? sans(13, color: AppColors.fg2, tabular: true)
      : mono(11.5, color: AppColors.fg2);
  final chip = stepChip(step);
  final out = <Widget>[];
  if (chip != null && (chip.added > 0 || chip.removed > 0)) {
    out.add(Text.rich(TextSpan(style: base, children: [
      TextSpan(text: '+${chip.added}', style: TextStyle(color: AppColors.fg2)),
      TextSpan(
          text: ' −${chip.removed}', style: TextStyle(color: AppColors.fg2)),
    ])));
  } else if (chip != null) {
    final danger = chip.tone == StepChipTone.danger;
    out.add(Text(danger ? chip.text.split(', ').last : chip.text,
        maxLines: 1,
        style: base.copyWith(
            color: switch (chip.tone) {
          StepChipTone.ok => AppColors.fg2,
          StepChipTone.danger => AppColors.fg1,
          StepChipTone.neutral => AppColors.fg2,
        })));
  } else if (!step.running && toolBaseName(step.tool) == 'search_content') {
    final hits = step.data?['matches'] ?? step.data?['results'];
    if (hits is List) {
      out.add(Text('${hits.length} ${hits.length == 1 ? 'hit' : 'hits'}',
          style: base));
    }
  }
  final took = stepDuration(step);
  if (took != null) out.add(Text(took, maxLines: 1, style: base));
  return out;
}

class DenseToolRow extends StatefulWidget {
  final String tool;
  final dynamic args;
  final dynamic result; // null while running
  final bool? open;
  final ValueChanged<bool>? onOpenChanged;
  final int? startMs;
  final int? endMs;
  const DenseToolRow(
      {super.key,
      required this.tool,
      this.args,
      this.result,
      this.open,
      this.onOpenChanged,
      this.startMs,
      this.endMs});

  bool get pending => result == null;

  @override
  State<DenseToolRow> createState() => _DenseToolRowState();
}

class _DenseToolRowState extends State<DenseToolRow> {
  bool _localOpen = false;
  bool _touched = false;

  ToolStep get _step =>
      ToolStep(tool: widget.tool, args: widget.args, result: widget.result);

  bool get _isCommand => toolBaseName(widget.tool) == 'bash';

  // A failed step, and a command still running, start open until the reader
  // says otherwise.
  bool get _autoOpen =>
      stepChip(_step)?.tone == StepChipTone.danger ||
      (_isCommand && widget.pending);

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
    final liveCommand = _isCommand && step.running && step.args is Map;
    final canExpand = toolHasDetail(step) || liveCommand;
    final open = _open && canExpand;
    final danger = stepChip(step)?.tone == StepChipTone.danger;
    final (verb, object, kind) = _rowParts(step);
    final live = step.running;
    final objectStyle = !kMobile
        ? switch (kind) {
            _Object.code =>
              mono(11.5, color: live ? AppColors.fg1 : AppColors.fg2),
            _ => sans(13,
                weight: FontWeight.w500,
                color: live ? AppColors.fg1 : AppColors.fg2),
          }
        : switch (kind) {
            _Object.path => sans(kMobile ? 15 : 13, color: AppColors.accent),
            _Object.code => mono(kMobile ? 13 : 12.5,
                color: live ? AppColors.fg1 : AppColors.fg3),
            _Object.text => sans(kMobile ? 15 : 13,
                color: live ? AppColors.fg1 : AppColors.fg3),
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Desktop TC-04/05: the shared tool-call row anatomy.
        if (!kMobile)
          ToolCallRow(
            step: step,
            onTap: canExpand ? _toggle : null,
            open: open,
            showChevron: canExpand,
          )
        else
        _FlatRow(
          live: live,
          onTap: canExpand ? _toggle : null,
          title: TextSpan(children: [
            TextSpan(
                text: verb,
                style: TextStyle(
                    color: danger
                        ? AppColors.fg1
                        : kMobile || live
                            ? AppColors.fg1
                            : AppColors.fg3)),
            if (object.isNotEmpty)
              TextSpan(text: ' $object', style: objectStyle),
          ]),
          meta: _rowMeta(step),
        ),
        SpringExpand(
          open: open,
          child: canExpand
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
                  child: _isCommand
                      ? TerminalBlock(step: step)
                      : _StepDetail(step: step),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// The opened body of a tool row without its title, for lists that already name the step.
Widget? toolRowBody(DenseToolRow r) {
  final step =
      ToolStep(tool: r.tool, args: r.args, result: r.result);
  final command = toolBaseName(r.tool) == 'bash';
  if (!toolHasDetail(step) && !(command && step.running && step.args is Map)) {
    return null;
  }
  return command ? TerminalBlock(step: step) : _StepDetail(step: step);
}

final _ansiCodes = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

/// A command opened: "$ command", its output capped at a few lines with a
/// fade, and the exit code in the corner.
class TerminalBlock extends StatefulWidget {
  const TerminalBlock({
    super.key,
    required this.step,
    this.commandLines,
    this.outputCap = 8,
    this.tail = false,
    this.size = 12,
  });
  final ToolStep step;

  /// Clamp the command to this many lines behind "Show full command".
  final int? commandLines;

  /// Output lines shown before "Show all".
  final int outputCap;

  /// Show the last lines of the output, as a running command does.
  final bool tail;
  final double size;

  @override
  State<TerminalBlock> createState() => _TerminalBlockState();
}

class _TerminalBlockState extends State<TerminalBlock> {
  static const _lineHeight = 1.6;
  double get _size => widget.size;
  int get _cap => widget.outputCap;
  bool _full = false;
  bool _cmdFull = false;

  static String _clean(Object? v) => (v ?? '')
      .toString()
      .replaceAll(_ansiCodes, '')
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .trimRight();

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final a = step.args is Map ? step.args as Map : const {};
    final d = step.data;
    final cmd = _clean(a['command'] ?? d?['command']);
    final stdout = _clean(step.stdout);
    var stderr = _clean(d?['stderr']);
    final err = step.result is Map ? (step.result as Map)['error'] : null;
    if (err is Map && step.failed && stderr.isEmpty && stdout.isEmpty) {
      stderr = _clean(err['message']);
    }
    final base = codeMono(_size, height: _lineHeight, color: AppColors.fg3);
    final out = stdout.isEmpty ? const <String>[] : stdout.split('\n');
    final errLines = stderr.isEmpty ? const <String>[] : stderr.split('\n');
    final total = out.length + errLines.length;
    final overflow = total > _cap;
    final capped = overflow && !_full;
    final cmdLines = cmd.isEmpty ? const <String>[] : cmd.split('\n');
    final clampCmd = widget.commandLines != null &&
        (cmdLines.length > widget.commandLines! || cmd.length > 110);
    // A running command shows its newest lines, a finished one its first.
    final skip = capped && widget.tail ? total - _cap : 0;
    final outShown = out.skip(skip.clamp(0, out.length)).toList();
    final errShown =
        errLines.skip((skip - out.length).clamp(0, errLines.length)).toList();
    final output = total == 0
        ? null
        : Text.rich(TextSpan(style: base, children: [
            for (var i = 0; i < outShown.length; i++)
              TextSpan(
                  text: '${i == 0 ? '' : '\n'}${outShown[i]}',
                  style: errorLineMarker.hasMatch(outShown[i])
                      ? TextStyle(color: AppColors.fg1, fontWeight: W.label)
                      : null),
            for (var i = 0; i < errShown.length; i++)
              TextSpan(
                  text: '${outShown.isEmpty && i == 0 ? '' : '\n'}${errShown[i]}',
                  style: TextStyle(color: AppColors.fg1, fontWeight: W.label)),
          ]));
    final exit = step.exitCode;
    final (String, bool)? badge = step.running
        ? null
        : exit != null
            ? ('exit $exit', exit != 0)
            : (step.failed ? ('failed', true) : null);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cmdLines.isNotEmpty)
            Text.rich(
                TextSpan(style: base, children: [
                  for (var i = 0; i < cmdLines.length; i++) ...[
                    if (i > 0) const TextSpan(text: '\n'),
                    TextSpan(
                        text: i == 0 ? r'$ ' : '  ',
                        style: TextStyle(color: AppColors.fg3)),
                    TextSpan(
                        text: cmdLines[i],
                        style: TextStyle(color: AppColors.fg2)),
                  ],
                ]),
                maxLines: clampCmd && !_cmdFull ? widget.commandLines : null,
                overflow: TextOverflow.ellipsis),
          if (clampCmd)
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _cmdFull = !_cmdFull),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_cmdFull ? 'Show less' : 'Show full command',
                    style: sans(13, weight: W.label, color: AppColors.fg3)),
              ),
            ),
          if (output != null) ...[
            if (cmdLines.isNotEmpty) const SizedBox(height: 6),
            capped
                ? SizedBox(
                    height: _cap * _size * _lineHeight,
                    child: Stack(children: [
                      ClipRect(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: output,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: widget.tail ? 0 : null,
                        bottom: widget.tail ? null : 0,
                        height: 3 * _size * _lineHeight,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: widget.tail
                                    ? [
                                        AppColors.surface2,
                                        AppColors.surface2.withValues(alpha: 0),
                                      ]
                                    : [
                                        AppColors.surface2.withValues(alpha: 0),
                                        AppColors.surface2,
                                      ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  )
                : output,
          ],
          if (overflow || badge != null || (step.running && widget.tail))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                if (overflow)
                  TapDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _full = !_full),
                    child: Text(_full ? 'Show less' : 'Show all $total lines',
                        style: sans(12, weight: W.label, color: AppColors.fg3)),
                  ),
                if (step.running && widget.tail)
                  Text('Following',
                      style: sans(12, weight: W.label, color: AppColors.fg3)),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: badge.$2
                          ? AppColors.surface3
                          : AppColors.surface3,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(badge.$1,
                        style: sans(11,
                            color: badge.$2 ? AppColors.fg1 : AppColors.fg2,
                            tabular: true)),
                  ),
              ]),
            ),
        ],
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
    final countsLines = tool == 'read_file' || tool == 'change_files';
    final lines = (_height / _lineHeight).round();
    final more = countsLines ? 'Show all $lines lines' : 'Show all';
    final meta = toolMetaParts(step);
    final metaStyle = sans(12, color: AppColors.fg3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No inner box: the transcript itself is the surface.
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
                TapDetector(
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

/// A finished run folds into one line that opens into its steps; a run still
/// working shows its rows directly. Shared by the transcript and [ToolRun].
class ActivityFold extends StatelessWidget {
  const ActivityFold({
    super.key,
    required this.rows,
    required this.running,
    required this.open,
    required this.onTap,
    this.took,
  });

  final List<Widget> rows;
  final bool running;
  final Duration? took;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final steps = [
      for (final r in rows.whereType<DenseToolRow>())
        ToolStep(
            tool: r.tool,
            args: r.args,
            result: r.result,
            startMs: r.startMs,
            endMs: r.endMs),
    ];
    if (!kMobile) {
      final dense = rows.whereType<DenseToolRow>().toList();
      // Plan and image rows ride along; the sentence is built from tool rows.
      if (dense.isNotEmpty) {
        return running
            ? LedgerStrip(rows: rows, steps: steps)
            : LedgerLine(
                rows: dense,
                allRows: rows,
                steps: steps,
                open: open,
                onTap: onTap,
                took: took);
      }
    }
    if (running) return WorkSteps(rows: rows, header: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkLine(
            steps: steps, running: false, open: open, onTap: onTap, took: took),
        SpringExpand(open: open, child: WorkSteps(rows: rows)),
      ],
    );
  }
}

/// A run of tool steps: one fold line while finished, rows while running.
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: ActivityFold(
          rows: widget.rows,
          running: widget.running,
          open: _open,
          onTap: _toggle),
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

    if (step == 'goal_set' ||
        step == 'goal_completed' ||
        step == 'goal_paused' ||
        step == 'goal_cancelled') {
      return const SizedBox.shrink();
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
                  child: AppIcon('activity', size: 14, color: AppColors.fg3)),
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
