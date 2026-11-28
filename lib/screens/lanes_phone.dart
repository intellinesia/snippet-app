import 'package:flutter/material.dart';

import '../models.dart';
import '../mochi.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import '../mobile_kit.dart';
import 'mobile_home/sessions_list_phone.dart' show SpinnerGlyph;
import '../transcript.dart' show laneAgentName;

/// SE-08 subtitle: "5 lanes, 2 running".
String lanesSubtitle(List<LaneInfo> lanes) {
  final running = lanes.where((l) => l.running).length;
  final n = lanes.length;
  return '$n ${n == 1 ? 'lane' : 'lanes'}, $running running';
}

String _word(LaneInfo l) => switch (l.status) {
      'running' => 'Running',
      'failed' => 'Failed',
      'paused' => 'Paused',
      'cancelled' => 'Cancelled',
      _ => 'Done',
    };

bool _needsYou(LaneInfo l) => l.status == 'failed' || l.status == 'paused';

int _order(LaneInfo l) => _needsYou(l)
    ? 0
    : l.running
        ? 1
        : 2;

String _sentence(String? raw) {
  final text = (raw ?? '')
      .replaceAll(RegExp(r'[*`#>]'), '')
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
      .trim();
  final end = RegExp(r'[.!?](\s|$)').firstMatch(text);
  return end == null ? text : text.substring(0, end.start + 1);
}

/// One line under the title: what the lane is doing or how it ended.
String laneLine(LaneInfo l) {
  if (l.status == 'failed') {
    final why = _sentence(l.error ?? l.summary);
    return why.isEmpty ? 'Failed' : 'Failed · $why';
  }
  if (l.status == 'paused') return 'Paused at its time limit';
  if (l.running) {
    final act = (l.activity ?? '').trim();
    return act.isEmpty ? 'Working' : act;
  }
  if (l.status == 'cancelled') return 'Cancelled';
  final what = _sentence(l.summary);
  return what.isEmpty ? 'Done' : what;
}

String? _detailLine(LaneInfo l) {
  final line = laneLine(l);
  final word = _word(l);
  if (line == word) return null;
  return line.startsWith('$word · ') ? line.substring(word.length + 3) : line;
}

/// State well: spinner while running, amber mark when it needs the user,
/// a quiet check or cross once finished.
Widget laneStateWell(LaneInfo l) {
  final a = kAndroidLook;
  final d = a ? 40.0 : 30.0;
  final Widget mark = l.running
      ? SpinnerGlyph(size: a ? 18 : 16)
      : AppIcon(
          switch (l.status) {
            'failed' => 'alert-triangle',
            'paused' => 'pause',
            'cancelled' => 'x',
            _ => 'check',
          },
          size: a ? 19 : 17,
          color: _needsYou(l)
              ? AppColors.run
              : l.status == 'cancelled'
                  ? AppColors.fg4
                  : AppColors.fg2);
  return Container(
    width: d,
    height: d,
    decoration: BoxDecoration(
      color: _needsYou(l)
          ? AppColors.run.withValues(alpha: 0.14)
          : AppColors.surface3,
      shape: a ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: a ? null : BorderRadius.circular(9),
    ),
    child: Center(child: mark),
  );
}

int _epoch(String iso) =>
    (DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0) ~/ 1000;

/// Filter values for the phone Lanes page.
enum LaneFilter { all, needs, running, done }

bool _inFilter(LaneInfo l, LaneFilter f) => switch (f) {
      LaneFilter.all => true,
      LaneFilter.needs => _needsYou(l),
      LaneFilter.running => l.running,
      LaneFilter.done => !_needsYou(l) && !l.running,
    };

String _groupHeader(String name, List<LaneInfo> lanes) {
  final needs = lanes.where(_needsYou).length;
  final working = lanes.where((l) => l.running).length;
  final parts = [
    if (needs > 0) '$needs need${needs == 1 ? 's' : ''} you',
    if (working > 0) '$working working',
  ];
  return parts.isEmpty ? name : '$name · ${parts.join(', ')}';
}

/// Lanes grouped by agent, each group a kit card of rows: state well, title,
/// one status line, start time. Needs-you first, then working, then the rest.
List<Widget> lanesPhoneGroups(List<(String, String, List<LaneInfo>)> groups,
    void Function(LaneInfo lane) onOpen,
    {LaneFilter filter = LaneFilter.all}) {
  final out = <Widget>[];
  for (final g in groups) {
    final shown = [
      for (final l in g.$3)
        if (_inFilter(l, filter)) l
    ]..sort((a, b) {
        final r = _order(a).compareTo(_order(b));
        return r != 0 ? r : b.startedAt.compareTo(a.startedAt);
      });
    if (shown.isEmpty) continue;
    out.add(MkGroup(
      header: _groupHeader(g.$2, g.$3),
      children: [for (final l in shown) _LaneRow(l, onTap: () => onOpen(l))],
    ));
  }
  return out;
}

/// The phone lanes list as a plain scrolling body.
class LanesListPhone extends StatelessWidget {
  const LanesListPhone({
    super.key,
    required this.groups,
    required this.onOpen,
  });

  /// (agent id, agent name, lanes) in display order.
  final List<(String, String, List<LaneInfo>)> groups;
  final void Function(LaneInfo lane) onOpen;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: lanesPhoneGroups(groups, onOpen),
      );
}

/// The phone Lanes page: kit large title, a filter row once there is enough
/// to filter, and the grouped list.
class LanesPagePhone extends StatefulWidget {
  const LanesPagePhone({
    super.key,
    required this.groups,
    required this.onOpen,
    required this.onBack,
  });
  final List<(String, String, List<LaneInfo>)> groups;
  final void Function(LaneInfo lane) onOpen;
  final VoidCallback onBack;

  @override
  State<LanesPagePhone> createState() => _LanesPagePhoneState();
}

class _LanesPagePhoneState extends State<LanesPagePhone> {
  LaneFilter _filter = LaneFilter.all;

  @override
  Widget build(BuildContext context) {
    final all = [for (final g in widget.groups) ...g.$3];
    int count(LaneFilter f) => all.where((l) => _inFilter(l, f)).length;
    final options = [
      MkFilter(LaneFilter.all, 'All', count: all.length),
      for (final (f, label) in [
        (LaneFilter.needs, 'Needs you'),
        (LaneFilter.running, 'Running'),
        (LaneFilter.done, 'Finished'),
      ])
        if (count(f) > 0) MkFilter(f, label, count: count(f)),
    ];
    final filtering = all.length >= 6 && options.length > 2;
    final filter = filtering ? _filter : LaneFilter.all;
    final rows = lanesPhoneGroups(widget.groups, widget.onOpen, filter: filter);
    return Material(
      color: AppColors.bg,
      child: MkPage(
        title: 'Lanes',
        onBack: widget.onBack,
        bottomClearance: false,
        filters: filtering
            ? MkFilterGroup<LaneFilter>(
                options: options,
                selected: filter,
                onSelect: (f) => setState(() => _filter = f))
            : null,
        slivers: [
          if (all.isEmpty)
            const SliverToBoxAdapter(
                child: MkEmpty('Parallel agent work appears here.'))
          else
            SliverPadding(
              padding: EdgeInsets.only(
                  bottom: 32 + MediaQuery.paddingOf(context).bottom),
              sliver: SliverList(delegate: SliverChildListDelegate(rows)),
            ),
        ],
      ),
    );
  }
}

class _LaneRow extends StatelessWidget {
  const _LaneRow(this.lane, {required this.onTap});
  final LaneInfo lane;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = relativeTime(_epoch(lane.startedAt));
    final title = lane.title.trim().isEmpty ? 'Lane' : lane.title.trim();
    return Semantics(
      button: true,
      label: '$title, ${_word(lane)}, $time',
      child: ExcludeSemantics(
        child: MkGroupRow(
          key: ValueKey('lane-row-${lane.id}'),
          label: title,
          subtitle: laneLine(lane),
          leading: laneStateWell(lane),
          chevron: false,
          trailing: Text(time, style: sans(13, color: AppColors.fg3)),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// SE-08 detail body: Brief (6 lines then More), Report so far when the lane
/// carries steps, Open transcript, and Stop lane which asks first.
class LaneDetailPhone extends StatefulWidget {
  const LaneDetailPhone({
    super.key,
    required this.lane,
    this.onOpenTranscript,
    this.onStop,
  });
  final LaneInfo lane;
  final VoidCallback? onOpenTranscript;

  /// Called after the user confirms; null hides Stop lane.
  final Future<void> Function()? onStop;

  @override
  State<LaneDetailPhone> createState() => _LaneDetailPhoneState();
}

class _LaneDetailPhoneState extends State<LaneDetailPhone> {
  bool _more = false;

  Future<void> _stop() async {
    final ok = await confirmAction(context,
        title: 'Stop this lane?',
        body: widget.lane.title.trim().isEmpty
            ? 'The lane stops where it is.'
            : widget.lane.title.trim(),
        confirmLabel: 'Stop lane',
        danger: true);
    if (ok) await widget.onStop?.call();
  }

  @override
  Widget build(BuildContext context) {
    final lane = widget.lane;
    final brief = (lane.handoff ?? '').trim();
    final steps = lane.activityLog;
    final a = kAndroidLook;
    final side = a ? 16.0 : MK.gutter;
    final report = _sentence(lane.report ?? lane.summary);
    final agent = (lane.agent ?? '').trim();
    final time = relativeTime(_epoch(lane.startedAt));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      MkGroup(children: [
        MkGroupRow(
          label: _word(lane),
          subtitle: _detailLine(lane),
          leading: laneStateWell(lane),
          chevron: false,
          trailing: time.isEmpty
              ? null
              : Text(time, style: sans(13, color: AppColors.fg3)),
        ),
        if (agent.isNotEmpty)
          MkGroupRow(
            label: 'Agent',
            leading: AgentMochi(agent, size: a ? 40 : 30),
            value: laneAgentName(agent),
            chevron: false,
          ),
      ]),
      if (brief.isNotEmpty)
        MkGroup(header: 'Brief', children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(brief,
                  maxLines: _more ? null : 6,
                  overflow:
                      _more ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: sans(15, height: 1.45, color: AppColors.fg1)),
              if (!_more && brief.length > 200)
                Semantics(
                  button: true,
                  label: 'More',
                  child: ExcludeSemantics(
                    child: TapDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _more = true),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        alignment: Alignment.centerLeft,
                        child: Text('More',
                            style: sans(14.5,
                                weight: W.label, color: AppColors.fg2)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      if (!lane.running && report.isNotEmpty && lane.status != 'failed')
        MkGroup(header: 'Report', children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Text(report,
                style: sans(15, height: 1.45, color: AppColors.fg1)),
          ),
        ]),
      if (steps.isNotEmpty)
        MkGroup(header: 'Report so far', children: [
          for (var i = 0; i < steps.length; i++)
            MkGroupRow(
              label: steps[i].text,
              icon: lane.running && i == steps.length - 1 ? 'circle' : 'check',
              bareIcon: true,
              chevron: false,
            ),
        ]),
      if (widget.onOpenTranscript != null ||
          (widget.onStop != null && lane.running))
        Padding(
          padding: EdgeInsets.fromLTRB(side, 20, side, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.onOpenTranscript != null)
              MkPill('Open transcript',
                  icon: 'file-text',
                  expand: true,
                  onTap: widget.onOpenTranscript),
            if (widget.onStop != null && lane.running)
              MkPill('Stop lane',
                  tone: MkPillTone.quiet, expand: true, onTap: _stop),
          ]),
        ),
      const SizedBox(height: 24),
    ]);
  }
}
