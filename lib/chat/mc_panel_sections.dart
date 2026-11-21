import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../screens/session.dart';
import '../screens/session_list_row.dart'
    show sessionAttentionState, sessionNeedsYou;
import '../screens/tasks/task_common.dart' show openTaskDetail;
import '../shell_panel.dart' show openSessionInTab;
import '../settings_form.dart' show Grouped;
import '../theme.dart';
import '../widgets.dart';

/// Short age such as "now", "5m", "2h", "3d".
String mcAge(DateTime since) {
  final d = DateTime.now().difference(since);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// Relative time to a future instant: "in 2h 10m".
String mcUntil(DateTime at) {
  final d = at.difference(DateTime.now());
  if (d.isNegative || d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return 'in ${d.inMinutes}m';
  if (d.inDays < 1) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
  return 'in ${d.inDays}d ${d.inHours % 24}h';
}

/// One thing waiting on the user: a task to review or unblock, or a session
/// that asked a question.
class McNeed {
  McNeed({
    required this.title,
    required this.sub,
    required this.icon,
    required this.tint,
    required this.at,
    required this.open,
  });
  final String title;
  final String sub;
  final String icon;
  final Color tint;
  final DateTime at;
  final void Function(BuildContext context) open;
}

/// Tasks and sessions waiting on the user, oldest first.
List<McNeed> mcNeeds(
    DaemonClient client, List<TaskItem> tasks, List<SessionInfo> sessions) {
  final out = <McNeed>[];
  for (final t in tasks) {
    if (t.status != TaskStatus.inReview && t.status != TaskStatus.blocked) {
      continue;
    }
    final review = t.status == TaskStatus.inReview;
    final at = DateTime.tryParse(t.updatedAt)?.toLocal() ?? DateTime.now();
    out.add(McNeed(
      title: t.title,
      sub: '${review ? 'Review' : 'Blocked'} · task · ${mcAge(at)}',
      icon: review ? 'file' : 'alert-circle',
      tint: review ? AppColors.accent : AppColors.run,
      at: at,
      open: (c) => openTaskDetail(c, client, t.id),
    ));
  }
  for (final s in sessions) {
    if (!sessionNeedsYou(s)) continue;
    final label = sessionAttentionState(s).label;
    final kind = label == 'Needs input'
        ? 'Question'
        : label == 'In review'
            ? 'Review'
            : label;
    final at = s.lastActive > 0
        ? DateTime.fromMillisecondsSinceEpoch(s.lastActive * 1000)
        : DateTime.now();
    out.add(McNeed(
      title: s.title.isEmpty ? 'Session' : s.title,
      sub: '$kind · session · ${mcAge(at)}',
      icon: kind == 'Review' ? 'file' : 'help-circle',
      tint: kind == 'Review' ? AppColors.accent : AppColors.run,
      at: at,
      open: (c) => mcOpenSession(c, client, s.id, s.title),
    ));
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

void mcOpenSession(
    BuildContext context, DaemonClient client, String id, String title) {
  final tab = openSessionInTab;
  if (!kMobile && tab != null) {
    tab(client, id, title);
    return;
  }
  presentScreen(context,
      builder: (_, close) => SessionScreen(
          client: client, sessionId: id, title: title, onMenu: close));
}

/// The "Needs you" section: count chip, "Oldest first", one soft row each.
class McNeedsYou extends StatelessWidget {
  const McNeedsYou({super.key, required this.needs, this.carded = false});
  final List<McNeed> needs;

  /// The agent panel's look: a label over one bordered card.
  final bool carded;

  @override
  Widget build(BuildContext context) {
    if (needs.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (final n in needs) {
      if (rows.isNotEmpty) {
        rows.add(carded
            ? Container(height: 1, color: Grouped.hairline)
            : const SizedBox(height: 2));
      }
      rows.add(_NeedRow(n, flat: carded));
    }
    if (carded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 24,
            child: Row(children: [
              const SizedBox(width: 2),
              Text('Needs you',
                  style: sans(12.5,
                      weight: FontWeight.w500, color: AppColors.fg2)),
              const SizedBox(width: 6),
              Text('${needs.length}',
                  style: sans(12.5, color: AppColors.run, tabular: true)),
              const Spacer(),
              Text('Oldest first', style: sans(11.5, color: AppColors.fg4)),
              const SizedBox(width: 2),
            ]),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.run.withValues(alpha: 0.06),
              border: Border.all(color: AppColors.run.withValues(alpha: 0.28)),
              borderRadius: BorderRadius.circular(Grouped.radiusEnd),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows),
          ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 24,
          child: Row(children: [
            const SizedBox(width: 18),
            Text('Needs you',
                style: sans(12, weight: W.label, color: AppColors.fg3)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.run.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(R.of(8)),
              ),
              child: Text('${needs.length}',
                  style: mono(11, color: AppColors.run)),
            ),
            const Spacer(),
            Text('Oldest first', style: sans(11, color: AppColors.fg4)),
          ]),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.of(12)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
      ]),
    );
  }
}

class _NeedRow extends StatelessWidget {
  const _NeedRow(this.n, {this.flat = false});
  final McNeed n;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: flat ? Colors.transparent : AppColors.surface2,
      child: InkWell(
        onTap: () => n.open(context),
        hoverColor: flat ? Colors.transparent : AppColors.surface3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: n.tint.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(R.of(8)),
              ),
              child: Center(child: AppIcon(n.icon, size: 13, color: n.tint)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12.5, color: AppColors.fg1)),
                    const SizedBox(height: 1),
                    Text(n.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(11.5, color: AppColors.fg3)),
                  ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(R.of(8)),
              ),
              child: Text('Open', style: sans(11.5, color: AppColors.fg2)),
            ),
          ]),
        ),
      ),
    );
  }
}
