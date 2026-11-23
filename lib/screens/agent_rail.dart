import 'package:flutter/material.dart';

import '../models.dart';
import '../quiet.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'session_list_row.dart' show sessionNeedsYou;
import 'shell_nav.dart' show sessionBusy;

/// The agent page's right rail: what it is working on and what it finished,
/// one hairline on the left and no rules between sections.
class AgentRail extends StatelessWidget {
  const AgentRail({
    super.key,
    required this.sessions,
    required this.onOpenSession,
    this.onAllSessions,
    this.embedded = false,
  });

  /// Sections only, for a rail that already owns the frame and scroll.
  final bool embedded;

  final List<SessionInfo> sessions;
  final void Function(SessionInfo s) onOpenSession;
  final VoidCallback? onAllSessions;

  @override
  Widget build(BuildContext context) {
    final byRecent = [...sessions]
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final now = [
      for (final s in byRecent)
        if (!s.settled && (sessionNeedsYou(s) || sessionBusy(s))) s
    ];
    final earlier = [
      for (final s in byRecent)
        if (!now.contains(s)) s
    ].take(8).toList();
    final kids = <Widget>[
      if (now.isEmpty && earlier.isEmpty)
        Text('No sessions yet.', style: sans(13, color: AppColors.fg3)),
      if (now.isNotEmpty) ...[
        _label('Working on'),
        for (final s in now) _row(s),
      ],
      if (earlier.isNotEmpty) ...[
        _label('Earlier', top: now.isEmpty ? 0 : 20),
        for (final s in earlier) _row(s),
      ],
      if (onAllSessions != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAllSessions,
            child: Container(
              constraints: const BoxConstraints(minHeight: 24),
              alignment: Alignment.centerLeft,
              child:
                  Text('All sessions', style: sans(13, color: AppColors.fg2)),
            ),
          ),
        ),
    ];
    if (embedded) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: kids);
    }
    return Container(
      decoration: BoxDecoration(
          border: Border(
              left: BorderSide(color: AppColors.fg1.withValues(alpha: 0.06)))),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: kids,
      ),
    );
  }

  Widget _label(String t, {double top = 0}) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 8),
        child: Text(t, style: sans(12, weight: W.label, color: AppColors.fg2)),
      );

  Widget _row(SessionInfo s) {
    final needs = sessionNeedsYou(s);
    final busy = !needs && sessionBusy(s) && !s.settled;
    final word = needs
        ? 'Waiting on you'
        : busy
            ? 'Running'
            : 'Completed';
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenSession(s),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: needs
                ? const QuietHand(size: 14)
                : AppIcon(busy ? 'circle' : 'check',
                    size: 14, color: busy ? AppColors.fg1 : AppColors.fg3),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title.isEmpty ? 'Untitled session' : s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1)),
                Text('$word · ${relativeTime(s.lastActive)}',
                    style: sans(12, color: AppColors.fg3)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
