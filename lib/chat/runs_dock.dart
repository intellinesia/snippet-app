import 'package:flutter/material.dart';

import '../mochi.dart';
import '../motion_routes.dart';
import '../platform.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';

/// One agent's run as the phone dock and sheet show it.
class RunLine {
  const RunLine(this.agentId, this.name, this.state, this.task,
      {this.failed = false});
  final String agentId;
  final String name;

  /// Words, never colour: Working, Idle, Failed.
  final String state;
  final String task;
  final bool failed;
}

/// Dock above the composer: a run ring, "3 working", overlapped avatars and
/// a failed pill. The whole dock is one 48 high target.
class RunsDock extends StatelessWidget {
  const RunsDock({super.key, required this.runs, required this.onOpen});
  final List<RunLine> runs;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final working = runs.where((r) => r.state == 'Working').toList();
    return Semantics(
      button: true,
      label: '${working.length} working',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            if (kMobile) ...[
              // Static ring: it never animates, so reduced motion needs no case.
              SizedBox(
                width: 16,
                height: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.fg2, width: 2)),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text('${working.length} working',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, weight: W.label, color: AppColors.fg1)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 22,
                width: 22.0 + (working.take(3).length - 1).clamp(0, 2) * 14,
                child: Stack(children: [
                  for (var i = 0; i < working.take(3).length; i++)
                    Positioned(
                        left: i * 14.0,
                        child: AgentMochi(working[i].agentId, size: 22)),
                ]),
              ),
              const Spacer(),
            ] else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.fg2, width: 2)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${working.length} working',
                        maxLines: 1,
                        softWrap: false,
                        style:
                            sans(13, weight: W.label, color: AppColors.fg1)),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 22,
                      width: 22.0 +
                          (working.take(3).length - 1).clamp(0, 2) * 14,
                      child: Stack(children: [
                        for (var i = 0; i < working.take(3).length; i++)
                          Positioned(
                              left: i * 14.0,
                              child:
                                  AgentMochi(working[i].agentId, size: 22)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The sheet: "Activity" with the run count, then rows of 56.
class RunsSheet extends StatelessWidget {
  const RunsSheet({super.key, required this.runs, this.onOpenChat});
  final List<RunLine> runs;
  final void Function(String agentId)? onOpenChat;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
            color: AppColors.surface1, borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(children: [
              Text('Activity',
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
              const Spacer(),
              Text('${runs.length} ${runs.length == 1 ? 'run' : 'runs'} today',
                  style: sans(12, color: AppColors.fg3)),
            ]),
          ),
          for (final r in runs)
            InkWell(
              key: ValueKey('run-${r.agentId}'),
              onTap: () => Navigator.of(context).push(AppPageRoute<void>(
                  builder: (_) => RunDetailPage(run: r, onOpenChat: onOpenChat))),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    AgentMochi(r.agentId, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(14,
                                  weight: W.label, color: AppColors.fg1)),
                          Text(r.task,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12.5, color: AppColors.fg3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(r.state, style: sans(12, color: AppColors.fg2)),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 6),
        ]),
      );
}

/// The run's page: back, avatar 28 and name, the state line, then an
/// "Open chat" row.
class RunDetailPage extends StatelessWidget {
  const RunDetailPage({super.key, required this.run, this.onOpenChat});
  final RunLine run;
  final void Function(String agentId)? onOpenChat;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 56,
              child: Row(children: [
                IconBtn('chevron-left',
                    size: 48,
                    iconSize: 20,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 2),
                AgentMochi(run.agentId, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(run.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(16, weight: W.label, color: AppColors.fg1)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('${run.state}  ${run.task}',
                  style: sans(13, color: AppColors.fg3)),
            ),
            InkWell(
              key: const ValueKey('open-chat'),
              onTap: onOpenChat == null ? null : () => onOpenChat!(run.agentId),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                        child: Text('Open chat',
                            style: sans(15, color: AppColors.fg1))),
                    AppIcon('chevron-right', size: 16, color: AppColors.fg3),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
}
