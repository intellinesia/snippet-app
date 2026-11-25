import 'package:flutter/material.dart';

import '../models.dart';
import '../mochi.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_home/sessions_list_phone.dart' show SpinnerGlyph;
import 'spec_bar.dart';

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

Widget _stateIcon(LaneInfo l) {
  if (l.running) return const SpinnerGlyph(size: 14);
  if (l.status == 'failed' || l.status == 'cancelled') {
    return AppIcon('x', size: 14, color: AppColors.fg2);
  }
  if (l.status == 'paused') {
    return AppIcon('pause', size: 14, color: AppColors.fg2);
  }
  return AppIcon('check', size: 14, color: AppColors.fg2);
}

int _epoch(String iso) =>
    (DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0) ~/ 1000;

/// Group header (agent avatar 26 at x16, name 12/500 fg2 at x52, 40 high) and
/// lane rows (min 56, title x16, state line with a 14 icon, time at the end).
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
        children: [
          for (final g in groups) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  AgentMochi(g.$1.isEmpty ? 'snippet' : g.$1, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(g.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, weight: W.label, color: AppColors.fg2))),
                ]),
              ),
            ),
            for (var i = 0; i < g.$3.length; i++)
              _LaneRow(g.$3[i], last: i == g.$3.length - 1, onTap: () => onOpen(g.$3[i])),
          ],
        ],
      );
}

class _LaneRow extends StatelessWidget {
  const _LaneRow(this.lane, {required this.last, required this.onTap});
  final LaneInfo lane;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = relativeTime(_epoch(lane.startedAt));
    final title = lane.title.trim().isEmpty ? 'Lane' : lane.title.trim();
    return Semantics(
      button: true,
      label: '$title, ${_word(lane)}, $time',
      child: ExcludeSemantics(
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(
                border: last
                    ? null
                    : Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(15, color: AppColors.fg1)),
                      const SizedBox(height: 2),
                      Row(children: [
                        _stateIcon(lane),
                        const SizedBox(width: 4),
                        Text(_word(lane),
                            style: sans(12, color: AppColors.fg3)),
                      ]),
                    ]),
              ),
              const SizedBox(width: 8),
              Text(time, style: sans(12, color: AppColors.fg3)),
            ]),
          ),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (brief.isNotEmpty) ...[
        const SpecLabel('Brief'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(brief,
              maxLines: _more ? null : 6,
              overflow: _more ? TextOverflow.visible : TextOverflow.ellipsis,
              style: sans(15, color: AppColors.fg1)),
        ),
        if (!_more && brief.length > 200)
          Semantics(
            button: true,
            label: 'More',
            child: ExcludeSemantics(
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _more = true),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Text('More',
                      style: sans(14, weight: W.label, color: AppColors.fg2)),
                ),
              ),
            ),
          ),
      ],
      if (steps.isNotEmpty) ...[
        const SpecLabel('Report so far'),
        for (var i = 0; i < steps.length; i++)
          Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              AppIcon(
                  lane.running && i == steps.length - 1 ? 'circle' : 'check',
                  size: 16,
                  color: AppColors.fg2),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(steps[i].text,
                      style: sans(14, color: AppColors.fg1))),
            ]),
          ),
      ],
      if (widget.onOpenTranscript != null) ...[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            button: true,
            label: 'Open transcript',
            child: ExcludeSemantics(
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpenTranscript,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.surface2,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('Open transcript',
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                ),
              ),
            ),
          ),
        ),
      ],
      if (widget.onStop != null && lane.running)
        Semantics(
          button: true,
          label: 'Stop lane',
          child: ExcludeSemantics(
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _stop,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                child: Text('Stop lane',
                    style: sans(14, weight: W.label, color: AppColors.fg2)),
              ),
            ),
          ),
        ),
      const SizedBox(height: 24),
    ]);
  }
}
