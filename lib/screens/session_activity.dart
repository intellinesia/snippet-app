import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/ledger_line.dart';
import '../platform.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../tool_sheet.dart';
import '../transcript.dart';
import '../widgets.dart';
import 'processes.dart';

/// One finished run of tool steps, as the transcript folded it.
class ActivityRun {
  const ActivityRun(this.key, this.steps, this.took);
  final String key;
  final List<ToolStep> steps;
  final Duration? took;
}

/// Desktop right-pane Activity: tool steps first, then background jobs.
class SessionActivityPanel extends StatefulWidget {
  const SessionActivityPanel({
    super.key,
    required this.client,
    required this.sessionId,
    required this.runs,
    required this.live,
    required this.onClose,
    this.onOpenFile,
    this.showBackground = true,
  });

  final DaemonClient client;
  final String sessionId;
  final ValueListenable<List<ActivityRun>> runs;
  final ValueListenable<ToolBatch?> live;
  final VoidCallback onClose;
  final void Function(String path)? onOpenFile;

  /// Off in render tests, where there is no daemon to list jobs from.
  final bool showBackground;

  @override
  State<SessionActivityPanel> createState() => _SessionActivityPanelState();
}

const _runCap = 30;

class _SessionActivityPanelState extends State<SessionActivityPanel> {
  final Set<String> _open = {};
  bool _all = false;

  Widget _label(String t) => Padding(
        padding: EdgeInsets.only(bottom: S.s8),
        child: Text(t,
            style: sans(11.5, weight: FontWeight.w600, color: AppColors.fg4)),
      );

  List<DenseToolRow> _rows(List<ToolStep> steps) => [
        for (final s in steps)
          DenseToolRow(tool: s.tool, args: s.args, result: s.result),
      ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ColoredBox(
      color: AppColors.surface1,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(children: [
              Text('Activity',
                  style:
                      sans(kMobile ? 20 : 16, weight: FontWeight.w600, color: AppColors.fg1)),
              const Spacer(),
              IconBtn('x',
                  size: 28,
                  iconSize: 14,
                  tooltip: 'Close',
                  onTap: widget.onClose),
            ]),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([widget.runs, widget.live]),
              builder: (context, _) {
                final live = widget.live.value;
                final all = widget.runs.value;
                final shown = _all || all.length <= _runCap
                    ? all
                    : all.sublist(all.length - _runCap);
                return ListView(
                  padding: EdgeInsets.all(S.s16),
                  children: [
                    if (live != null && live.running) ...[
                      _label('Now'),
                      LedgerStrip(rows: _rows(live.steps), steps: live.steps),
                      SizedBox(height: S.s20),
                    ],
                    _label('This session'),
                    if (all.isEmpty)
                      Text('No tool steps yet',
                          style: sans(13, color: AppColors.fg4))
                    else ...[
                      for (final r in shown.reversed)
                        Container(
                          key: ValueKey(r.key),
                          margin: EdgeInsets.only(bottom: S.s4),
                          padding: EdgeInsets.symmetric(
                              horizontal: S.s12, vertical: S.s8),
                          decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(R.md)),
                          child: LedgerLine(
                            rows: _rows(r.steps),
                            steps: r.steps,
                            took: r.took,
                            open: _open.contains(r.key),
                            onTap: () => setState(() {
                              if (!_open.remove(r.key)) _open.add(r.key);
                            }),
                          ),
                        ),
                      if (!_all && all.length > _runCap)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() => _all = true),
                            child: Text('Show older (${all.length - _runCap})',
                                style: sans(12.5, color: AppColors.fg3)),
                          ),
                        ),
                    ],
                    if (widget.showBackground) ...[
                      SizedBox(height: S.s20),
                      _label('Background'),
                      ProcessesScreen(
                          client: widget.client,
                          sessionId: widget.sessionId,
                          embedded: true),
                    ],
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
