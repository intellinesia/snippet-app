// "Ledger line": desktop tool activity as one sentence of hoverable phrases
// while finished, and a single 40px strip while a step is running.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent_character.dart' show AgentCharacterState;
import '../mochi.dart' show AgentMochi;

import '../theme.dart';
import '../tool_activity.dart';
import '../transcript.dart';
import '../widgets.dart';

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
    case 'search_content' || 'grep_search' || 'find_by_name' || 'glob' || 'list_dir':
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
      if (n == 1 && paths.length == 1) return 'searched ${_base(paths.single!)}';
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
      final tests = steps
          .where((s) => stepCommand(s)?.kind == CommandKind.test)
          .length;
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

  // Kept after closing so the collapse animates the rows it was showing.
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final phrases = ledgerPhrases(widget.steps);
    final bad = widget.steps.any(_stepFailed);
    final took = widget.took ?? stepsDuration(widget.steps);
    final base = sans(13, height: 1.45, color: AppColors.fg3, tabular: true);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.only(top: 3, right: 8),
                child: bad
                    ? AppIcon('x', size: 14, color: AppColors.danger)
                    : AppIcon('check', size: 14, color: AppColors.ok),
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Text(formatWorkDuration(took),
                      style: mono(12, color: AppColors.fg4)),
                ),
              ),
          ],
        ),
        SpringExpand(
          open: widget.open,
          child: WorkSteps(rows: widget.allRows ?? widget.rows),
        ),
        SpringExpand(
          open: _phrase != null && !widget.open,
          child: shown == null
              ? const SizedBox.shrink()
              : WorkSteps(rows: [
                  for (final k in shown.indices) widget.rows[k],
                ]),
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
    if (_hover == v) return;
    setState(() => _hover = v);
    v ? _portal.show() : _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.phrase;
    final on = _hover || widget.active;
    final tone = on ? AppColors.accent : AppColors.fg2;
    final deco = TextDecoration.underline;
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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: p.text,
                style: widget.style.copyWith(
                  color: tone,
                  decoration: deco,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: on ? AppColors.accent : AppColors.fg4,
                ),
              ),
              if (p.failNote != null)
                TextSpan(
                    text: ' ${p.failNote}',
                    style: widget.style.copyWith(color: AppColors.danger)),
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
          borderRadius: BorderRadius.circular(10),
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
                      style: sans(12, color: AppColors.fg4)),
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
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [
          AppIcon(_iconFor(_kindOf(step).$1),
              size: 13, color: bad ? AppColors.danger : AppColors.fg3),
          const SizedBox(width: 8),
          Flexible(
            child: Text(target.isEmpty ? liveStepText(step) : target,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: mono(12, color: bad ? AppColors.danger : AppColors.fg2)),
          ),
          if (meta != null) ...[
            const SizedBox(width: 12),
            Text(meta, style: sans(12, color: AppColors.fg4)),
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
    (d?['stdout'] ?? d?['output'] ?? '').toString(),
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

/// Running run: one 40px strip with the mascot, what is happening in words,
/// the command, a step bar sized by time, elapsed time, Peek and Stop. The
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
    if (_pinned) {
      setState(() => _pinned = false);
      return;
    }
    _portal.isShowing ? _portal.hide() : _portal.show();
    setState(() {});
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Seconds each step took, the running one up to now; equal when unstamped.
  List<double> _weights() => [
        for (final s in widget.steps)
          s.startMs == null
              ? 1.0
              : (((s.endMs ?? _now) - s.startMs!) / 1000).clamp(0.4, 1e6),
      ];

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

  Widget _bar({int? failAt}) {
    final w = _weights();
    final steps = widget.steps;
    return SizedBox(
      width: 132,
      height: 6,
      child: Row(children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            flex: (w[i] * 10).round().clamp(1, 1 << 20),
            child: Container(
              decoration: BoxDecoration(
                color: _stepFailed(steps[i]) || i == failAt
                    ? AppColors.danger
                    : steps[i].running
                        ? AppColors.accent
                        : AppColors.fg4.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _key(String k) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.fg1.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(k, style: mono(10.5, color: AppColors.fg4)),
      );

  Widget _btn(String icon, String label, String key, VoidCallback? onTap,
          {bool filled = false}) =>
      HoverSurface(
        radius: 8,
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: filled
              ? BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(8))
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
          _portal.hide();
          setState(() {});
        },
        child: Container(
          width: 470,
          constraints: const BoxConstraints(maxHeight: 340),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
              child: Row(children: [
                AppIcon('eye', size: 12, color: AppColors.fg4),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('Steps so far',
                        style: sans(11.5, color: AppColors.fg4))),
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
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: WorkSteps(rows: widget.rows, header: false),
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
    live ??= steps.isEmpty ? null : steps.last;
    var failAt = -1;
    for (var i = steps.length - 1; i >= 0; i--) {
      if (!steps[i].running && _stepFailed(steps[i])) {
        failAt = i;
        break;
      }
    }
    final fail = failAt >= 0 && failAt != _dismissedFail ? steps[failAt] : null;
    final label = live == null ? 'Working' : ledgerLiveLabel(live);
    final target = live == null ? '' : stepTarget(live);
    final el = _elapsed();
    final agent = scope?.agentId;
    final peekOpen = _portal.isShowing || _pinned;

    final strip = Container(
      height: 40,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        SizedBox(
          width: 18,
          height: 18,
          child: agent == null
              ? Center(child: RunSpinner(size: 12, color: AppColors.accent))
              : AgentMochi(agent,
                  size: 18, state: AgentCharacterState.working),
        ),
        const SizedBox(width: 10),
        Text(label,
            maxLines: 1,
            softWrap: false,
            style: sans(13, weight: W.label, color: AppColors.fg1)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(target,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: mono(12, color: AppColors.fg3)),
        ),
        const SizedBox(width: 10),
        if (steps.isNotEmpty) ...[_bar(), const SizedBox(width: 10)],
        if (el != null) ...[
          Text(_clock(el), style: mono(12, color: AppColors.fg3)),
          const SizedBox(width: 8),
        ],
        CompositedTransformTarget(
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
              child: _btn('eye', 'Peek', 'Space', _togglePeek,
                  filled: peekOpen),
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
        if (fail != null) ...[
          Container(
            height: 40,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              AppIcon('alert-circle', size: 16, color: AppColors.danger),
              const SizedBox(width: 10),
              Text(_failLabel(fail),
                  style: sans(13, weight: W.label, color: AppColors.danger)),
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
              const SizedBox(width: 10),
              _bar(failAt: failAt),
              if (fail.startMs != null && fail.endMs != null) ...[
                const SizedBox(width: 10),
                Text(
                    _clock(Duration(
                        milliseconds: fail.endMs! - fail.startMs!)),
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
          if (_tail(fail).isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_tail(fail).join('\n'),
                  style: mono(12, color: AppColors.fg3)),
            ),
          const SizedBox(height: 6),
        ],
        strip,
        SpringExpand(
          open: _pinned,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: WorkSteps(rows: widget.rows, header: false),
          ),
        ),
      ],
    );
  }
}
