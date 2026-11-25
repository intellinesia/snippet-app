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
