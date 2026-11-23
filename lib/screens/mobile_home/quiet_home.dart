import '../../chat/agent_cluster.dart';
import 'package:flutter/material.dart';

import '../../crew_status.dart';
import '../../menu_widgets.dart' show relativeTime, showAppMenu, appMenuItem;
import '../../mochi.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../session_list_row.dart' show sessionNeedsYou;
import '../shell_nav.dart' show sessionBusy;
import 'home_data.dart';

/// Quiet Home and Sessions: two calm lists, no hero, no shader, no cards.
/// Both read the same sessions; Home shows only what matters now.
class QuietPlaceHeader extends StatelessWidget {
  const QuietPlaceHeader(
      {super.key,
      required this.title,
      this.onSearch,
      this.onSettings,
      this.trailing,
      this.tagline});
  final String title;
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;
  final Widget? trailing;

  /// One calm sentence under the title.
  final String? tagline;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s12, S.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (onSearch != null)
              _IconTap('search', 'Search', onSearch!),
            if (onSettings != null) _IconTap('settings', 'Settings', onSettings!),
            if (trailing != null) trailing!,
          ]),
          Text(title,
              style: sans(34,
                  height: 41 / 34, weight: FontWeight.w500, color: AppColors.fg1)),
          if (tagline != null)
            Padding(
              padding: EdgeInsets.only(top: S.s4),
              child: Text(tagline!, style: sans(13, color: AppColors.fg3)),
            ),
        ]),
      );
}

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
              child: Center(
                  child: AppIcon(icon, size: 22, color: AppColors.fg1))),
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

class QuietHomeScreen extends StatelessWidget {
  const QuietHomeScreen({
    super.key,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    required this.onOpenSessions,
    required this.onSettings,
    required this.onSearch,
    this.onNew,
    this.onOpenAgent,
    this.onOpenLead,
    this.onAllAgents,
    this.onProfile,
    this.onDecide,
    this.offline,
    this.groups = const [],
    this.onOpenGroup,
  });

  final Widget? offline;
  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final void Function(SessionInfo s) onOpenSession;
  final VoidCallback onOpenSessions;
  final VoidCallback onSettings;
  final VoidCallback onSearch;
  final VoidCallback? onNew;
  final void Function(CoordinationAgent a)? onOpenAgent;
  final VoidCallback? onOpenLead;
  final VoidCallback? onAllAgents;
  final void Function(CoordinationAgent a)? onProfile;
  final List<GroupSummary> groups;
  final void Function(GroupSummary g)? onOpenGroup;
  int get groupCount => groups.length;
  final Future<bool> Function(SessionInfo s, bool approve)? onDecide;

  @override
  Widget build(BuildContext context) {
    final names = {for (final a in agents) a.id: a.displayName};
    final asks = needsYouItems(sessions);
    final working = [
      for (final s in sessions)
        if (!s.settled && sessionBusy(s) && !sessionNeedsYou(s)) s
    ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final rows = agentRows(agents, sessions);
    final lead = agents.where((a) => a.isLead).firstOrNull;
    // Lead first, then whoever needs you, then who is working, then the rest.
    final strip = <(CoordinationAgent, CrewState)>[
      if (lead != null)
        (lead, working.isNotEmpty ? CrewState.working : CrewState.standingBy),
      for (final r in rows.needs) (r.agent, r.state),
      for (final r in rows.working) (r.agent, r.state),
      for (final r in rows.asleep) (r.agent, r.state),
    ];
    // A group ask counts only when its asker has no session ask of its own.
    final withAsk = {for (final a in asks) a.agentId};
    final askers = {
      for (final r in rows.needs)
        if (!withAsk.contains(r.agent.id)) r.agent.id
    };
    final groupAsks = [
      for (final g in groups)
        if (g.agentIds.any(askers.contains)) g
    ];
    final quiet = asks.isEmpty && working.isEmpty && groupAsks.isEmpty;
    final dayStart = DateTime.now()
            .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
            .millisecondsSinceEpoch ~/
        1000;
    final finished = sessions
        .where((s) =>
            !sessionBusy(s) && !sessionNeedsYou(s) && s.lastActive >= dayStart)
        .length;
    final total = agents.where((a) => !a.isLead).length + (lead != null ? 1 : 0);
    final allLabel = groupCount > 0
        ? 'All $total agents and $groupCount ${groupCount == 1 ? 'group' : 'groups'}'
        : 'All $total agents';
    return ListView(
      padding: EdgeInsets.only(bottom: S.s24),
      children: [
        QuietPlaceHeader(
          title: 'Agents',
          onSearch: onSearch,
          onSettings: onSettings,
          tagline: quiet && strip.isNotEmpty
              ? 'Tap an agent to talk to it. Nobody is working.'
              : null,
        ),
        if (offline != null) offline!,
        if (strip.isNotEmpty)
          _FaceStrip(
              items: strip,
              onOpen: (a) => onOpenAgent?.call(a),
              onProfile: onProfile),
        if (asks.isNotEmpty) ...[
          QuietSectionLabel('Needs you', count: asks.length + groupAsks.length),
          for (final a in asks)
            _Ask(item: a, names: names, onOpen: onOpenSession, onDecide: onDecide),
        ],
        if (groupAsks.isNotEmpty && asks.isEmpty) ...[
          QuietSectionLabel('Needs you', count: groupAsks.length),
        ],
        for (final g in groupAsks)
          QuietRow(
            title: g.title.isEmpty ? 'Group' : g.title,
            sub: 'Waiting on ${[for (final id in g.agentIds) if (askers.contains(id)) ((names[id] ?? '').trim().isEmpty ? id : names[id]!)].join(', ')}',
            leading: AgentCluster(ids: g.agentIds, size: 28),
            trailing: const QuietHand(size: 14),
            onTap: onOpenGroup == null ? null : () => onOpenGroup!(g),
          ),
        if (working.isNotEmpty) ...[
          QuietSectionLabel('Working', count: working.length),
          for (final s in working)
            QuietRow(
              title: _agentName(s, names),
              titleLines: 1,
              sub: s.title.isEmpty ? 'Untitled session' : s.title,
              meta: relativeTime(s.lastActive),
              leading: AgentMochi(s.displayAgentId ?? 'snippet', size: 28),
              onTap: () => onOpenSession(s),
            ),
        ],
        if (quiet) ...[
          const QuietSectionLabel('Start'),
          _StartGroup(onOpenLead: onOpenLead, onNew: onNew),
        ],
        if (groups.isNotEmpty) ...[
          QuietSectionLabel('Groups', count: groups.length),
          for (final g in groups)
            QuietRow(
              title: g.title.isEmpty ? 'Group' : g.title,
              sub: '${g.members.length} members',
              leading: AgentCluster(ids: g.agentIds, size: 28),
              onTap: onOpenGroup == null ? null : () => onOpenGroup!(g),
            ),
        ],
        if (finished > 0) ...[
          SizedBox(height: S.s8),
          QuietRow(
            title: '$finished finished today',
            leading: AppIcon('check-circle', size: 20, color: AppColors.fg3),
            trailing:
                AppIcon('chevron-right', size: 16, color: AppColors.fg3),
            onTap: onOpenSessions,
          ),
        ],
        if (onAllAgents != null)
          QuietRow(
            title: allLabel,
            leading: AppIcon('users', size: 20, color: AppColors.fg3),
            trailing:
                AppIcon('chevron-right', size: 16, color: AppColors.fg3),
            onTap: onAllAgents,
          ),
      ],
    );
  }
}

/// Who is here: 56 pt faces with a 16 pt state badge, scrolling sideways.
class _FaceStrip extends StatelessWidget {
  const _FaceStrip(
      {required this.items, required this.onOpen, this.onProfile});
  final void Function(CoordinationAgent a)? onProfile;
  final List<(CoordinationAgent, CrewState)> items;
  final void Function(CoordinationAgent a) onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 92 + (MediaQuery.textScalerOf(context).scale(11) - 11) * 2,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s4),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 16),
          itemBuilder: (_, i) {
            final (a, state) = items[i];
            return Semantics(
              button: true,
              label: a.displayName,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onOpen(a),
                onLongPress: () async {
                  final pick = await showAppMenu<String>(context, items: [
                    appMenuItem(
                        value: 'message', icon: 'message', label: 'Message'),
                    appMenuItem(
                        value: 'profile', icon: 'user', label: 'Profile'),
                  ]);
                  if (pick == 'message') onOpen(a);
                  if (pick == 'profile') onProfile?.call(a);
                },
                child: SizedBox(
                  width: 56,
                  child: Column(children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(clipBehavior: Clip.none, children: [
                        AgentMochi(a.id, size: 56),
                        if (state != CrewState.standingBy)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                  color: AppColors.bg, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: state == CrewState.needsYou
                                  ? const QuietHand(size: 12)
                                  : AppIcon('circle',
                                      size: 10, color: AppColors.fg1),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text(a.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: sans(11, color: AppColors.fg3)),
                  ]),
                ),
              ),
            );
          },
        ),
      );
}

/// The Start group: one calm place for the two things you do first.
class _StartGroup extends StatelessWidget {
  const _StartGroup({this.onOpenLead, this.onNew});
  final VoidCallback? onOpenLead;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: S.s16),
        child: Container(
          decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(R.md)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            QuietRow(
              title: 'Ask Lead what is next',
              sub: 'Lead plans it and hands it out',
              leading: AgentMochi('lead', size: 28),
              trailing: AppIcon('chevron-right', size: 16, color: AppColors.fg3),
              onTap: onOpenLead,
            ),
            QuietRow(
              title: 'New session',
              sub: 'Pick an agent, then say what to make',
              leading: AppIcon('edit', size: 22, color: AppColors.fg2),
              trailing: AppIcon('chevron-right', size: 16, color: AppColors.fg3),
              onTap: onNew,
            ),
          ]),
        ),
      );
}

class _Ask extends StatefulWidget {
  const _Ask(
      {required this.item,
      required this.names,
      required this.onOpen,
      required this.onDecide});
  final AskItem item;
  final Map<String, String> names;
  final void Function(SessionInfo) onOpen;
  final Future<bool> Function(SessionInfo, bool)? onDecide;

  @override
  State<_Ask> createState() => _AskState();
}

class _AskState extends State<_Ask> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    await widget.onDecide!(widget.item.session, approve);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.item.session;
    final canDecide =
        widget.item.kind == AskKind.approval && widget.onDecide != null;
    return Container(
      margin: EdgeInsets.fromLTRB(S.s16, 0, S.s16, S.s8),
      padding: EdgeInsets.all(S.s12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.of(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpen(s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: EdgeInsets.only(top: S.s2),
                child: const QuietHand()),
            SizedBox(width: S.s12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title.isEmpty ? 'Untitled session' : s.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: sans(15,
                            height: 20 / 15,
                            weight: W.label,
                            color: AppColors.fg1)),
                    Text(
                        '${_agentName(s, widget.names)} · ${switch (widget.item.kind) {
                          AskKind.approval => 'Asks to run something',
                          AskKind.question => 'Asked you a question',
                          AskKind.handoff => 'Ready for review',
                        }}',
                        style: sans(13, height: 18 / 13, color: AppColors.fg3)),
                  ]),
            ),
            SizedBox(width: S.s8),
            Text(relativeTime(s.lastActive),
                style: sans(12, height: 16 / 12, color: AppColors.fg3)),
          ]),
        ),
        SizedBox(height: S.s12),
        Row(children: [
          if (canDecide) ...[
            Btn('Approve',
                small: true,
                onTap: _busy ? null : () => _decide(true)),
            SizedBox(width: S.s8),
          ],
          Btn(canDecide ? 'Reply' : 'Open',
              small: true,
              variant: BtnVariant.secondary,
              onTap: () => widget.onOpen(s)),
        ]),
      ]),
    );
  }
}

enum _Filter { all, needs, running }

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
    final running = all.where((s) => sessionBusy(s) && !sessionNeedsYou(s)).length;
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
    }.where(hit).toList();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/ 1000;
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
                size: 48, iconSize: 20, tooltip: 'Cancel', onTap: widget.onExitSelect),
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
      QuietPlaceHeader(
          title: 'Sessions',
          onSearch: () => setState(() {
                _searching = !_searching;
                if (!_searching) _q.clear();
              })),
      if (_searching)
        Padding(
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
        ),
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
          Text(widget.sessions.isEmpty ? 'No sessions yet' : 'No sessions here.',
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
              onTap: widget.onNew,
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
          ],
        ]),
      ));
    }
    children.add(SizedBox(height: S.s24));
    return ListView(children: children);
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
                style: sans(14,
                    color: selected ? AppColors.bg : AppColors.fg3)),
          ]),
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
