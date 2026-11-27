// "Ledger line": desktop tool activity as one sentence of hoverable phrases
// while finished, and a single 40px strip while a step is running.

import '../quiet.dart';
import '../platform.dart' show kMobile;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tool_activity.dart';
import '../transcript.dart';
import '../widgets.dart';
import '../tap_detector.dart';

enum LedgerKind { search, read, web, edit, command, other }

class LedgerPhrase {
  const LedgerPhrase({
    required this.kind,
    required this.indices,
    required this.text,
    this.failures = 0,
  });

  final LedgerKind kind;

  /// Positions in the step list this phrase covers.
  final List<int> indices;

  /// "searched 3 places"; the first phrase of a line starts capitalised.
  final String text;
  final int failures;

  String? get failNote => failures > 0 ? '($failures failed)' : null;
}

bool _stepFailed(ToolStep s) => s.failed || verifyOutputFailed(s);

/// Group key: the kind, plus the tool name for tools with no kind of their own.
(LedgerKind, String) _kindOf(ToolStep s) {
  final name = toolBaseName(s.tool);
  switch (name) {
    case 'search_content' ||
          'grep_search' ||
          'find_by_name' ||
          'glob' ||
          'list_dir':
      return (LedgerKind.search, '');
    case 'read_file' || 'view_file' || 'view_image':
      return (LedgerKind.read, '');
    case 'web_search' || 'web_read':
      return (LedgerKind.web, '');
    case 'change_files':
      return (LedgerKind.edit, '');
    case 'bash':
      return switch (stepCommand(s)?.kind) {
        CommandKind.search => (LedgerKind.search, ''),
        CommandKind.read => (LedgerKind.read, ''),
        _ => (LedgerKind.command, ''),
      };
  }
  return (LedgerKind.other, name);
}

String _plural(int n, String one, String many) => n == 1 ? one : many;

String _base(String path) {
  final parts = path.split('/').where((e) => e.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

String? _pathArg(ToolStep s) {
  final a = s.args is Map ? s.args as Map : const {};
  final p = (a['path'] ?? a['AbsolutePath'] ?? a['SearchPath'] ?? '')
      .toString()
      .trim();
  return p.isEmpty ? null : p;
}

String _phraseText(LedgerKind kind, String tool, List<ToolStep> steps) {
  final n = steps.length;
  switch (kind) {
    case LedgerKind.search:
      final paths = {for (final s in steps) _pathArg(s)}..remove(null);
      if (n == 1 && paths.length == 1) {
        return 'searched ${_base(paths.single!)}';
      }
      if (n == 1) return 'searched the code';
      return 'searched $n places';
    case LedgerKind.read:
      final paths = {for (final s in steps) _pathArg(s) ?? ''}..remove('');
      if (paths.length == 1) return 'read ${_base(paths.single)}';
      final count = paths.isEmpty ? n : paths.length;
      return count == 1 ? 'read a file' : 'read $count files';
    case LedgerKind.web:
      return 'searched the web';
    case LedgerKind.edit:
      final paths = <String>{
        for (final s in steps)
          for (final c in s.changes)
            if ((c['path'] ?? '').toString().isNotEmpty) c['path'].toString(),
      };
      final files = fileChanges(steps);
      if (paths.length == 1) {
        final name = _base(paths.single);
        final f = files.length == 1 ? files.single : null;
        if (f != null && (f.added > 0 || f.removed > 0)) {
          return 'edited $name +${f.added} −${f.removed}';
        }
        return 'edited $name';
      }
      final count = paths.isEmpty ? n : paths.length;
      return 'edited $count ${_plural(count, 'file', 'files')}';
    case LedgerKind.command:
      final tests =
          steps.where((s) => stepCommand(s)?.kind == CommandKind.test).length;
      if (tests == n) {
        return switch (n) {
          1 => 'ran tests',
          2 => 'ran tests twice',
          _ => 'ran tests $n times',
        };
      }
      return n == 1 ? 'ran a command' : 'ran $n commands';
    case LedgerKind.other:
      final label = tool.replaceAll('_', ' ');
      return n == 1 ? 'used $label' : 'used $label $n times';
  }
}

/// Steps of one kind fold into one phrase, in order of first appearance, so
/// a read-run-read-run loop reads as two phrases rather than four.
List<LedgerPhrase> ledgerPhrases(List<ToolStep> steps) {
  final groups = <(LedgerKind, String), List<int>>{};
  for (var i = 0; i < steps.length; i++) {
    groups.putIfAbsent(_kindOf(steps[i]), () => []).add(i);
  }
  final out = <LedgerPhrase>[];
  for (final e in groups.entries) {
    final group = [for (final k in e.value) steps[k]];
    var text = _phraseText(e.key.$1, e.key.$2, group);
    if (out.isEmpty) text = '${text[0].toUpperCase()}${text.substring(1)}';
    out.add(LedgerPhrase(
      kind: e.key.$1,
      indices: e.value,
      text: text,
      failures: group.where(_stepFailed).length,
    ));
  }
  return out;
}

String _iconFor(LedgerKind k) => switch (k) {
      LedgerKind.search => 'search',
      LedgerKind.read => 'file-text',
      LedgerKind.web => 'globe',
      LedgerKind.edit => 'edit',
      LedgerKind.command => 'terminal',
      LedgerKind.other => 'activity',
    };

/// The live label of the strip: what is happening now, by kind.
String ledgerLiveLabel(ToolStep s) {
  final cmd = stepCommand(s);
  if (cmd != null) {
    switch (cmd.kind) {
      case CommandKind.test:
        return 'Running tests';
      case CommandKind.build:
        return 'Building';
      case CommandKind.check:
        return 'Checking';
      default:
    }
  }
  return switch (_kindOf(s).$1) {
    LedgerKind.edit => 'Editing',
    LedgerKind.read => 'Reading',
    LedgerKind.search => 'Searching',
    LedgerKind.web => 'Searching the web',
    LedgerKind.command => 'Running',
    LedgerKind.other => toolSentenceParts(s, running: true).$1,
  };
}

/// Finished run: a sentence of phrases; hover previews, click opens in place.
class LedgerLine extends StatefulWidget {
  const LedgerLine({
    super.key,
    required this.rows,
    required this.steps,
    required this.open,
    required this.onTap,
    this.took,
    this.allRows,
  });

  /// Step rows, one per entry in [steps].
  final List<DenseToolRow> rows;

  /// Every row of the run, including non-tool rows, for the open-all view.
  final List<Widget>? allRows;
  final List<ToolStep> steps;
  final bool open;
  final VoidCallback onTap;
  final Duration? took;

  @override
  State<LedgerLine> createState() => _LedgerLineState();
}

class _LedgerLineState extends State<LedgerLine> {
  int? _phrase;
  bool _hover = false;

  // Kept after closing so the collapse animates the rows it was showing.
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final phrases = ledgerPhrases(widget.steps);
    final took = widget.took ?? stepsDuration(widget.steps);
    final base = sans(kMobile ? 13 : 12,
        height: kMobile ? 1.45 : 17 / 12,
        color: kMobile ? AppColors.fg3 : AppColors.fg2,
        tabular: true);
    final spans = <InlineSpan>[];
    for (var i = 0; i < phrases.length; i++) {
      final p = phrases[i];
      if (i > 0) spans.add(TextSpan(text: ', ', style: base));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _PhraseTarget(
          phrase: p,
          steps: [for (final k in p.indices) widget.steps[k]],
          style: base,
          active: _phrase == i && !widget.open,
          onTap: () {
            if (widget.open) widget.onTap();
            setState(() {
              _phrase = _phrase == i && !widget.open ? null : i;
              _shown = i;
            });
          },
        ),
      ));
    }
    final shown = _shown < phrases.length ? phrases[_shown] : null;
    if (!kMobile) {
      // Desktop TC-01/02: one s1 surface, a state icon at x+14, the sentence
      // at x+32, mono duration at the right and expansion behind one hairline.
      final lifted = _phrase != null && !widget.open;
      // Steps read as quiet text; a plate only on hover or when open.
      return MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Container(
          decoration: BoxDecoration(
            color: lifted
                ? AppColors.surface2
                : (widget.open || _hover)
                    ? AppColors.surface1
                    : null,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: SizedBox(
                  height: 30,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
                    child: Row(children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: Center(
                          child:
                              AppIcon('check', size: 13, color: AppColors.fg3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: spans),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: base,
                        ),
                      ),
                      if (took != null) ...[
                        const SizedBox(width: 10),
                        Text(formatWorkDuration(took),
                            style: mono(11, color: AppColors.fg3)),
                      ],
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: AnimatedRotation(
                            turns: widget.open ? 0.25 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: AppIcon('chevron-right',
                                size: 12, color: AppColors.fg3),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              SpringExpand(
                open: widget.open,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(height: 1, color: AppColors.line),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                      child: LedgerGantt(
                          steps: widget.steps, rows: widget.rows, total: took),
                    ),
                  ],
                ),
              ),
              SpringExpand(
                open: _phrase != null && !widget.open,
                child: shown == null
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(height: 1, color: AppColors.line),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                            child: LedgerGantt(
                              steps: [
                                for (final k in shown.indices) widget.steps[k]
                              ],
                              rows: [
                                for (final k in shown.indices) widget.rows[k]
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    }
    // Finished run: the live strip's card settles into its done state.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: BoxConstraints(minHeight: kMobile ? 48 : 28),
          padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  // Line tier: one fg2 icon, never a colour face or a red mark.
                  child: AppIcon('terminal',
                      size: kMobile ? 16 : 14, color: AppColors.fg2),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    ...spans,
                    if (phrases.isNotEmpty) TextSpan(text: '.', style: base),
                  ]),
                  style: base,
                ),
              ),
              if (took != null)
                TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(formatWorkDuration(took),
                        style: sans(kMobile ? 13 : 12, color: AppColors.fg2)),
                  ),
                ),
              HoverSurface(
                radius: 6,
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AnimatedRotation(
                    turns: widget.open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: AppIcon('chevron-right',
                        size: 13, color: AppColors.fg3),
                  ),
                ),
              ),
            ],
          ),
        ),
        SpringExpand(
          open: widget.open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: LedgerGantt(
                steps: widget.steps, rows: widget.rows, total: took),
          ),
        ),
        SpringExpand(
          open: _phrase != null && !widget.open,
          child: shown == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: LedgerGantt(
                    steps: [for (final k in shown.indices) widget.steps[k]],
                    rows: [for (final k in shown.indices) widget.rows[k]],
                  ),
                ),
        ),
      ],
    );
  }
}

class _PhraseTarget extends StatefulWidget {
  const _PhraseTarget({
    required this.phrase,
    required this.steps,
    required this.style,
    required this.active,
    required this.onTap,
  });

  final LedgerPhrase phrase;
  final List<ToolStep> steps;
  final TextStyle style;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_PhraseTarget> createState() => _PhraseTargetState();
}

class _PhraseTargetState extends State<_PhraseTarget> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  bool _hover = false;

  void _set(bool v) {
    if (!mounted || _hover == v) return;
    setState(() => _hover = v);
    v ? _portal.show() : _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.phrase;
    final on = _hover || widget.active;
    final tone = on ? AppColors.accent : AppColors.fg2;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 4),
            child: IgnorePointer(child: _LedgerPopover(steps: widget.steps)),
          ),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _set(true),
          onExit: (_) => _set(false),
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: p.text,
                style: widget.style.copyWith(
                  color: tone,
                  decoration: TextDecoration.none,
                ),
              ),
            ])),
          ),
        ),
      ),
    );
  }
}

class _LedgerPopover extends StatelessWidget {
  const _LedgerPopover({required this.steps});
  final List<ToolStep> steps;

  static const _max = 6;

  @override
  Widget build(BuildContext context) {
    final shown = steps.take(_max).toList();
    final more = steps.length - shown.length;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, minWidth: 200),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          boxShadow: overlayShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in shown) _PopRow(step: s),
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                  child: Text('+$more more',
                      style: sans(12, color: AppColors.fg3)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopRow extends StatelessWidget {
  const _PopRow({required this.step});
  final ToolStep step;

  @override
  Widget build(BuildContext context) {
    final bad = _stepFailed(step);
    final meta = stepChip(step)?.text ?? stepDuration(step);
    final target = stepTarget(step);
    return SizedBox(
      height: 24,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [
          AppIcon(_iconFor(_kindOf(step).$1),
              size: 13, color: AppColors.fg3),
          const SizedBox(width: 8),
          Flexible(
            child: Text(target.isEmpty ? liveStepText(step) : target,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: mono(11.5, color: bad ? AppColors.fg2 : AppColors.fg1)),
          ),
          if (meta != null) ...[
            const SizedBox(width: 12),
            Text(meta, style: mono(11, color: AppColors.fg3)),
          ],
        ]),
      ),
    );
  }
}

/// Running run: one strip, with Peek to show the step rows beneath it.
/// Session facts the live strip needs but its rows do not carry.
class LedgerLiveScope extends InheritedWidget {
  const LedgerLiveScope({
    super.key,
    required super.child,
    this.agentId,
    this.startedAt,
    this.onStop,
  });

  final String? agentId;

  /// The turn's start, the elapsed fallback when steps carry no stamps.
  final String? startedAt;

  /// Interrupts the run; null when nothing is running or Stop is not ours.
  final VoidCallback? onStop;

  static LedgerLiveScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LedgerLiveScope>();

  @override
  bool updateShouldNotify(LedgerLiveScope old) =>
      agentId != old.agentId ||
      startedAt != old.startedAt ||
      (onStop == null) != (old.onStop == null);
}

String _clock(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  final m = d.inMinutes;
  if (m < 60) return '${m}m ${s % 60}s';
  return '${d.inHours}h ${m % 60}m';
}

/// Last few non-empty lines of a finished step's output.
List<String> _tail(ToolStep s, {int n = 3}) {
  final d = s.data;
  final r = s.result;
  final raw = [
    s.stdout,
    (d?['stderr'] ?? '').toString(),
    if (r is Map && r['error'] is Map)
      ((r['error'] as Map)['message'] ?? '').toString(),
  ].join('\n');
  final lines = raw
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.trim().isNotEmpty)
      .toList();
  return lines.length <= n ? lines : lines.sublist(lines.length - n);
}

String _failLabel(ToolStep s) {
  final cmd = stepCommand(s);
  if (cmd?.kind == CommandKind.test) return 'Tests failed';
  if (cmd?.kind == CommandKind.build) return 'Build failed';
  if (cmd?.kind == CommandKind.check) return 'Check failed';
  return toolBaseName(s.tool) == 'bash' ? 'Command failed' : 'Step failed';
}

bool _typing() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Steps as rows, each with its own track on the run's timeline, then a
/// one-line tally; a row opens its full step when [rows] are given.
class LedgerGantt extends StatefulWidget {
  const LedgerGantt({super.key, required this.steps, this.rows, this.total});

  final List<ToolStep> steps;

  /// Full step rows, one per entry in [steps], opened by tapping a row.
  final List<Widget>? rows;

  /// Total shown in the tally; measured from the steps when null.
  final Duration? total;

  @override
  State<LedgerGantt> createState() => _LedgerGanttState();
}

class _LedgerGanttState extends State<LedgerGantt> {
  int? _open;

  // Unstamped steps get equal slots by position.
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final steps = widget.steps;
    final n = steps.length;
    final now = DateTime.now().millisecondsSinceEpoch;
    final starts = [for (final s in steps) s.startMs].whereType<int>();
    final t0 = starts.isEmpty ? null : starts.reduce((a, b) => a < b ? a : b);
    var t1 = t0 ?? 0;
    for (final s in steps) {
      final e = s.running ? now : (s.endMs ?? s.startMs);
      if (e != null && e > t1) t1 = e;
    }
    String took(ToolStep s) {
      if (s.startMs == null) return '';
      final ms = (s.running ? now : (s.endMs ?? s.startMs!)) - s.startMs!;
      return ms < 10000
          ? '${(ms / 1000).toStringAsFixed(1)}s'
          : _clock(Duration(milliseconds: ms));
    }

    final tally = <LedgerKind, int>{};
    var failed = 0;
    for (final s in steps) {
      tally.update(_kindOf(s).$1, (v) => v + 1, ifAbsent: () => 1);
      if (!s.running && _stepFailed(s)) failed++;
    }
    String noun(LedgerKind k, int c) => switch (k) {
          LedgerKind.read => _plural(c, 'read', 'reads'),
          LedgerKind.search => _plural(c, 'search', 'searches'),
          LedgerKind.web => _plural(c, 'web lookup', 'web lookups'),
          LedgerKind.edit => _plural(c, 'edit', 'edits'),
          LedgerKind.command => _plural(c, 'command', 'commands'),
          LedgerKind.other => _plural(c, 'other step', 'other steps'),
        };
    final el =
        widget.total ?? (t0 == null ? null : Duration(milliseconds: t1 - t0));

    Widget row(int i) {
      final s = steps[i];
      final (verb, obj) = toolSentenceParts(s);
      final target =
          obj.isNotEmpty ? obj : (verb.contains(' ') ? '' : stepTarget(s));
      final raw = widget.rows != null && i < widget.rows!.length
          ? widget.rows![i]
          : null;
      // The line already names the step; open straight to its output.
      final Widget? detail = raw is DenseToolRow ? toolRowBody(raw) : raw;
      final line = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(children: [
          AppIcon(_iconFor(_kindOf(s).$1), size: 14, color: AppColors.fg2),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: target.isEmpty ? verb : '$verb  ',
                    style: sans(12.5,
                        color: target.isEmpty ? AppColors.fg2 : AppColors.fg3)),
                if (target.isNotEmpty)
                  TextSpan(text: target, style: mono(12, color: AppColors.fg1)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(took(s),
                textAlign: TextAlign.right,
                style: mono(11.5, color: AppColors.fg3)),
          ),
        ]),
      );
      if (detail == null) return line;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoverSurface(
            radius: 6,
            onTap: () => setState(() => _open = _open == i ? null : i),
            child: line,
          ),
          SpringExpand(
            open: _open == i,
            child: Padding(
              padding: const EdgeInsets.only(left: 23, bottom: 4),
              child: raw is DenseToolRow
                  ? detail
                  : WorkSteps(rows: [detail], header: false),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < n; i++) row(i),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(children: [
            for (final e in tally.entries) ...[
              Text('${e.value} ${noun(e.key, e.value)}',
                  style: sans(12, color: AppColors.fg3)),
              const SizedBox(width: 12),
            ],
            if (failed > 0)
              Text('$failed failed', style: sans(12, color: AppColors.fg3)),
            const Spacer(),
            if (el != null)
              Text(_clock(el), style: mono(11.5, color: AppColors.fg3)),
          ]),
        ),
      ],
    );
  }
}

/// Running run: one 40px strip with the mascot, what is happening in words,
/// The command, a step bar sized by time, elapsed time, Peek and Stop. The
/// latest failure sits above it in red with its last output lines.
class LedgerStrip extends StatefulWidget {
  const LedgerStrip({super.key, required this.rows, required this.steps});

  final List<Widget> rows;
  final List<ToolStep> steps;

  @override
  State<LedgerStrip> createState() => _LedgerStripState();
}

class _LedgerStripState extends State<LedgerStrip> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  Timer? _tick;
  bool _pinned = false;
  int? _dismissedFail;
  bool _keys = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final want = LedgerLiveScope.of(context)?.onStop != null;
    if (want != _keys) {
      _keys = want;
      want
          ? HardwareKeyboard.instance.addHandler(_onKey)
          : HardwareKeyboard.instance.removeHandler(_onKey);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_keys) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // Space peeks and Esc stops, only while no text field has focus.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || _typing() || !mounted) return false;
    if (e.logicalKey == LogicalKeyboardKey.space) {
      _togglePeek();
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      if (_portal.isShowing) {
        _portal.hide();
        setState(() {});
        return true;
      }
      final stop = LedgerLiveScope.of(context)?.onStop;
      if (stop != null) {
        stop();
        return true;
      }
    }
    return false;
  }

  void _togglePeek() {
    if (!mounted) return;
    if (_pinned) {
      setState(() => _pinned = false);
      return;
    }
    _portal.isShowing ? _portal.hide() : _portal.show();
    setState(() {});
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Duration? _elapsed() {
    int? first;
    for (final s in widget.steps) {
      if (s.startMs != null) {
        first = s.startMs;
        break;
      }
    }
    if (first == null) {
      final t = DateTime.tryParse(LedgerLiveScope.of(context)?.startedAt ?? '');
      if (t == null) return null;
      first = t.millisecondsSinceEpoch;
    }
    final ms = _now - first;
    return ms < 0 ? Duration.zero : Duration(milliseconds: ms);
  }

  Widget _key(String k) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.fg1.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(k, style: mono(10.5, color: AppColors.fg3)),
      );

  Widget _btn(String icon, String label, String key, VoidCallback? onTap,
          {bool filled = false}) =>
      HoverSurface(
        radius: 6,
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: filled
              ? BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(6))
              : null,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon, size: 13, color: AppColors.fg2),
            const SizedBox(width: 6),
            Text(label, style: sans(12, weight: W.label, color: AppColors.fg2)),
            _key(key),
          ]),
        ),
      );

  Widget _peekPanel() => TapRegion(
        groupId: _link,
        onTapOutside: (_) {
          if (!mounted) return;
          _portal.hide();
          setState(() {});
        },
        child: Container(
          width: 470,
          constraints: const BoxConstraints(maxHeight: 340),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
            boxShadow: overlayShadow,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
              child: Row(children: [
                Expanded(
                    child: Text('Steps so far',
                        style:
                            sans(12, weight: W.label, color: AppColors.fg2))),
                HoverSurface(
                  radius: 6,
                  onTap: () {
                    _portal.hide();
                    setState(() => _pinned = true);
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(children: [
                      AppIcon('pin', size: 12, color: AppColors.fg3),
                      const SizedBox(width: 4),
                      Text('Pin', style: sans(11.5, color: AppColors.fg3)),
                    ]),
                  ),
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: LedgerGantt(
                    steps: widget.steps, rows: widget.rows, total: _elapsed()),
              ),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final scope = LedgerLiveScope.of(context);
    final steps = widget.steps;
    ToolStep? live;
    for (final s in steps.reversed) {
      if (s.running) {
        live = s;
        break;
      }
    }
    var failAt = -1;
    for (var i = steps.length - 1; i >= 0; i--) {
      if (!steps[i].running && _stepFailed(steps[i])) {
        failAt = i;
        break;
      }
    }
    final fail = failAt >= 0 && failAt != _dismissedFail ? steps[failAt] : null;
    // Quiet rule: a failure a later step got past is one muted line; only a
    // failure nothing recovered from becomes the amber hand.
    final recovered = fail != null &&
        steps.skip(failAt + 1).any((s) => !s.running && !_stepFailed(s));
    // No call in flight: the model is between steps.
    final label = live == null ? 'Thinking' : ledgerLiveLabel(live);
    final target = live == null ? '' : stepTarget(live);
    final el = _elapsed();
    final peekOpen = _portal.isShowing || _pinned;

    // Keyed so inserting the failure banner above it never remounts _portal.
    final strip = Container(
      key: const ValueKey('ledger-strip'),
      constraints: BoxConstraints(minHeight: kMobile ? 48 : 28),
      padding: EdgeInsets.only(left: kMobile ? 0 : 10, right: 3),
      decoration: kMobile
          ? null
          : BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(8),
            ),
      child: Row(children: [
        SizedBox(
          width: kMobile ? 16 : 14,
          height: kMobile ? 16 : 14,
          child: Center(child: RunSpinner(size: 12, color: AppColors.fg2)),
        ),
        const SizedBox(width: 8),
        Text(label,
            maxLines: 1,
            softWrap: false,
            style: sans(kMobile ? 13 : 12,
                weight: kMobile ? W.label : W.body, color: AppColors.fg1)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(target,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: mono(kMobile ? 12 : 12, color: AppColors.fg2)),
        ),
        const SizedBox(width: 10),
        if (el != null) ...[
          Text(_clock(el),
              style: mono(kMobile ? 12 : 11, color: AppColors.fg3)),
          const SizedBox(width: 8),
        ],
        // Keyed so toggling the progress bar or clock before it never remounts _portal.
        CompositedTransformTarget(
          key: const ValueKey('ledger-peek-portal'),
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (_) => CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.bottomRight,
              offset: const Offset(0, -8),
              child: Align(
                  alignment: Alignment.bottomRight,
                  child: Material(
                      type: MaterialType.transparency, child: _peekPanel())),
            ),
            child: TapRegion(
              groupId: _link,
              child:
                  _btn('eye', 'Peek', 'Space', _togglePeek, filled: peekOpen),
            ),
          ),
        ),
        if (scope?.onStop != null) ...[
          const SizedBox(width: 2),
          _btn('stop', 'Stop', 'Esc', scope!.onStop),
        ],
      ]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fail != null && recovered)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: QuietRecoveredLine(
              summary:
                  '${_failLabel(fail)}, recovered${fail.exitCode != null ? ' (exit ${fail.exitCode})' : ''}',
              detail: _tail(fail, n: 12).join('\n'),
            ),
          )
        else if (fail != null) ...[
          Container(
            height: 32,
            padding: const EdgeInsets.only(left: 9, right: 3),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              AppIcon('x', size: 14, color: AppColors.fg1),
              const SizedBox(width: 10),
              Text(_failLabel(fail),
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    [
                      if (fail.exitCode != null) 'exit ${fail.exitCode}',
                      stepTarget(fail),
                    ].join(' · '),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: mono(12, color: AppColors.fg3)),
              ),
              if (fail.startMs != null && fail.endMs != null) ...[
                const SizedBox(width: 10),
                Text(
                    _clock(Duration(milliseconds: fail.endMs! - fail.startMs!)),
                    style: mono(12, color: AppColors.fg3)),
              ],
              const SizedBox(width: 6),
              IconBtn('copy',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Copy output',
                  onTap: () => Clipboard.setData(
                      ClipboardData(text: _tail(fail, n: 400).join('\n')))),
              IconBtn('x',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Dismiss',
                  onTap: () => setState(() => _dismissedFail = failAt)),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
                _tail(fail).isEmpty ? 'no output' : _tail(fail).join('\n'),
                style: mono(12,
                    color:
                        _tail(fail).isEmpty ? AppColors.fg3 : AppColors.fg1)),
          ),
          const SizedBox(height: 6),
        ],
        strip,
        SpringExpand(
          key: const ValueKey('ledger-gantt'),
          open: _pinned,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: LedgerGantt(
                steps: widget.steps, rows: widget.rows, total: _elapsed()),
          ),
        ),
      ],
    );
  }
}
