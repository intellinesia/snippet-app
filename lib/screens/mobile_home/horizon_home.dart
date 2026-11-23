import 'package:flutter/material.dart';

import '../../mochi.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../session_list_row.dart' show sessionNeedsYou;
import '../shell_nav.dart' show sessionBusy;
import 'home_data.dart';
import 'home_style.dart';
import 'needs_you_pager.dart' show askText;
import 'one_thing_ask.dart' show askHeadlineSpans;

/// What a timeline marker is.
enum HorizonKind { ask, work, later }

/// One marker on the Horizon rail: when it next needs the user, and by whom.
class HorizonEntry {
  const HorizonEntry({
    required this.kind,
    required this.at,
    required this.agentId,
    required this.who,
    required this.text,
    this.session,
  });

  final HorizonKind kind;

  /// Null for work in flight with no estimate.
  final DateTime? at;
  final String agentId;
  final String who;
  final String text;
  final SessionInfo? session;
}

String _hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

/// A clock time relative to now: 10:15, Tomorrow, 8:00, Mon 10:15.
String horizonClock(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  if (diff <= 0) return _hm(at);
  if (diff == 1) return 'Tomorrow, ${_hm(at)}';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[at.weekday - 1]} ${_hm(at)}';
}

/// A span of time in words: 25 min, 1 h 6 min, 2 h, 3 days.
String horizonSpan(Duration d) {
  final m = d.inMinutes < 1 ? 1 : d.inMinutes;
  if (m < 60) return '$m min';
  if (m < 48 * 60) {
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }
  return '${d.inDays} days';
}

/// The free-time sentence between two markers. [from] to [to] is empty space.
String horizonGap(
  DateTime from,
  DateTime? to,
  DateTime now, {
  required bool first,
  required bool busy,
}) {
  if (to == null) {
    return first ? 'Nothing is scheduled. You are free.' : 'Then free.';
  }
  final span = to.difference(from);
  if (!first) {
    return span.inHours >= 3
        ? 'Free until ${horizonClock(to, now)}.'
        : '${horizonSpan(span)} later.';
  }
  if (busy) return 'Nothing else before ${horizonClock(to, now)}.';
  final sameDay = DateTime(
        to.year,
        to.month,
        to.day,
      ).difference(DateTime(now.year, now.month, now.day)).inDays ==
      0;
  return !sameDay && span.inHours >= 12
      ? 'Free until ${horizonClock(to, now)}.'
      : 'Free for ${horizonSpan(span)}.';
}

/// Timed markers from live sessions and schedules, soonest first, then work
/// in flight with no estimate.
List<HorizonEntry> horizonEntries({
  required List<SessionInfo> sessions,
  required List<RecurringJob> jobs,
  required String Function(String agentId) nameOf,
  required DateTime now,
}) {
  final nowSec = now.millisecondsSinceEpoch ~/ 1000;
  final timed = <HorizonEntry>[], open = <HorizonEntry>[];
  final byId = {for (final s in sessions) s.id: s};
  for (final s in sessions) {
    if (s.settled || sessionNeedsYou(s)) continue;
    final agent = s.displayAgentId ?? 'snippet';
    final plan = s.plan;
    final step =
        plan != null && plan.total > 0 ? (plan.current ?? '').trim() : '';
    final title = s.title.trim().isEmpty ? 'Untitled session' : s.title.trim();
    var text = step.isNotEmpty ? step : title;
    if (plan != null && plan.total > 0) {
      final n = plan.done < plan.total ? plan.done + 1 : plan.total;
      text = '$text, step $n of ${plan.total}';
    }
    final wake = s.nextWakeAt ?? 0;
    final busy = sessionBusy(s);
    if (wake > nowSec) {
      timed.add(
        HorizonEntry(
          kind: busy ? HorizonKind.work : HorizonKind.later,
          at: DateTime.fromMillisecondsSinceEpoch(wake * 1000),
          agentId: agent,
          who: nameOf(agent),
          text: text,
          session: s,
        ),
      );
    } else if (busy) {
      open.add(
        HorizonEntry(
          kind: HorizonKind.work,
          at: null,
          agentId: agent,
          who: nameOf(agent),
          text: text,
          session: s,
        ),
      );
    }
  }
  for (final j in jobs) {
    if (!j.enabled || j.nextRunAt <= nowSec) continue;
    final s = byId[j.sessionId];
    final agent = s?.displayAgentId ??
        (j.sessionId.isEmpty || j.sessionId.contains('-')
            ? 'lead'
            : j.sessionId);
    timed.add(
      HorizonEntry(
        kind: HorizonKind.later,
        at: DateTime.fromMillisecondsSinceEpoch(j.nextRunAt * 1000),
        agentId: agent,
        who: nameOf(agent),
        text: j.title.trim().isEmpty ? 'Scheduled run' : j.title.trim(),
        session: s,
      ),
    );
  }
  timed.sort((a, b) => a.at!.compareTo(b.at!));
  return [...timed.take(6), ...open.take(4)];
}

const double _kRail = 30;
const double _kNode = 30;

/// Home as a timeline: what needs the user now, what is due and when, and the
/// gaps between written as free time.
class HorizonHome extends StatefulWidget {
  const HorizonHome({
    super.key,
    required this.asks,
    required this.entries,
    required this.names,
    required this.now,
    required this.earlierLabel,
    required this.onOpenSession,
    required this.onOpenAgent,
    required this.onEarlier,
  });

  final List<AskItem> asks;
  final List<HorizonEntry> entries;
  final Map<String, String> names;
  final DateTime now;
  final String earlierLabel;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(String agentId) onOpenAgent;
  final VoidCallback onEarlier;

  @override
  State<HorizonHome> createState() => _HorizonHomeState();
}

class _HorizonHomeState extends State<HorizonHome> {
  // Asks pushed to the next look; they stay on the rail as plain rows.
  final Set<String> _later = {};

  String _name(String id) {
    final n = widget.names[id]?.trim();
    return (n != null && n.isNotEmpty) ? n : id;
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final live = {for (final a in widget.asks) a.id};
    _later.retainAll(live);
    final asks = [
      ...widget.asks.where((a) => !_later.contains(a.id)),
      ...widget.asks.where((a) => _later.contains(a.id)),
    ];
    final children = <Widget>[
      Padding(
        padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s12),
        child: Text(
          'Today',
          style: sans(15, weight: FontWeight.w600, color: AppColors.fg3),
        ),
      ),
    ];

    if (asks.isEmpty) {
      children.add(
        _Entry(
          kind: HorizonKind.later,
          nodeIcon: 'check',
          when: 'Now',
          text: 'Nothing needs you.',
        ),
      );
    } else {
      for (var i = 0; i < asks.length; i++) {
        final a = asks[i];
        final big = i == 0 && !_later.contains(a.id);
        final who = _name(a.agentId);
        final t = askText(a).ask;
        children.add(
          _Entry(
            kind: HorizonKind.ask,
            nodeIcon: 'hand',
            when: 'Now',
            who: who,
            text: t,
            big: big,
            face: big ? null : a.agentId,
            onTap: big ? null : () => widget.onOpenSession(a.session),
            actions: big
                ? [
                    _Pill(
                      'Review',
                      true,
                      () => widget.onOpenSession(a.session),
                    ),
                    _Pill(
                      'Later',
                      false,
                      () => setState(() => _later.add(a.id)),
                    ),
                  ]
                : null,
          ),
        );
      }
    }

    final entries = widget.entries;
    final timed = [
      for (final e in entries)
        if (e.at != null) e,
    ];
    final open = [
      for (final e in entries)
        if (e.at == null) e,
    ];
    final firstAt = timed.isEmpty ? null : timed.first.at;
    children.add(
      _Gap(
        text: horizonGap(now, firstAt, now, first: true, busy: asks.isNotEmpty),
        minutes: firstAt == null ? 600 : firstAt.difference(now).inMinutes,
      ),
    );
    for (var i = 0; i < timed.length; i++) {
      final e = timed[i];
      children.add(_entryFor(e, now));
      final next = i + 1 < timed.length ? timed[i + 1].at : null;
      if (next != null || i == timed.length - 1) {
        children.add(
          _Gap(
            text: horizonGap(e.at!, next, now, first: false, busy: true),
            minutes: next == null ? 40 : next.difference(e.at!).inMinutes,
          ),
        );
      }
    }
    if (open.isNotEmpty) {
      children.add(_Gap(text: 'No estimate.', minutes: 30));
      for (final e in open) {
        children.add(_entryFor(e, now));
      }
    }

    // Earlier stays pinned under the rail so every agent is one tap away.
    return Column(children: [
      Expanded(
        child: ListView(
          key: const ValueKey('horizon-home'),
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          children: children,
        ),
      ),
      _Earlier(label: widget.earlierLabel, onTap: widget.onEarlier),
    ]);
  }

  Widget _entryFor(HorizonEntry e, DateTime now) => _Entry(
        kind: e.kind,
        nodeIcon: e.kind == HorizonKind.work ? 'rotate' : 'clock',
        when: e.at == null ? 'Working' : horizonClock(e.at!, now),
        who: e.who,
        text: e.text,
        face: e.agentId,
        onTap: () {
          final s = e.session;
          s != null ? widget.onOpenSession(s) : widget.onOpenAgent(e.agentId);
        },
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.primary, this.onTap);

  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: Material(
            color: primary
                ? const Color(0xFFFAFAFA)
                : const Color(0xFFFAFAFA).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                tapHaptic();
                onTap();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 96, minHeight: 48),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: S.s20),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: sans(
                        16,
                        weight: FontWeight.w500,
                        color: primary
                            ? const Color(0xFF0A0A0A)
                            : const Color(0xFFFAFAFA),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Node extends StatelessWidget {
  const _Node(this.kind, this.icon);

  final HorizonKind kind;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final ask = kind == HorizonKind.ask;
    return Container(
      width: _kNode,
      height: _kNode,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ask
            ? askAmber.withValues(alpha: 0.22)
            : (kind == HorizonKind.work
                ? AppColors.surface3
                : AppColors.surface2),
      ),
      alignment: Alignment.center,
      child: AppIcon(
        icon,
        size: 18,
        color: ask
            ? askAmber
            : (kind == HorizonKind.work ? AppColors.fg2 : AppColors.fg3),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.kind,
    required this.nodeIcon,
    required this.when,
    required this.text,
    this.who = '',
    this.face,
    this.big = false,
    this.onTap,
    this.actions,
  });

  final HorizonKind kind;
  final String nodeIcon;
  final String when;
  final String who;
  final String text;
  final String? face;
  final bool big;
  final VoidCallback? onTap;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final ask = kind == HorizonKind.ask;
    final label = who.isEmpty ? when : '$when  $who';
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _kRail, child: _Node(kind, nodeIcon)),
        SizedBox(width: S.s12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(
                    15,
                    weight: FontWeight.w600,
                    color: ask ? askAmber : AppColors.fg2,
                  ),
                ),
                SizedBox(height: S.s4),
                if (big)
                  Text.rich(
                    TextSpan(
                      children: askHeadlineSpans(
                        text,
                        serif(
                          26,
                          weight: FontWeight.w500,
                          height: 34 / 26,
                          color: AppColors.fg1,
                        ),
                      ),
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(17, color: AppColors.fg1),
                  ),
                if (actions != null) ...[
                  SizedBox(height: S.s12),
                  Wrap(spacing: 10, runSpacing: 10, children: actions!),
                ],
              ],
            ),
          ),
        ),
        if (face != null) ...[
          SizedBox(width: S.s12),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AgentMochi(face!, size: 32),
          ),
        ],
      ],
    );
    if (onTap == null) {
      return Semantics(
        container: true,
        label: '$when. $who. $text',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: S.s4),
          child: body,
        ),
      );
    }
    return Semantics(
      button: true,
      label: '$when. $who. $text. Opens it.',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(14)),
          onTap: () {
            tapHaptic();
            onTap!();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: S.s4),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// Free time: a dashed rail whose length follows the wait, with the words.
class _Gap extends StatelessWidget {
  const _Gap({required this.text, required this.minutes});

  final String text;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final h = (minutes * 0.5).clamp(48.0, 110.0);
    return Semantics(
      container: true,
      label: text,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: h),
        child: IntrinsicHeight(
          child: Row(
            children: [
              SizedBox(
                width: _kRail,
                child: CustomPaint(painter: _DashPainter(AppColors.fg1)),
              ),
              SizedBox(width: S.s12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: S.s8),
                    child: Text(
                      text,
                      style: serif(
                        15,
                        height: 21 / 15,
                        fontStyle: FontStyle.italic,
                        color: AppColors.fg2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    for (var y = 2.0; y < size.height - 2; y += 9) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + 4).clamp(0, size.height - 2)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _Earlier extends StatelessWidget {
  const _Earlier({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: S.s12),
        child: Semantics(
          button: true,
          label: '$label. Opens everyone by last activity.',
          child: ExcludeSemantics(
            child: InkWell(
              key: const ValueKey('horizon-earlier'),
              borderRadius: BorderRadius.circular(R.of(14)),
              onTap: () {
                tapHaptic();
                onTap();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(
                  children: [
                    SizedBox(
                      width: _kRail,
                      child: Center(
                        child:
                            AppIcon('history', size: 20, color: AppColors.fg2),
                      ),
                    ),
                    SizedBox(width: S.s12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(
                          17,
                          weight: FontWeight.w500,
                          color: AppColors.fg1,
                        ),
                      ),
                    ),
                    AppIcon('chevron-right', size: 16, color: AppColors.fg3),
                    SizedBox(width: S.s4),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
