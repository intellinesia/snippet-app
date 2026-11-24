import '../../toast_avoid.dart';
import 'collapsing_root.dart';
import 'package:flutter/material.dart';

import '../../crew_status.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../session_list_row.dart' show sessionNeedsYou;
import '../shell_nav.dart' show sessionBusy;
import '../../pins.dart';
import 'agents_home.dart';
import 'lead_phone.dart';
import 'home_data.dart';
import 'home_style.dart' show homeAge;
import 'needs_you_pager.dart' show askText;

enum _Filter { all, needs, running }

/// Quiet Home and Sessions: two calm lists, no hero, no shader, no cards.
/// Both read the same sessions; Home shows only what matters now.
class _IconTap extends StatelessWidget {
  const _IconTap(this.icon, this.label, this.onTap);
  final String icon, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
              width: 48,
              height: 48,
              child:
                  Center(child: AppIcon(icon, size: 20, color: AppColors.fg2))),
        ),
      );
}

String _agentName(SessionInfo s, Map<String, String> names) {
  final id = s.displayAgentId ?? '';
  return names[id] ?? (id.isEmpty ? 'Snippet' : id);
}

Widget _stateMark(SessionInfo s) {
  if (sessionNeedsYou(s)) return const QuietHand(size: 20);
  if (sessionBusy(s)) {
    return AppIcon('circle', size: 20, color: AppColors.fg1);
  }
  return SizedBox.square(
      dimension: 20, child: CustomPaint(painter: _Dashed(AppColors.fg4)));
}

String _stateWord(SessionInfo s) => sessionNeedsYou(s)
    ? 'Needs you'
    : sessionBusy(s)
        ? 'Running'
        : s.settled
            ? 'Completed'
            : 'Idle';

enum HomeFilter { all, working, needs, pinned }

class QuietHomeScreen extends StatefulWidget {
  const QuietHomeScreen({
    super.key,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    required this.onOpenSessions,
    required this.onSettings,
    required this.onSearch,
    this.onNew,
    this.onNewMenu,
    this.onNewAgent,
    this.onOpenAgent,
    this.onOpenLead,
    this.onAllAgents,
    this.onArtifacts,
    this.onProfile,
    this.onDecide,
    this.offline,
    this.groups = const [],
    this.onOpenGroup,
    this.pinHost,
  });

  final Widget? offline;
  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final void Function(SessionInfo s) onOpenSession;
  final VoidCallback onOpenSessions;
  final VoidCallback onSettings;
  final VoidCallback onSearch;
  final VoidCallback? onNew;
  final void Function(BuildContext anchor)? onNewMenu;
  final VoidCallback? onNewAgent;
  final void Function(CoordinationAgent a)? onOpenAgent;
  final VoidCallback? onOpenLead;
  final VoidCallback? onAllAgents;
  final VoidCallback? onArtifacts;
  final void Function(CoordinationAgent a)? onProfile;
  final List<GroupSummary> groups;
  final void Function(GroupSummary g)? onOpenGroup;
  final Future<bool> Function(SessionInfo s, bool approve)? onDecide;

  /// Host the pins are stored under; null means nothing is pinned.
  final String? pinHost;
  int get groupCount => groups.length;

  @override
  State<QuietHomeScreen> createState() => _QuietHomeScreenState();
}

class _HomeAgent {
  _HomeAgent(this.agent, this.state, this.line, this.activityMs, this.since);
  final CoordinationAgent agent;
  final CrewState state;
  final String line;
  final int activityMs;

  /// Unix seconds the current work started; null when not working.
  final int? since;
}

class _QuietHomeScreenState extends State<QuietHomeScreen> {
  HomeFilter _filter = HomeFilter.all;
  bool _showAllWorking = false;

  @override
  void initState() {
    super.initState();
    Pins.instance.addListener(_pins);
  }

  @override
  void dispose() {
    Pins.instance.removeListener(_pins);
    super.dispose();
  }

  void _pins() {
    if (mounted) setState(() {});
  }

  bool _pinned(CoordinationAgent a) =>
      widget.pinHost != null &&
      Pins.instance.isPinned(Pins.agent, a.id, host: widget.pinHost!);

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final names = {for (final a in w.agents) a.id: a.displayName};
    final asks = needsYouItems(w.sessions);
    final rows = agentRows(w.agents, w.sessions);
    final lead = w.agents.where((a) => a.isLead).firstOrNull;
    final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    List<SessionInfo> mine(CoordinationAgent a) => [
          for (final s in w.sessions)
            if (s.displayAgentId == a.id) s
        ]..sort((x, y) => y.lastActive.compareTo(x.lastActive));
    int activity(CoordinationAgent a) {
      final s = mine(a).firstOrNull?.lastActive ?? 0;
      final said = a.lastMessage?.at?.millisecondsSinceEpoch ?? 0;
      return s * 1000 > said ? s * 1000 : said;
    }

    final all = <_HomeAgent>[];
    for (final r in [...rows.needs, ...rows.working, ...rows.asleep]) {
      final ms = mine(r.agent);
      final busy = ms.where((s) => !s.settled && sessionBusy(s)).firstOrNull;
      all.add(_HomeAgent(
          r.agent,
          r.state,
          r.state == CrewState.working
              ? (busy?.title.trim().isNotEmpty == true
                  ? busy!.title.trim()
                  : r.line)
              : r.line,
          activity(r.agent),
          r.state == CrewState.working
              ? (busy?.runningSince ?? busy?.lastActive)
              : null));
    }
    if (lead != null) {
      final ls = w.sessions.where((s) => s.displayAgentId == 'lead').toList();
      final busy = ls.any((s) => !s.settled && sessionBusy(s));
      all.add(_HomeAgent(
          lead,
          busy ? CrewState.working : CrewState.standingBy,
          lead.lastMessage?.text ?? 'Orchestrator',
          activity(lead),
          busy ? nowS : null));
    }
    final working = [
      for (final a in all)
        if (a.state == CrewState.working) a
    ]..sort((a, b) => (a.since ?? nowS).compareTo(b.since ?? nowS));
    final needsAgents = {
      for (final a in all)
        if (a.state == CrewState.needsYou) a.agent.id
    };
    final recent = [
      for (final a in all)
        if (a.state == CrewState.standingBy) a
    ]..sort((a, b) => b.activityMs.compareTo(a.activityMs));
    final pinned = [
      for (final a in all)
        if (_pinned(a.agent)) a
    ];

    // Group asks count only when the asker has no session ask of its own.
    final withAsk = {for (final a in asks) a.agentId};
    final askers = {
      for (final id in needsAgents)
        if (!withAsk.contains(id)) id
    };
    final groupAsks = [
      for (final g in w.groups)
        if (g.agentIds.any(askers.contains)) g
    ];
    final pager = <AskCardData>[
      for (final a in asks)
        AskCardData(
            agentId: a.agentId,
            name: _agentName(a.session, names),
            time: relativeTime(a.session.lastActive),
            text: askText(a).ask,
            onTap: () => w.onOpenSession(a.session)),
      for (final g in groupAsks)
        AskCardData(
            agentId: g.agentIds.firstOrNull ?? 'snippet',
            name: g.title.isEmpty ? 'Group' : g.title,
            time: relativeTime(
                (groupActivityAt(g)?.millisecondsSinceEpoch ?? 0) ~/ 1000),
            text:
                'Waiting on ${[for (final id in g.agentIds) if (askers.contains(id)) (names[id] ?? id)].join(', ')}',
            onTap: () => w.onOpenGroup?.call(g)),
    ];

    final dayStart = DateTime.now()
            .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
            .millisecondsSinceEpoch ~/
        1000;
    final finished = w.sessions
        .where((s) =>
            !sessionBusy(s) && !sessionNeedsYou(s) && s.lastActive >= dayStart)
        .length;

    const bar = LargeTitle('Agents');
    Widget root(Widget list) => CollapsingRoot(title: 'Agents', actions: [
          _IconTap('search', 'Search', w.onSearch),
          _IconTap('settings', 'Settings', w.onSettings),
        ], child: list);
    if (all.isEmpty && w.groups.isEmpty) {
      return root(ListView(children: [
        bar,
        if (w.offline != null) w.offline!,
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 12),
          child: Text('No agents yet',
              style: sans(14, weight: FontWeight.w500, color: AppColors.fg1)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          child: Semantics(
            button: true,
            label: 'New agent',
            excludeSemantics: true,
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: w.onNewAgent ?? w.onNew,
              child: Container(
                key: const ValueKey('empty-new-agent'),
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.fg1,
                    borderRadius: BorderRadius.circular(24)),
                child: Text('New agent',
                    style: sans(14,
                        weight: FontWeight.w500, color: AppColors.bg)),
              ),
            ),
          ),
        ),
      ]));
    }

    String status(_HomeAgent a) {
      if (a.state == CrewState.working) {
        final age = homeAge(a.since ?? nowS);
        return 'Working · ${age == 'now' ? '1m' : age}';
      }
      return a.state == CrewState.needsYou ? 'Needs you' : 'Idle';
    }

    AgentCardData card(_HomeAgent a) => AgentCardData(
        a.agent, status(a), a.line,
        working: a.state == CrewState.working);
    void open(CoordinationAgent a) {
      if (a.isLead && w.onOpenLead != null) {
        w.onOpenLead!();
      } else {
        w.onOpenAgent?.call(a);
      }
    }

    final f = _filter;
    final body = <Widget>[];
    final delegating = [
      for (final s in w.sessions)
        if (s.ownerAgentId == 'lead' &&
            s.workerAgentId != null &&
            !s.settled &&
            sessionBusy(s))
          s
    ];
    if (f == HomeFilter.all && delegating.isNotEmpty && w.onOpenLead != null) {
      body.add(LeadHomeCard(
          running: delegating.length, onTap: () => w.onOpenLead!()));
    }
    if (f == HomeFilter.all || f == HomeFilter.needs) {
      if (pager.isNotEmpty) {
        body.add(const SizedBox(height: 16));
        body.add(AskPager(items: pager));
      } else if (f == HomeFilter.needs) {
        body.add(const _Empty('Nothing needs you'));
      }
    }
    if (f == HomeFilter.all || f == HomeFilter.working) {
      if (working.isNotEmpty) {
        body.add(HomeLabel('Working  ${working.length}'));
        final shown = _showAllWorking || f == HomeFilter.working
            ? working
            : working.take(4).toList();
        body.add(
            AgentGrid(cards: [for (final a in shown) card(a)], onOpen: open));
        if (shown.length < working.length) {
          body.add(TextLink('Show ${working.length - shown.length} more',
              () => setState(() => _showAllWorking = true)));
        }
      } else if (f == HomeFilter.working) {
        body.add(const _Empty('No agents are working'));
      }
    }
    if (f == HomeFilter.pinned) {
      if (pinned.isEmpty) {
        body.add(const _Empty('Nothing is pinned'));
      } else {
        body.add(HomeLabel('Pinned  ${pinned.length}'));
        body.add(
            AgentGrid(cards: [for (final a in pinned) card(a)], onOpen: open));
      }
    }
    if (f == HomeFilter.all) {
      if (w.groups.isNotEmpty) {
        body.add(const HomeLabel('Groups'));
        final workingIds = {
          for (final a in all)
            if (a.state == CrewState.working) a.agent.id
        };
        for (final g in sortedGroups(w.groups)) {
          final n = g.members.length;
          final active =
              g.members.where((m) => workingIds.contains(m.id)).length;
          body.add(MarkRow(
            mark: groupMark(36),
            title: g.title.isEmpty ? 'Group' : g.title,
            sub: '$n ${n == 1 ? 'member' : 'members'} · $active active',
            trailing: AppIcon('chevron-right', size: 16, color: AppColors.fg3),
            hairline: false,
            onTap: w.onOpenGroup == null ? null : () => w.onOpenGroup!(g),
          ));
        }
      }
      if (recent.isNotEmpty) {
        body.add(const HomeLabel('Recent'));
        for (final a in recent.take(3)) {
          final at = a.activityMs;
          body.add(MarkRow(
            mark: agentFace(a.agent.id, 36),
            title: a.agent.displayName,
            time: at == 0 ? null : relativeTime(at ~/ 1000),
            sub: a.line,
            onTap: () => open(a.agent),
          ));
        }
      }
    }

    final foot = Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: HomeFooter(
          onAll: w.onAllAgents,
          finished: finished,
          onFinished: w.onOpenSessions),
    );

    return root(CustomScrollView(slivers: [
      SliverList(
        delegate: SliverChildListDelegate([
          bar,
          if (w.offline != null) w.offline!,
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ChipRow(chips: [
              StateChip('All', f == HomeFilter.all,
                  () => setState(() => _filter = HomeFilter.all)),
              StateChip('Working', f == HomeFilter.working,
                  () => setState(() => _filter = HomeFilter.working)),
              StateChip('Needs you', f == HomeFilter.needs,
                  () => setState(() => _filter = HomeFilter.needs),
                  amberDot: pager.isNotEmpty),
              StateChip('Pinned', f == HomeFilter.pinned,
                  () => setState(() => _filter = HomeFilter.pinned)),
            ]),
          ),
          ...body,
        ]),
      ),
      SliverFillRemaining(
        hasScrollBody: false,
        child: Align(alignment: Alignment.bottomCenter, child: foot),
      ),
    ]));
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 8),
        child: Center(child: Text(text, style: sans(14, color: AppColors.fg3))),
      );
}

/// Home bar: 28/500 title at x16, search and settings as 48 x 48 targets.
class QuietSessionsScreen extends StatefulWidget {
  const QuietSessionsScreen({
    super.key,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    this.onSessionActions,
    this.onNew,
    this.selecting = false,
    this.selected = const {},
    this.onToggle,
    this.onExitSelect,
    this.onSelectAll,
  });
  final bool selecting;
  final Set<String> selected;
  final void Function(SessionInfo s)? onToggle;
  final VoidCallback? onExitSelect;
  final void Function(List<SessionInfo> shown)? onSelectAll;
  final VoidCallback? onNew;
  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(SessionInfo s)? onSessionActions;

  @override
  State<QuietSessionsScreen> createState() => _QuietSessionsScreenState();
}

class _QuietSessionsScreenState extends State<QuietSessionsScreen> {
  _Filter _filter = _Filter.all;
  bool _searching = false;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final a in widget.agents) a.id: a.displayName};
    final all = [...widget.sessions]
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final needs = all.where(sessionNeedsYou).length;
    final running =
        all.where((s) => sessionBusy(s) && !sessionNeedsYou(s)).length;
    final q = _q.text.trim().toLowerCase();
    bool hit(SessionInfo s) =>
        q.isEmpty ||
        s.title.toLowerCase().contains(q) ||
        _agentName(s, names).toLowerCase().contains(q);
    final shown = switch (_filter) {
      _Filter.all => all,
      _Filter.needs => all.where(sessionNeedsYou).toList(),
      _Filter.running =>
        all.where((s) => sessionBusy(s) && !sessionNeedsYou(s)).toList(),
    }
        .where(hit)
        .toList();
    final now = DateTime.now();
    final today =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/ 1000;
    final yesterday = today - 86400;
    String bucket(SessionInfo s) => s.lastActive >= today
        ? 'Today'
        : s.lastActive >= yesterday
            ? 'Yesterday'
            : 'Earlier';
    final children = <Widget>[
      if (widget.selecting)
        Padding(
          padding: EdgeInsets.fromLTRB(S.s4, S.s8, S.s16, S.s4),
          child: Row(children: [
            IconBtn('x',
                size: 48,
                iconSize: 20,
                tooltip: 'Cancel',
                onTap: widget.onExitSelect),
            Expanded(
              child: Text(
                  widget.selected.isEmpty
                      ? 'Select sessions'
                      : '${widget.selected.length} selected',
                  style: sans(17, weight: W.label, color: AppColors.fg1)),
            ),
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelectAll?.call(shown),
              child: Padding(
                padding: EdgeInsets.all(S.s12),
                child: Text('Select all',
                    style: sans(13, weight: W.label, color: AppColors.fg1)),
              ),
            ),
          ]),
        )
      else
        const LargeTitle('Sessions'),
      if (_searching)
        ToastAvoid(child: Padding(
          padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
          child: TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: sans(15, color: AppColors.fg1),
            cursorColor: AppColors.fg1,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surface2,
              hintText: 'Search sessions',
              hintStyle: sans(15, color: AppColors.fg4),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: S.s12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.of(12)),
                  borderSide: BorderSide.none),
            ),
          ),
        )),
      Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
        child: Wrap(spacing: S.s8, children: [
          _Chip('All', all.length, _filter == _Filter.all,
              () => setState(() => _filter = _Filter.all)),
          _Chip('Needs you', needs, _filter == _Filter.needs,
              () => setState(() => _filter = _Filter.needs)),
          _Chip('Running', running, _filter == _Filter.running,
              () => setState(() => _filter = _Filter.running)),
        ]),
      ),
    ];
    String? last;
    for (final s in shown) {
      final b = bucket(s);
      if (b != last) {
        children.add(QuietSectionLabel(b));
        last = b;
      }
      children.add(QuietRow(
        title: s.title.isEmpty ? 'Untitled session' : s.title,
        titleLines: 2,
        sub: '${_agentName(s, names)} · ${_stateWord(s)}',
        meta: relativeTime(s.lastActive),
        selected: widget.selecting && widget.selected.contains(s.id),
        leading: widget.selecting
            ? AppIcon(
                widget.selected.contains(s.id) ? 'check-circle' : 'circle',
                size: 22,
                color: widget.selected.contains(s.id)
                    ? AppColors.fg1
                    : AppColors.fg4,
                filled: widget.selected.contains(s.id))
            : _stateMark(s),
        onTap: () => widget.selecting
            ? widget.onToggle?.call(s)
            : widget.onOpenSession(s),
        onLongPress: widget.onSessionActions == null || widget.selecting
            ? null
            : () => widget.onSessionActions!(s),
      ));
    }
    if (shown.isEmpty) {
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s24, S.s16, S.s8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              widget.sessions.isEmpty ? 'No sessions yet' : 'No sessions here.',
              style: sans(14, weight: W.label, color: AppColors.fg1)),
          SizedBox(height: S.s4),
          Text(
              widget.sessions.isEmpty
                  ? 'A session is one job for one agent.'
                  : 'Nothing matches this filter.',
              style: sans(13, color: AppColors.fg3)),
          if (widget.sessions.isEmpty && widget.onNew != null) ...[
            SizedBox(height: S.s12),
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onNew,
              child: HitArea(
                alignment: Alignment.center,
                child: Container(
                  height: 36,
                  padding: EdgeInsets.symmetric(horizontal: S.s16),
                  decoration: BoxDecoration(
                      color: AppColors.accentFill,
                      borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon('edit', size: 14, color: AppColors.accentFg),
                    SizedBox(width: S.s8),
                    Text('New session',
                        style: sans(13,
                            weight: W.label, color: AppColors.accentFg)),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ));
    }
    children.add(SizedBox(height: S.s24));
    return CollapsingRoot(
        title: 'Sessions',
        actions: [
          if (!widget.selecting)
            _IconTap('search', 'Search', () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _q.clear();
                })),
        ],
        child: ListView(children: children));
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.count, this.selected, this.onTap);
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: HitArea(
          alignment: Alignment.center,
          child: Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: S.s12),
            decoration: BoxDecoration(
              color: selected ? AppColors.fg1 : AppColors.surface2,
              borderRadius: BorderRadius.circular(R.of(18)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: sans(14,
                      weight: selected ? W.label : W.body,
                      color: selected ? AppColors.bg : AppColors.fg1)),
              SizedBox(width: S.s6),
              Text('$count',
                  style:
                      sans(14, color: selected ? AppColors.bg : AppColors.fg3)),
            ]),
          ),
        ),
      );
}

/// Idle mark: a dashed ring (the icon font has no dashed circle).
class _Dashed extends CustomPainter {
  _Dashed(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final r = size.width / 2 - 1.5;
    const n = 10;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * 3.141592653589793 / n;
      canvas.drawArc(
          Rect.fromCircle(center: size.center(Offset.zero), radius: r),
          a,
          2 * 3.141592653589793 / n * 0.55,
          false,
          paint);
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}
