import 'package:flutter/material.dart';

import '../tap_detector.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../widgets.dart';

/// Phone ledger (CH-18): a collapsible card of what the run did, one row per
/// file change or command. Words and signs only, no green or red.
class PhoneLedgerCard extends StatefulWidget {
  const PhoneLedgerCard({super.key, required this.steps});
  final List<ToolStep> steps;

  @override
  State<PhoneLedgerCard> createState() => _PhoneLedgerCardState();
}

class _PhoneLedgerCardState extends State<PhoneLedgerCard> {
  bool _open = true;

  List<(String, String, String)> _rows() {
    final rows = <(String, String, String)>[];
    for (final c in fileChanges(widget.steps)) {
      final verb = switch (c.kind) {
        FileChangeKind.created => 'Created',
        FileChangeKind.edited => 'Edited',
        FileChangeKind.deleted => 'Deleted',
        FileChangeKind.moved => 'Moved',
      };
      rows.add((verb, c.name, '+${c.added} -${c.removed}'));
    }
    for (final s in widget.steps) {
      if (toolBaseName(s.tool) != 'bash' || s.running) continue;
      final cmd = stepCommand(s)?.label ?? '';
      if (cmd.isEmpty) continue;
      rows.add(('Ran', cmd.split('\n').first, s.failed ? 'failed' : 'done'));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
          color: AppColors.surface1, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: 'Ledger, ${rows.length} actions, ${_open ? 'expanded' : 'collapsed'}',
          excludeSemantics: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text('Ledger  ${rows.length} ${rows.length == 1 ? 'action' : 'actions'}',
                      style: sans(12, weight: W.label, color: AppColors.fg2)),
                  const Spacer(),
                  AppIcon(_open ? 'chevron-up' : 'chevron-down',
                      size: 16, color: AppColors.fg3),
                ]),
              ),
            ),
          ),
        ),
        if (_open)
          for (final r in rows)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Row(children: [
                  SizedBox(
                      width: 56,
                      child: Text(r.$1,
                          style: sans(11, weight: W.label, color: AppColors.fg3))),
                  Expanded(
                    child: Text(r.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(12, color: AppColors.fg1)),
                  ),
                  const SizedBox(width: 8),
                  Text(r.$3, style: sans(11, color: AppColors.fg2)),
                ]),
              ),
            ),
        if (_open) const SizedBox(height: 6),
      ]),
    );
  }
}
