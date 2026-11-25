import 'package:flutter/material.dart';

import '../models.dart';
import '../motion_routes.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../tap_detector.dart';
import '../widgets.dart';
import 'spec_bar.dart';

/// A page one level down from the session's Actions: back circle, title, rows.
Future<void> pushActionsSubPage(BuildContext context,
    {required String title,
    String? subtitle,
    bool padded = true,
    required Widget Function(BuildContext context, VoidCallback back) body}) {
  return Navigator.of(context).push<void>(AppPageRoute<void>(
    builder: (page) => Material(
      color: AppColors.pageBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpecBar(title: title, subtitle: subtitle),
            Expanded(
              child: SingleChildScrollView(
                padding: padded
                    ? EdgeInsets.fromLTRB(
                        Grouped.gutter, 8, Grouped.gutter, S.of(28))
                    : EdgeInsets.only(bottom: S.of(28)),
                child: body(page, () => Navigator.of(page).pop()),
              ),
            ),
          ],
        ),
      ),
    ),
  ));
}

/// The sub line under Lanes: running lane titles, then "and N more" and any
/// other agent they run as. Profile names are never printed; see [laneProviders].
String? laneSummary(List<LaneInfo> lanes, {String? ownAgent}) {
  final running = lanes.where((l) => l.running).toList();
  if (running.isEmpty) return null;
  final first = running.first.title.trim();
  final rest = running.length - 1;
  final titles = first.isEmpty
      ? null
      : rest == 0
          ? first
          : '$first and $rest more';
  final others = <String>{
    for (final l in running)
      if ((l.agent ?? '').isNotEmpty && l.agent != ownAgent) l.agent!,
  };
  if (others.isEmpty) return titles;
  final on = 'on ${others.join(', ')}';
  return titles == null ? on : '$titles \u00b7 $on';
}

/// Providers of the running lanes' profiles that differ from the session's own.
List<String> laneProviders(
    List<LaneInfo> lanes, Map<String, String> providers, String? ownProfile) {
  final own = providers[ownProfile];
  return {
    for (final l in lanes)
      if (l.running &&
          providers[l.profile] != null &&
          providers[l.profile] != own)
        providers[l.profile]!,
  }.toList();
}

/// A muted sub line with small provider icons after the text.
class LaneSub extends StatelessWidget {
  const LaneSub({super.key, this.text, required this.providers});
  final String? text;
  final List<String> providers;

  @override
  Widget build(BuildContext context) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in providers)
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 3),
                child: AppIcon('provider:$p', size: 14, color: Grouped.muted),
              ),
            if (text != null)
              Flexible(
                  child: Text(text!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textWidthBasis: TextWidthBasis.longestLine,
                      style: Grouped.subStyle())),
          ]);
}

/// One success criterion on the goal page.
class GoalCriterion {
  const GoalCriterion(this.label, this.done);
  final String label;
  final bool done;
}

/// SE-03 goal page: Goal text box and, only when the caller has a goal record
/// (criteria != null), the Success criteria list.
class SessionGoalPage extends StatefulWidget {
  const SessionGoalPage({
    super.key,
    required this.goal,
    required this.onSet,
    required this.onCancel,
    required this.onResume,
    required this.onDone,
    this.criteria,
    this.onToggleCriterion,
    this.onAddCriterion,
  });

  final VoidCallback onDone;
  final GoalInfo? goal;
  final ValueChanged<String> onSet;
  final VoidCallback onCancel;
  final VoidCallback onResume;
  final List<GoalCriterion>? criteria;
  final ValueChanged<int>? onToggleCriterion;
  final ValueChanged<String>? onAddCriterion;

  @override
  State<SessionGoalPage> createState() => _SessionGoalPageState();
}

class _SessionGoalPageState extends State<SessionGoalPage> {
  Future<void> _edit() async {
    final t = await promptText(context,
        title: 'Goal',
        initial: widget.goal?.text ?? '',
        hint: 'What should the agent work toward?',
        saveLabel: 'Set goal',
        minLines: 3,
        maxLines: 6);
    if (t == null || t.trim().isEmpty) return;
    widget.onSet(t.trim());
  }

  Future<void> _add() async {
    final t = await promptText(context,
        title: 'Add criterion', saveLabel: 'Add', hint: 'What counts as done?');
    if (t == null || t.trim().isEmpty) return;
    widget.onAddCriterion?.call(t.trim());
  }

  Widget _row(Widget child, {VoidCallback? onTap, String? label}) => Semantics(
        button: onTap != null,
        label: label,
        child: ExcludeSemantics(
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: child),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final text = goal?.text.trim() ?? '';
    final criteria = widget.criteria;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SpecLabel('Goal', top: 24),
      Semantics(
        button: true,
        label: text.isEmpty ? 'Goal, set a goal' : 'Goal, $text',
        child: ExcludeSemantics(
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _edit,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              constraints: const BoxConstraints(minHeight: 92),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(text.isEmpty ? 'What should the agent work toward?' : text,
                  style: sans(15,
                      color: text.isEmpty ? AppColors.fg3 : AppColors.fg1)),
            ),
          ),
        ),
      ),
      if (goal != null)
        _row(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(goal.paused ? 'Resume goal' : 'Cancel goal',
                  style: sans(14, weight: W.label, color: AppColors.fg2)),
            ),
          ),
          label: goal.paused ? 'Resume goal' : 'Cancel goal',
          onTap: () {
            goal.paused ? widget.onResume() : widget.onCancel();
            widget.onDone();
          },
        ),
      if (criteria != null) ...[
        const SpecLabel('Success criteria'),
        for (var i = 0; i < criteria.length; i++)
          _row(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      color: criteria[i].done ? AppColors.fg1 : null,
                      borderRadius: BorderRadius.circular(5),
                      border: criteria[i].done
                          ? null
                          : Border.all(color: AppColors.fg3, width: 1.5)),
                  child: criteria[i].done
                      ? Center(
                          child: AppIcon('check', size: 14, color: AppColors.bg))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(criteria[i].label,
                        style: sans(15,
                            color: criteria[i].done
                                ? AppColors.fg1
                                : AppColors.fg2))),
              ]),
            ),
            label: '${criteria[i].label}, ${criteria[i].done ? 'done' : 'open'}',
            onTap: widget.onToggleCriterion == null
                ? null
                : () => widget.onToggleCriterion!(i),
          ),
        if (widget.onAddCriterion != null)
          _row(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                AppIcon('plus', size: 20, color: AppColors.fg2),
                const SizedBox(width: 12),
                Text('Add criterion',
                    style: sans(15, color: AppColors.fg2)),
              ]),
            ),
            label: 'Add criterion',
            onTap: _add,
          ),
      ],
    ]);
  }
}

/// Auto-settle and cold-resume mode, kept in step with the panel behind it,
/// then Effort chips when the caller can set one. Approvals stay hidden until
/// the daemon exposes a per-session approval mode.
class SessionBehaviourPage extends StatefulWidget {
  const SessionBehaviourPage({
    super.key,
    required this.auto,
    required this.resume,
    required this.onAuto,
    required this.onResume,
    this.effort,
    this.onEffort,
  });

  final bool? auto;
  final String? resume;
  final ValueChanged<bool>? onAuto;
  final ValueChanged<String>? onResume;
  final String? effort;
  final ValueChanged<String>? onEffort;

  @override
  State<SessionBehaviourPage> createState() => _SessionBehaviourPageState();
}

class _SessionBehaviourPageState extends State<SessionBehaviourPage> {
  late bool? _auto = widget.auto;
  late String? _resume = widget.resume;
  late String? _effort = widget.effort;

  static const _efforts = [
    ('low', 'Low'),
    ('medium', 'Medium'),
    ('high', 'High'),
    ('max', 'Max')
  ];

  @override
  Widget build(BuildContext context) {
    final auto = _auto;
    final resume = _resume;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Grouped.gutter, 8, Grouped.gutter, 0),
        child: SettingsGroup(children: [
          if (auto != null && widget.onAuto != null)
            SettingsRow(
              icon: 'archive',
              label: 'Auto-settle',
              sub: 'Save memory and park this chat after 12 hours idle',
              trailing: SettingsSwitch(
                  value: auto,
                  onChanged: (v) {
                    setState(() => _auto = v);
                    widget.onAuto!(v);
                  }),
              onTap: () {
                setState(() => _auto = !auto);
                widget.onAuto!(!auto);
              },
            ),
          if (resume != null && widget.onResume != null)
            SettingsPickerRow<String>(
              icon: 'clock',
              label: 'Cold resume',
              detail: 'How a cold session picks up its history',
              value: sessionResumeLabel(resume),
              items: const [('ask', 'Ask'), ('lean', 'Lean'), ('full', 'Full')],
              selected: resume,
              onSelected: (m) {
                setState(() => _resume = m);
                widget.onResume!(m);
              },
            ),
        ]),
      ),
      if (widget.onEffort != null) ...[
        const SpecLabel('Effort'),
        SpecChipWrap(chips: [
          for (final e in _efforts)
            SpecChip(e.$2, _effort == e.$1, () {
              setState(() => _effort = e.$1);
              widget.onEffort!(e.$1);
            }),
        ]),
      ],
    ]);
  }
}

String sessionResumeLabel(String mode) => switch (mode) {
      'lean' => 'Lean',
      'full' => 'Full',
      _ => 'Ask',
    };
