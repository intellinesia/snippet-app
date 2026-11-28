// The phone activity sheet: a run as 48px rows with icon tiles, and one step
// opened as a page with Prev / Copy / Open / Next at the thumb.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion_routes.dart';
import '../api.dart' show DaemonClient;
import '../media_views.dart' show DaemonScope, ImageThumb;
import '../platform.dart';
import '../morph_sheet.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../tool_sheet.dart' show ToolBatch;
import '../tool_views.dart';
import '../transcript.dart' show TerminalBlock, isLookupStep, isSearchStep;
import '../widgets.dart';
import 'activity_dock.dart';
import 'tool_call_row.dart';
import '../mobile_kit/controls.dart'
    show MkFilter, MkFilterGroup, MkIconButton, MkPill;
import '../mobile_kit/chrome.dart' show MkPage;
import '../mobile_kit/lists.dart' show MkGroup, MkGroupRow;
import '../mobile_kit/tokens.dart' show kAndroidLook;
import '../tap_detector.dart';

Future<void> showActivitySheet(
  BuildContext context, {
  required DaemonClient client,
  required ValueListenable<ToolBatch> batch,
  int? initial,
  DateTime? startedAt,
  Duration? took,
  void Function(String path)? onOpenFile,
}) {
  return showSpringSheet<void>(context, builder: (ctx, scroll) {
    final h = math.min(MediaQuery.of(ctx).size.height * 0.78, 640.0);
    return Material(
      type: MaterialType.transparency,
      child: AppSheetSurface(
        // The sheet sits above the page's scope; images need the client.
        child: DaemonScope(
          client: client,
          // Sized to the run, up to the cap; no dead space under short runs.
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: h),
            child: ActivitySheet(
              batch: batch,
              scroll: scroll,
              initial: initial,
              startedAt: startedAt,
              took: took,
              onOpenFile: onOpenFile,
            ),
          ),
        ),
      ),
    );
  });
}

class ActivitySheet extends StatefulWidget {
  const ActivitySheet({
    super.key,
    required this.batch,
    required this.scroll,
    this.initial,
    this.startedAt,
    this.took,
    this.onOpenFile,
  });

  final ValueListenable<ToolBatch> batch;
  final ScrollController scroll;
  final int? initial;
  final DateTime? startedAt;
  final Duration? took;
  final void Function(String path)? onOpenFile;

  @override
  State<ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<ActivitySheet> {
  int? _open;
  bool _forward = true;
  final Set<int> _expanded = {};
  String _kind = 'all';

  @override
  void initState() {
    super.initState();
    _open = widget.initial;
  }

  void _show(int? i) => setState(() {
        _forward = i != null;
        _open = i;
      });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ToolBatch>(
      valueListenable: widget.batch,
      builder: (context, batch, _) {
        final steps = batch.steps;
        final open = _open != null && _open! < steps.length ? _open : null;
        return PopScope(
          canPop: open == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _show(null);
          },
          child: AnimatedSwitcher(
            duration: Motion.base,
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            transitionBuilder: (child, a) {
              final incoming = child.key == ValueKey(open ?? -1);
              final dx = _forward == incoming ? 0.12 : -0.12;
              return FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position:
                      Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a),
                  child: child,
                ),
              );
            },
            child: open == null
                ? _ListPage(
                    key: const ValueKey(-1),
                    batch: batch,
                    scroll: widget.scroll,
                    startedAt: widget.startedAt,
                    took: widget.took,
                    expanded: _expanded,
                    onToggle: (i) => setState(() => _expanded.contains(i)
                        ? _expanded.remove(i)
                        : _expanded.add(i)),
                    onOpen: _show,
                    kind: _kind,
                    onKind: (k) => setState(() => _kind = k),
                  )
                : _DetailPage(
                    key: ValueKey(open),
                    steps: steps,
                    index: open,
                    onBack: () => _show(null),
                    onGo: _show,
                    onOpenFile: widget.onOpenFile,
                  ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

class _Entry {
  const _Entry(this.indexes, this.kind);
  final List<int> indexes;
  final String kind; // step | explore | edit
}

List<_Entry> _entries(List<ToolStep> steps) {
  final out = <_Entry>[];
  var i = 0;
  while (i < steps.length) {
    final lookup = isLookupStep(steps[i]);
    final edit = toolBaseName(steps[i].tool) == 'change_files';
    if (!lookup && !edit) {
      out.add(_Entry([i], 'step'));
      i++;
      continue;
    }
    var j = i;
    while (j < steps.length &&
        (lookup
            ? isLookupStep(steps[j])
            : toolBaseName(steps[j].tool) == 'change_files')) {
      j++;
    }
    final run = [for (var k = i; k < j; k++) k];
    if (run.length >= 2) {
      out.add(_Entry(run, lookup ? 'explore' : 'edit'));
    } else {
      out.add(_Entry(run, 'step'));
    }
    i = j;
  }
  return out;
}

class _ListPage extends StatelessWidget {
  const _ListPage({
    super.key,
    required this.batch,
    required this.scroll,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
    this.startedAt,
    this.took,
    this.kind = 'all',
    this.onKind,
  });

  final String kind;
  final ValueChanged<String>? onKind;
  final ToolBatch batch;
  final ScrollController scroll;
  final Set<int> expanded;
  final void Function(int first) onToggle;
  final void Function(int index) onOpen;
  final DateTime? startedAt;
  final Duration? took;

  @override
  Widget build(BuildContext context) {
    final steps = batch.steps;
    final rows = <Widget>[];
    for (final e in _entries(steps)) {
      if (e.kind == 'step') {
        final i = e.indexes.first;
        rows.add(_StepRow(step: steps[i], onTap: () => onOpen(i)));
        continue;
      }
      final group = [for (final i in e.indexes) steps[i]];
      final open = expanded.contains(e.indexes.first);
      rows.add(_GroupRow(
        steps: group,
        edit: e.kind == 'edit',
        open: open,
        onTap: () => onToggle(e.indexes.first),
      ));
      if (open) {
        for (final i in e.indexes) {
          rows.add(
              _StepRow(step: steps[i], indent: 24, onTap: () => onOpen(i)));
        }
      }
    }
    final t = took ?? stepsDuration(steps);
    if (!kMobile) {
      final state = batch.running ? 'Running' : 'Done';
      final meta = [
        state,
        '${steps.length} ${steps.length == 1 ? 'step' : 'steps'}',
        if (t != null) formatWorkDuration(t),
      ].join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Text('Activity',
                    style: sans(13, weight: W.label, color: AppColors.fg1)),
                const Spacer(),
                Text(meta, style: mono(11, color: AppColors.fg3)),
              ]),
            ),
          ),
          Container(height: 1, color: AppColors.line),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              children: rows,
            ),
          ),
        ],
      );
    }
    final a = kAndroidLook;
    final counts = <String, int>{};
    for (final st in steps) {
      counts.update(_kindOf(st), (n) => n + 1, ifAbsent: () => 1);
    }
    final filter = counts.length >= 2 && steps.length >= 4;
    final shown = !filter || kind == 'all'
        ? rows
        : <Widget>[
            for (var i = 0; i < steps.length; i++)
              if (_kindOf(steps[i]) == kind)
                _StepRow(step: steps[i], onTap: () => onOpen(i)),
          ];
    final pad = a ? 20.0 : 16.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, filter ? 4 : 12),
          child: Column(
              crossAxisAlignment:
                  a ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text('Activity',
                      style: a
                          ? sans(22, weight: W.label, color: AppColors.fg1)
                          : sans(17,
                              weight: FontWeight.w600, color: AppColors.fg1)),
                ),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (batch.running) ...[
                    Spinner(size: 12, color: AppColors.fg2),
                    const SizedBox(width: 8),
                  ],
                  if (batch.running && startedAt != null)
                    _RunClock(startedAt!, steps: steps.length)
                  else
                    Text(
                        [
                          batch.running ? 'Running' : 'Done',
                          '${steps.length} ${steps.length == 1 ? 'step' : 'steps'}',
                          if (t != null) formatWorkDuration(t),
                        ].join(' · '),
                        style: sans(13.5, color: AppColors.fg3, tabular: true)),
                ]),
              ]),
        ),
        if (filter)
          MkFilterGroup<String>(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            options: [
              MkFilter('all', 'All', count: steps.length),
              for (final k in _kindOrder)
                if (counts[k] != null)
                  MkFilter(k, _kindLabel[k]!, count: counts[k]),
            ],
            selected: counts.containsKey(kind) ? kind : 'all',
            onSelect: (k) => onKind?.call(k),
          ),
        Flexible(
          child: ListView(
            controller: scroll,
            shrinkWrap: true,
            padding: EdgeInsets.only(
                bottom: 16 + MediaQuery.of(context).padding.bottom),
            children: [MkGroup(children: shown)],
          ),
        ),
      ],
    );
  }
}

const _kindOrder = ['cmd', 'read', 'edit', 'other'];
const _kindLabel = {
  'cmd': 'Commands',
  'read': 'Reading',
  'edit': 'Edits',
  'other': 'Other',
};

String _kindOf(ToolStep s) {
  final n = toolBaseName(s.tool);
  if (n == 'bash') return 'cmd';
  if (n == 'change_files') return 'edit';
  if (isLookupStep(s) || n == 'view_image' || n == 'present_file') {
    return 'read';
  }
  return 'other';
}

/// The kit's tonal well: a 40 circle on Android, a 30 tile on iPhone.
Widget _well({required Widget child, bool clip = false}) {
  final a = kAndroidLook;
  final d = a ? 40.0 : 30.0;
  return Container(
    width: d,
    height: d,
    clipBehavior: clip ? Clip.antiAlias : Clip.none,
    decoration: BoxDecoration(
      color: AppColors.surface3,
      shape: a ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: a ? null : BorderRadius.circular(9),
    ),
    child: Center(child: child),
  );
}

/// The command without its setup (cd, export, ulimit), first line only.
String _coreCommand(String raw) {
  final line = raw.trim().split('\n').first.trim();
  final parts = line
      .split(RegExp(r'\s*(?:;|&&)\s*'))
      .where((p) => p.isNotEmpty)
      .toList();
  final setup = RegExp(r'^(?:(?:cd|export|ulimit|source|set)\s|[A-Za-z_]\w*=)');
  final core = parts.where((p) => !setup.hasMatch(p)).toList();
  return (core.isEmpty ? parts : core).join('; ');
}

/// The second line of a step row: the command or the path it touched.
String? _stepSub(ToolStep s, String title) {
  if (s.failed || stepFailedOut(s)) {
    final e = _errorLines(s);
    if (e.isNotEmpty) return e.first.trim();
  }
  if (toolBaseName(s.tool) == 'bash') {
    final a = s.args is Map ? s.args as Map : const {};
    final c = _coreCommand((a['command'] ?? '').toString());
    return c.isEmpty ? null : c;
  }
  final t = stepTarget(s);
  if (t.isEmpty || title.contains(t.split('/').last)) return null;
  return t;
}

class _RunClock extends StatefulWidget {
  const _RunClock(this.startedAt, {this.steps = 0});
  final DateTime startedAt;
  final int steps;

  @override
  State<_RunClock> createState() => _RunClockState();
}

class _RunClockState extends State<_RunClock> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = DateTime.now().difference(widget.startedAt).inSeconds;
    final n = widget.steps;
    return Text(
        [
          'Running',
          if (n > 0) '$n ${n == 1 ? 'step' : 'steps'}',
          formatWorkDuration(Duration(seconds: s < 0 ? 0 : s)),
        ].join(' · '),
        style: sans(13, color: AppColors.fg3, tabular: true));
  }
}

enum _Tone { neutral, ok, bad, run }

(Color bg, Color fg) _toneColors(_Tone t) => switch (t) {
      _Tone.ok => (AppColors.okBg, AppColors.ok),
      _Tone.bad => (AppColors.surface3, AppColors.fg2),
      _Tone.run => (AppColors.surface3, AppColors.fg2),
      _Tone.neutral => (AppColors.surface3, AppColors.fg2),
    };

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.tone = _Tone.neutral});
  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _toneColors(tone);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Center(
        widthFactor: 1,
        child: Text(text,
            style: sans(13, weight: W.label, color: fg, tabular: true)),
      ),
    );
  }
}

_Tone _stepTone(ToolStep s) {
  if (s.running) return _Tone.run;
  if (stepFailedOut(s)) return _Tone.bad;
  if (stepChip(s)?.tone == StepChipTone.ok) return _Tone.ok;
  return _Tone.neutral;
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.tone);
  final String icon;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    // Quiet rows: an 18pt fg2 icon, no tinted tile; state is told in words.
    return SizedBox.square(
      dimension: 24,
      child: Center(child: AppIcon(icon, size: 20, color: AppColors.fg2)),
    );
  }
}

String _argLabel(ToolStep s) {
  final a = s.args is Map ? s.args as Map : const {};
  return (a['label'] ?? '').toString().trim();
}

String stepTitle(ToolStep s) {
  if (s.running) return liveStepText(s);
  if (toolBaseName(s.tool) == 'bash') {
    final label = _argLabel(s);
    if (label.isNotEmpty) return label;
    final c = stepCommand(s);
    return c != null ? 'Ran ${c.label}' : 'Ran a command';
  }
  if (toolBaseName(s.tool) == 'delegate_task') {
    final a = s.args is Map ? s.args as Map : const {};
    final what = (a['title'] ?? a['description'] ?? '').toString().trim();
    if (what.isNotEmpty) return 'Delegated $what';
  }
  return toolSentence(s);
}

List<String> _errorLines(ToolStep s) {
  final d = s.data;
  var text = (d?['stderr'] ?? '').toString();
  final err = s.result is Map ? (s.result as Map)['error'] : null;
  if (text.trim().isEmpty && err is Map) {
    text = (err['message'] ?? '').toString();
  }
  if (text.trim().isEmpty) text = s.stdout;
  final lines = text
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty)
      .toList();
  final errors = lines
      .where((l) =>
          RegExp(r'^\s*(error|fatal|panic|fail)', caseSensitive: false)
              .hasMatch(l))
      .toList();
  if (errors.isNotEmpty) return errors.take(2).toList();
  final hits = lines.where(errorLineMarker.hasMatch).toList();
  if (hits.isNotEmpty) return hits.take(2).toList();
  return lines.length > 2 ? lines.sublist(lines.length - 2) : lines;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.onTap, this.indent = 0});
  final ToolStep step;
  final VoidCallback onTap;
  final double indent;

  /// An image step shows its picture in place of the icon.
  Widget _leading(BuildContext context) {
    final client = DaemonScope.maybeOf(context);
    final name = toolBaseName(step.tool);
    if (client != null &&
        (name == 'view_image' || name == 'present_file') &&
        !step.running &&
        !step.failed) {
      final a = step.args is Map ? step.args as Map : const {};
      final path = (step.data?['path'] ?? a['path'] ?? '').toString().trim();
      final ext = path.split('.').last.toLowerCase();
      if (path.startsWith('/') &&
          const {'png', 'jpg', 'jpeg', 'gif', 'webp'}.contains(ext)) {
        final d = kAndroidLook ? 40.0 : 30.0;
        return _well(
            clip: true,
            child: ImageThumb(client: client, path: path, width: d, height: d));
      }
    }
    if (!kMobile) return _Tile(toolIcon(step.tool), _stepTone(step));
    if (step.running) {
      return _well(child: Spinner(size: 16, color: AppColors.fg2));
    }
    if (_stepTone(step) == _Tone.bad) {
      return _well(
          child: AppIcon('alert-triangle', size: 18, color: AppColors.fg1));
    }
    return _well(
        child: AppIcon(toolIcon(step.tool),
            size: kAndroidLook ? 19 : 17, color: AppColors.fg2));
  }

  @override
  Widget build(BuildContext context) {
    if (!kMobile) {
      return Padding(
        padding: EdgeInsets.only(left: indent, top: 2),
        child: ToolCallRow(
          step: step,
          onTap: onTap,
          filled: false,
          showChevron: true,
        ),
      );
    }
    final tone = _stepTone(step);
    final chip = stepChip(step);
    final failed = tone == _Tone.bad;
    final title = stepTitle(step);
    Widget? meta;
    if (failed) {
      meta = Text('Failed',
          style: sans(13.5, weight: W.label, color: AppColors.fg1));
    } else if (step.running) {
      meta = null;
    } else if (chip != null && (chip.added > 0 || chip.removed > 0)) {
      meta = _diffStat(chip.added, chip.removed);
    } else {
      final d = stepDuration(step);
      final last = chip?.text.split(' · ').last;
      final text = d ?? (last == 'ok' ? null : last);
      if (text != null && text.isNotEmpty) {
        meta = Text(text, style: sans(13, color: AppColors.fg3, tabular: true));
      }
    }
    final sub = _stepSub(step, title);
    final cmd = toolBaseName(step.tool) == 'bash' || sub == stepTarget(step);
    final row = MkGroupRow(
      leading: indent > 0 ? _childMark(step) : _leading(context),
      label: title,
      subtitle: step.running && sub == null ? 'Running' : sub,
      subtitleMono: sub != null && cmd && !failed,
      chevron: false,
      trailing: meta,
      onTap: onTap,
    );
    return row;
  }

  /// A child of a group row: a bare glyph in the well's column.
  Widget _childMark(ToolStep s) => SizedBox(
        width: kAndroidLook ? 40 : 30,
        child: Center(
          child: s.running
              ? Spinner(size: 14, color: AppColors.fg2)
              : AppIcon(toolIcon(s.tool), size: 16, color: AppColors.fg3),
        ),
      );
}

Widget _diffStat(int added, int removed) => Text.rich(
    TextSpan(children: [
      TextSpan(text: '+$added', style: TextStyle(color: AppColors.ok)),
      TextSpan(text: ' −$removed', style: TextStyle(color: AppColors.fg2)),
    ]),
    style: sans(13, tabular: true));

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.steps,
    required this.edit,
    required this.open,
    required this.onTap,
  });

  final List<ToolStep> steps;
  final bool edit;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = steps.any((s) => s.running);
    String title;
    String sub;
    Widget? meta;
    if (edit) {
      final files = fileChanges(steps);
      final added = files.fold<int>(0, (n, c) => n + c.added);
      final removed = files.fold<int>(0, (n, c) => n + c.removed);
      title = live
          ? 'Editing ${files.length} files'
          : 'Edited ${files.length} files';
      sub = files.map((c) => c.path.split('/').last).join(', ');
      if (added + removed > 0) meta = _diffStat(added, removed);
    } else {
      final searches = steps.where(isSearchStep).length;
      final fileCount = steps.length - searches;
      title = live ? 'Exploring' : 'Explored';
      sub = [
        if (fileCount > 0) '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
        if (searches > 0) '$searches ${searches == 1 ? 'search' : 'searches'}',
      ].join(', ');
    }
    if (!kMobile) {
      return TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
            child: Row(children: [
              SizedBox(
                width: 14,
                height: 14,
                child: Center(
                  child: live
                      ? Spinner(size: 13, color: AppColors.fg2)
                      : AppIcon('check', size: 13, color: AppColors.fg3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: title,
                        style: TextStyle(
                            color: live ? AppColors.fg1 : AppColors.fg2)),
                    if (sub.isNotEmpty)
                      TextSpan(
                          text: ' $sub',
                          style: TextStyle(color: AppColors.fg3)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12),
                ),
              ),
              if (meta != null) ...[
                const SizedBox(width: 10),
                DefaultTextStyle(
                  style: mono(11, color: AppColors.fg3),
                  child: meta,
                ),
              ],
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: Motion.fast,
                child: AppIcon('chevron-right', size: 12, color: AppColors.fg3),
              ),
            ]),
          ),
        ),
      );
    }
    return MkGroupRow(
      leading: _well(
          child: live
              ? Spinner(size: 16, color: AppColors.fg2)
              : AppIcon(edit ? 'edit' : 'layers',
                  size: kAndroidLook ? 19 : 17, color: AppColors.fg2)),
      label: title,
      subtitle: sub.isEmpty ? null : sub,
      chevron: false,
      onTap: onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (meta != null) ...[meta, const SizedBox(width: 8)],
        AnimatedRotation(
          turns: open ? 0.5 : 0,
          duration: Motion.fast,
          child: AppIcon('chevron-down', size: 18, color: AppColors.fg3),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail
// ---------------------------------------------------------------------------

String _copyText(ToolStep s) {
  final a = s.args is Map ? s.args as Map : const {};
  final d = s.data;
  if (toolBaseName(s.tool) == 'bash') {
    return [
      (a['command'] ?? '').toString(),
      s.stdout,
      (d?['stderr'] ?? '').toString(),
    ].where((p) => p.trim().isNotEmpty).join('\n');
  }
  if (toolBaseName(s.tool) == 'change_files') {
    return [for (final c in s.changes) (c['path'] ?? '').toString()].join('\n');
  }
  return toolSentence(s);
}

class _DetailPage extends StatelessWidget {
  const _DetailPage({
    super.key,
    required this.steps,
    required this.index,
    required this.onBack,
    required this.onGo,
    this.onOpenFile,
  });

  final List<ToolStep> steps;
  final int index;
  final VoidCallback onBack;
  final void Function(int index) onGo;
  final void Function(String path)? onOpenFile;

  Widget _body(BuildContext context, ToolStep step) {
    if (kMobile && toolBaseName(step.tool) == 'bash') {
      return TerminalBlock(
          step: step,
          commandLines: 3,
          outputCap: 14,
          tail: step.running,
          size: 13);
    }
    final detail = safeToolDetailView(context,
        tool: step.tool, args: step.args, result: step.result);
    if (kMobile) return detail;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: detail,
    );
  }

  void _openFull(BuildContext context, ToolStep step) {
    if (kMobile) {
      Navigator.of(context).push(AppPageRoute<void>(
        builder: (ctx) => Material(
          color: AppColors.bg,
          child: MkPage(
            title: stepTitle(step),
            onBack: () => Navigator.of(ctx).maybePop(),
            bottomClearance: false,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, 24 + MediaQuery.of(ctx).padding.bottom),
                sliver: SliverToBoxAdapter(
                  child: toolBaseName(step.tool) == 'bash'
                      ? TerminalBlock(step: step, outputCap: 100000, size: 13)
                      : _body(ctx, step),
                ),
              ),
            ],
          ),
        ),
      ));
      return;
    }
    Navigator.of(context).push(AppPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                _RoundButton(
                    icon: 'chevron-left',
                    onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(stepTitle(step),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            sans(17, weight: W.title, color: AppColors.fg1))),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: kMobile && toolBaseName(step.tool) == 'bash'
                    ? TerminalBlock(step: step, outputCap: 100000, size: 13)
                    : _body(context, step),
              ),
            ),
          ]),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final step = steps[index];
    final tone = _stepTone(step);
    final chip = stepChip(step);
    final files = toolBaseName(step.tool) == 'change_files'
        ? fileChanges([step])
        : const <FileChange>[];
    final added = files.fold<int>(0, (n, c) => n + c.added);
    final removed = files.fold<int>(0, (n, c) => n + c.removed);
    final dur = stepDuration(step);
    final single = files.length == 1 ? files.first.path : null;
    final canOpenFile = single != null && onOpenFile != null;
    if (kMobile) {
      final a = kAndroidLook;
      final meta = [
        if (step.running) 'Running',
        if (tone == _Tone.bad)
          chip != null ? chip.text.split(' · ').last : 'Failed',
        if (added + removed > 0) '+$added −$removed',
        if (dur != null) dur,
      ].join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 20, 8),
            child: Row(children: [
              MkIconButton(
                  icon: a ? 'arrow-left' : 'chevron-left',
                  label: 'Back',
                  bare: true,
                  onTap: onBack),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(stepTitle(step),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(17,
                            weight: a ? W.label : FontWeight.w600,
                            color: AppColors.fg1)),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(meta,
                            style: sans(13.5,
                                color: AppColors.fg3, tabular: true)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('${index + 1} of ${steps.length}',
                  style: sans(13, color: AppColors.fg3, tabular: true)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _body(context, step),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, 8 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              _NavButton(
                  icon: 'chevron-left',
                  enabled: index > 0,
                  onTap: () => onGo(index - 1)),
              const SizedBox(width: 8),
              Expanded(
                child: MkPill('Copy', icon: 'copy', expand: true, onTap: () {
                  HapticFeedback.selectionClick();
                  Clipboard.setData(ClipboardData(text: _copyText(step)));
                  toast(context, 'Copied');
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MkPill('Open',
                    icon: canOpenFile ? 'file-text' : 'expand',
                    expand: true,
                    onTap: () => canOpenFile
                        ? onOpenFile!(single)
                        : _openFull(context, step)),
              ),
              const SizedBox(width: 8),
              _NavButton(
                  icon: 'chevron-right',
                  enabled: index < steps.length - 1,
                  onTap: () => onGo(index + 1)),
            ]),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(children: [
            _RoundButton(
                icon: 'chevron-left', onTap: onBack, size: kMobile ? 40 : 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stepTitle(step),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(17, weight: W.title, color: AppColors.fg1)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('${index + 1} of ${steps.length}',
                style: mono(kMobile ? 13 : 11, color: AppColors.fg3)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (added > 0) _Pill('+$added', tone: _Tone.ok),
            if (removed > 0) _Pill('−$removed', tone: _Tone.bad),
            if (step.running)
              Text('Running', style: sans(13, color: AppColors.fg2)),
            if (tone == _Tone.bad && chip != null)
              _Pill(chip.text.split(' · ').last, tone: _Tone.bad),
            if (dur != null) _Pill(dur),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: _body(context, step),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          child: Row(children: [
            _NavButton(
                icon: 'chevron-left',
                enabled: index > 0,
                onTap: () => onGo(index - 1)),
            const SizedBox(width: 10),
            Expanded(
              child: _WideButton(
                  icon: 'copy',
                  label: 'Copy',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(ClipboardData(text: _copyText(step)));
                    toast(context, 'Copied');
                  }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _WideButton(
                  icon: 'expand',
                  label: canOpenFile ? 'Open file' : 'Open full',
                  onTap: () => canOpenFile
                      ? onOpenFile!(single)
                      : _openFull(context, step)),
            ),
            const SizedBox(width: 10),
            _NavButton(
                icon: 'chevron-right',
                enabled: index < steps.length - 1,
                onTap: () => onGo(index + 1)),
          ]),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.size = 44});
  final String icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border2)),
          child: AppIcon(icon, size: 18, color: AppColors.fg2),
        ),
      );
}

class _NavButton extends StatelessWidget {
  const _NavButton(
      {required this.icon, required this.enabled, required this.onTap});
  final String icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: kMobile ? 48 : 28,
            height: kMobile ? 48 : 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(kMobile ? 24 : 6)),
            child: AppIcon(icon, size: kMobile ? 18 : 13, color: AppColors.fg1),
          ),
        ),
      );
}

class _WideButton extends StatelessWidget {
  const _WideButton(
      {required this.icon, required this.label, required this.onTap});
  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: kMobile ? 44 : 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(kMobile ? 22 : 6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon, size: kMobile ? 18 : 13, color: AppColors.fg1),
            SizedBox(width: kMobile ? 8 : 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 15 : 12,
                      weight: W.label, color: AppColors.fg1)),
            ),
          ]),
        ),
      );
}
