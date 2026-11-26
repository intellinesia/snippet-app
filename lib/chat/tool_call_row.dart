import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../tool_views.dart';
import '../widgets.dart';
import '../tap_detector.dart';

/// Desktop TC row anatomy shared by the transcript seam, activity sheet and
/// tests. Lane C2 owns this additive API; the transcript core can adopt it
/// without duplicating the section-0/TC geometry.
///
/// Geometry is locked on desktop: s1 fill, radius 7, a 28–32pt row, state
/// icon centred at x+14, label at x+32 and mono meta at the right. Phone uses
/// the v19 row: s1 fill, radius 6, 48pt high, the same icon/text seam and
/// mono 12.5 target/meta.
class ToolCallRow extends StatelessWidget {
  const ToolCallRow({
    super.key,
    required this.step,
    this.onTap,
    this.open = false,
    this.filled = true,
    this.showChevron = false,
    this.padding,
  });

  final ToolStep step;
  final VoidCallback? onTap;
  final bool open;
  final bool filled;
  final bool showChevron;
  final EdgeInsetsGeometry? padding;

  static bool failed(ToolStep step) => step.failed || verifyOutputFailed(step);

  static Widget stateIcon(ToolStep step, {String? kindIcon}) {
    if (step.running) {
      return Spinner(size: 13, color: AppColors.fg2);
    }
    if (failed(step)) {
      return AppIcon('x', size: 14, color: AppColors.fg1);
    }
    if (step.result != null) {
      return AppIcon('check', size: 13, color: AppColors.fg3);
    }
    return AppIcon(kindIcon ?? toolIcon(step.tool),
        size: 13, color: AppColors.fg2);
  }

  static bool _monoSubject(ToolStep step) => switch (toolBaseName(step.tool)) {
        'bash' ||
        'read_file' ||
        'view_file' ||
        'list_dir' ||
        'search_content' ||
        'grep_search' ||
        'find_by_name' ||
        'glob' ||
        'change_files' ||
        'view_image' ||
        'present_file' ||
        'manage_process' ||
        'monitor' =>
          true,
        _ when isCanvasTool(step.tool) || isGitTool(step.tool) => true,
        _ => false,
      };

  static InlineSpan titleSpan(ToolStep step) {
    final running = step.running;
    final bad = failed(step);
    final (verb, object) = toolSentenceParts(step, running: running);
    final verbColor = running || bad ? AppColors.fg1 : AppColors.fg2;
    return TextSpan(children: [
      TextSpan(text: verb, style: TextStyle(color: verbColor)),
      if (object.isNotEmpty)
        TextSpan(
          text: ' $object',
          style: _monoSubject(step)
              ? mono(kMobile ? 12.5 : 12,
                  color: kMobile || running || bad ? AppColors.fg1 : AppColors.fg2)
              : TextStyle(color: running || bad ? AppColors.fg1 : AppColors.fg2),
        ),
    ]);
  }

  static List<String> metaParts(ToolStep step) {
    final out = <String>[];
    final chip = stepChip(step);
    if (chip != null && (chip.added > 0 || chip.removed > 0)) {
      out.add('+${chip.added} −${chip.removed}');
    } else {
      out.addAll(toolMetaParts(step));
      if (chip != null &&
          chip.text.isNotEmpty &&
          chip.tone != StepChipTone.ok) {
        // Keep the useful failure count ("2 failed") without repeating the
        // exit code already supplied by toolMetaParts.
        final failureCount =
            RegExp(r'\d+ failed').firstMatch(chip.text)?.group(0);
        final extra =
            failureCount ?? (chip.text.startsWith('failed') ? '' : chip.text);
        if (extra.isNotEmpty && !out.any((p) => p.contains(extra))) {
          out.add(extra);
        }
      }
    }
    final took = stepDuration(step);
    if (took != null && !out.any((p) => p == took)) out.add(took);
    if (out.isEmpty && chip != null && chip.text.isNotEmpty) out.add(chip.text);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = !kMobile;
    final radius = BorderRadius.circular(desktop ? 7 : 6);
    final meta = metaParts(step);
    final child = Container(
      constraints: BoxConstraints(minHeight: desktop ? 28 : 48),
      padding: padding ??
          EdgeInsets.fromLTRB(desktop ? 10 : 7, 0, desktop ? 8 : 8, 0),
      child: Row(children: [
        SizedBox(
          width: desktop ? 14 : 18,
          height: desktop ? 14 : 18,
          child: Center(child: stateIcon(step)),
        ),
        SizedBox(width: desktop ? 8 : 7),
        Expanded(
          child: Text.rich(
            titleSpan(step),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(desktop ? 12 : 14,
                height: desktop ? 17 / 12 : 18.9 / 14),
          ),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            flex: 0,
            child: Text(
              meta.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(desktop ? 11 : 12.5, color: AppColors.fg3),
            ),
          ),
        ],
        if (showChevron) ...[
          SizedBox(width: desktop ? 6 : 8),
          AnimatedRotation(
            turns: open ? 0.25 : 0,
            duration: Motion.fast,
            child: AppIcon('chevron-right', size: 12, color: AppColors.fg3),
          ),
        ],
      ]),
    );
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: filled ? AppColors.surface1 : Colors.transparent,
            borderRadius: radius,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Whether a raw daemon tool name is one of the proposed canvas operations.
bool isCanvasTool(String tool) {
  final t = toolBaseName(tool);
  return t.startsWith('canvas') ||
      t == 'frame_apply' ||
      t == 'canvas_apply' ||
      t == 'canvas_ask';
}

/// Whether a raw daemon tool name is a git or pull-request operation.
bool isGitTool(String tool) {
  final t = toolBaseName(tool);
  return t.startsWith('git_') ||
      t == 'git' ||
      t == 'commit' ||
      t == 'push' ||
      t == 'pull_request' ||
      t == 'pr' ||
      t.startsWith('github_pr');
}

/// One compact result sentence for a tool sub-row.
String toolCallResultLine(ToolStep step) {
  if (step.running) return 'Running';
  if (ToolCallRow.failed(step)) return 'Failed';
  final chip = stepChip(step)?.text;
  if (chip != null && chip.isNotEmpty) return chip;
  final output = step.stdout
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (output.isNotEmpty) {
    return output.length <= 72 ? output : '${output.substring(0, 71)}…';
  }
  return 'OK';
}

/// The mono subject shown in an expanded sub-row: command for shell, path or
/// query for file/search rows, otherwise the ordinary object.
String toolCallSubject(ToolStep step) {
  final a = step.args is Map ? step.args as Map : const {};
  final name = toolBaseName(step.tool);
  if (name == 'bash') {
    final command = (a['command'] ?? '').toString().trim();
    if (command.isNotEmpty) return command.split('\n').first;
  }
  final object = toolObject(step);
  return object.isEmpty ? toolSentence(step) : object;
}

/// Expanded sub-row inside one TC surface: mono subject, muted result and a
/// right-aligned mono duration. Height stays inside the 28–30pt band.
class ToolCallSubRow extends StatelessWidget {
  const ToolCallSubRow({super.key, required this.step, this.onTap});

  final ToolStep step;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bad = ToolCallRow.failed(step);
    final duration = stepDuration(step);
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            SizedBox(
              width: 14,
              height: 14,
              child: Center(child: ToolCallRow.stateIcon(step)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                toolCallSubject(step),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(12, color: AppColors.fg1),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 0,
              child: Text(
                toolCallResultLine(step),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(11.5, color: bad ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            if (duration != null) ...[
              const SizedBox(width: 10),
              Text(duration, style: mono(11, color: AppColors.fg3)),
            ],
          ]),
        ),
      ),
    );
  }
}

String toolGroupSummary(List<ToolStep> steps, {required bool running}) {
  final commands = steps.where((s) => toolBaseName(s.tool) == 'bash').length;
  final reads = steps
      .where((s) => switch (toolBaseName(s.tool)) {
            'read_file' || 'view_file' || 'list_dir' || 'view_image' => true,
            _ => false,
          })
      .length;
  final searches = steps
      .where((s) => switch (toolBaseName(s.tool)) {
            'search_content' ||
            'grep_search' ||
            'find_by_name' ||
            'glob' =>
              true,
            _ => false,
          })
      .length;
  final edits =
      steps.where((s) => toolBaseName(s.tool) == 'change_files').length;
  final other = steps.length - commands - reads - searches - edits;
  String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  final parts = <String>[
    if (commands > 0)
      '${running ? 'Running' : 'Ran'} ${plural(commands, 'command', 'commands')}',
    if (edits > 0)
      '${running ? 'Editing' : 'Edited'} ${plural(edits, 'file', 'files')}',
    if (reads > 0)
      '${running ? 'Reading' : 'Read'} ${plural(reads, 'file', 'files')}',
    if (searches > 0)
      '${running ? 'Searching' : 'Searched'} ${plural(searches, 'place', 'places')}',
    if (other > 0)
      '${running ? 'Using' : 'Used'} ${plural(other, 'tool', 'tools')}',
  ];
  if (parts.isEmpty) return running ? 'Running tools' : 'No tool calls';
  String lowerFirst(String s) =>
      s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';
  final sentence = [
    for (var i = 0; i < parts.length; i++)
      i == 0 ? parts[i] : lowerFirst(parts[i]),
  ].join(', ');
  return sentence;
}

/// TC-01/TC-21 in one surface: a collapsed summary row, a hairline when open,
/// then flat 28–30pt sub-rows rather than nested cards.
class ToolCallGroup extends StatefulWidget {
  const ToolCallGroup({
    super.key,
    required this.steps,
    this.initiallyOpen = false,
    this.open,
    this.onOpenChanged,
    this.onOpenStep,
  });

  final List<ToolStep> steps;
  final bool initiallyOpen;
  final bool? open;
  final ValueChanged<bool>? onOpenChanged;
  final void Function(int index)? onOpenStep;

  @override
  State<ToolCallGroup> createState() => _ToolCallGroupState();
}

class _ToolCallGroupState extends State<ToolCallGroup> {
  late bool _localOpen = widget.initiallyOpen;

  bool get _open => widget.open ?? _localOpen;

  void _toggle() {
    final next = !_open;
    widget.onOpenChanged?.call(next);
    if (widget.open == null) setState(() => _localOpen = next);
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final running = steps.any((s) => s.running);
    final bad = steps.any(ToolCallRow.failed);
    final took = stepsDuration(steps);
    // ToolCallRow derives its title from one step; a group paints the same
    // geometry directly so the summary can describe every step.
    final groupHeader = TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
          child: Row(children: [
            SizedBox(
              width: 14,
              height: 14,
              child: Center(
                child: running
                    ? Spinner(size: 13, color: AppColors.fg2)
                    : AppIcon(bad ? 'x' : 'check',
                        size: bad ? 14 : 13,
                        color: bad ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                toolGroupSummary(steps, running: running),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12,
                    color: running || bad ? AppColors.fg1 : AppColors.fg2),
              ),
            ),
            if (took != null) ...[
              const SizedBox(width: 10),
              Text(formatWorkDuration(took),
                  style: mono(11, color: AppColors.fg3)),
            ],
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _open ? 0.25 : 0,
              duration: Motion.fast,
              child: AppIcon('chevron-right', size: 12, color: AppColors.fg3),
            ),
          ]),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          groupHeader,
          if (_open) ...[
            Container(height: 1, color: AppColors.line),
            for (var i = 0; i < steps.length; i++)
              ToolCallSubRow(
                step: steps[i],
                onTap: widget.onOpenStep == null
                    ? null
                    : () => widget.onOpenStep!(i),
              ),
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}
