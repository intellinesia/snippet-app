import 'package:flutter/material.dart';

import '../models.dart';
import '../motion_routes.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';

/// A page one level down from the session's Actions: back circle, title, rows.
Future<void> pushActionsSubPage(BuildContext context,
    {required String title,
    required Widget Function(BuildContext context, VoidCallback back) body}) {
  return Navigator.of(context).push<void>(AppPageRoute<void>(
    builder: (page) => Material(
      color: AppColors.pageBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Grouped.gutter, 8, Grouped.gutter, 8),
              child: Row(children: [
                GroupedCircleButton(
                    icon: 'chevron-left',
                    tooltip: 'Back',
                    onTap: () => Navigator.of(page).pop()),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Grouped.pageTitleStyle()),
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    Grouped.gutter, 8, Grouped.gutter, S.of(28)),
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

/// Set a goal, or read and cancel or resume the one that is running.
class SessionGoalPage extends StatefulWidget {
  const SessionGoalPage({
    super.key,
    required this.goal,
    required this.onSet,
    required this.onCancel,
    required this.onResume,
    required this.onDone,
  });

  final VoidCallback onDone;
  final GoalInfo? goal;
  final ValueChanged<String> onSet;
  final VoidCallback onCancel;
  final VoidCallback onResume;

  @override
  State<SessionGoalPage> createState() => _SessionGoalPageState();
}

class _SessionGoalPageState extends State<SessionGoalPage> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    if (goal != null) {
      return SettingsGroup(
        header: goal.paused ? 'Paused' : 'Working',
        children: [
          Padding(
            padding: const EdgeInsets.all(Grouped.padX),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal.text, style: Grouped.titleStyle()),
                const SizedBox(height: 14),
                Btn(goal.paused ? 'Resume goal' : 'Cancel goal',
                    small: true, variant: BtnVariant.secondary, onTap: () {
                  goal.paused ? widget.onResume() : widget.onCancel();
                  widget.onDone();
                }),
              ],
            ),
          ),
        ],
      );
    }
    return SettingsGroup(
      footer: 'The agent works toward it on its own until it is done.',
      children: [
        Padding(
          padding: const EdgeInsets.all(Grouped.padX),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppField(
                  controller: _ctl,
                  hint: 'What should the agent work toward?',
                  minLines: 2,
                  maxLines: 4),
              const SizedBox(height: 12),
              Btn('Set goal', full: true, onTap: () {
                final t = _ctl.text.trim();
                if (t.isEmpty) return;
                widget.onSet(t);
                widget.onDone();
              }),
            ],
          ),
        ),
      ],
    );
  }
}

/// Auto-settle and cold-resume mode, kept in step with the panel behind it.
class SessionBehaviourPage extends StatefulWidget {
  const SessionBehaviourPage({
    super.key,
    required this.auto,
    required this.resume,
    required this.onAuto,
    required this.onResume,
  });

  final bool? auto;
  final String? resume;
  final ValueChanged<bool>? onAuto;
  final ValueChanged<String>? onResume;

  @override
  State<SessionBehaviourPage> createState() => _SessionBehaviourPageState();
}

class _SessionBehaviourPageState extends State<SessionBehaviourPage> {
  late bool? _auto = widget.auto;
  late String? _resume = widget.resume;

  @override
  Widget build(BuildContext context) {
    final auto = _auto;
    final resume = _resume;
    return SettingsGroup(children: [
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
    ]);
  }
}

String sessionResumeLabel(String mode) => switch (mode) {
      'lean' => 'Lean',
      'full' => 'Full',
      _ => 'Ask',
    };
