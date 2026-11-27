import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/agent_cluster.dart';
import '../crew_status.dart';
import '../models.dart';
import '../mochi.dart';
import '../session_quick_send.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'group_messaging.dart' show openGroupThread;
import 'lead/lead_state.dart' show isDedicatedLeadSession;

class HomeSections {
  const HomeSections({
    required this.needs,
    required this.working,
    required this.available,
    required this.groupAsks,
    required this.groupWaitingNames,
  });

  final List<CrewEntry> needs;
  final List<CrewEntry> working;
  final List<CrewEntry> available;
  final List<GroupSummary> groupAsks;

  final Map<String, List<String>> groupWaitingNames;

  int get needsCount => needs.length + groupAsks.length;
}

HomeSections deriveHomeSections(
  List<CrewEntry> crew,
  List<GroupSummary> groups,
) {
  final needs = [
    for (final e in crew)
      if (e.state == CrewState.needsYou) e
  ];
  // Keep the existing rule: only direct asks without a backing session can
  // surface through their group as a group-level ask.
  final askers = <String, String>{
    for (final e in needs)
      if (e.lead == null) e.agent.id: e.agent.displayName
  };
  final groupAsks = [
    for (final g in groups)
      if (g.agentIds.any(askers.containsKey)) g
  ];
  return HomeSections(
    needs: needs,
    working: [
      for (final e in crew)
        if (e.state == CrewState.working) e
    ],
    available: [
      for (final e in crew)
        if (e.state == CrewState.standingBy) e
    ],
    groupAsks: groupAsks,
    groupWaitingNames: {
      for (final g in groupAsks)
        g.id: [
          for (final id in g.agentIds)
            if (askers.containsKey(id)) askers[id]!
        ]
    },
  );
}

List<SessionInfo> recentHomeSessions(Iterable<SessionInfo> sessions) {
  final out = [
    for (final s in sessions)
      if (!s.settled) s
  ];
  out.sort((a, b) => b.lastActive.compareTo(a.lastActive));
  return out;
}

/// Desktop Home: who needs you, who is working, who is free, recent sessions.
class DesktopHome extends StatefulWidget {
  const DesktopHome({
    super.key,
    required this.client,
    required this.sessions,
    required this.onOpenSession,
    required this.onOpenAgent,
    required this.onRefresh,
    required this.onOpenAllSessions,
  });

  final DaemonClient client;
  final List<SessionInfo>? sessions;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(CoordinationAgent a) onOpenAgent;
  final VoidCallback onRefresh;
  final VoidCallback onOpenAllSessions;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  List<CoordinationAgent> _agents = const [];
  final Set<String> _busy = {};
  List<GroupSummary> _groups = const [];

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((a) {
      if (mounted) setState(() => _agents = a);
    }).catchError((_) {});
    widget.client.groups().then((g) {
      if (mounted) setState(() => _groups = g);
    }).catchError((_) {});
  }

  /// Strips raw backticks, markdown links and internal UUIDs/ids from row subs.
  static String _cleanSubtitle(String raw) {
    var s = raw;
    // `[title](session:...)` / `[title](task:...)` -> `title`
    s = s.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1) ?? '');
    // Remove inline code backticks.
    s = s.replaceAll('`', '');
    // Strip raw UUIDs (with optional surrounding parens/brackets).
    s = s.replaceAll(
        RegExp(
            r'[\(\[]?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[\)\]]?',
            caseSensitive: false),
        '');
    // Strip internal session/task/agent prefixes like `session:abc123def456`.
    s = s.replaceAll(
        RegExp(r'\b(?:session|task|agent|artifact|thread):[a-z0-9_/-]+',
            caseSensitive: false),
        '');
    // Strip standalone long hex ids (8+ hex chars with digits).
    s = s.replaceAll(RegExp(r'\b(?=[0-9a-f]*\d)[0-9a-f]{8,}\b'), '');
    // Tidy what id removal leaves behind: empty brackets, dangling joiners.
    s = s.replaceAll(RegExp(r'[\(\[]\s*[\)\]]'), '');
    s = s.replaceAll(
        RegExp(
            r'\b(?:of|for|to|from|on|in|about|against|under|with|by|at|into|via|after|during|over|around)\s*(?=[.,;:]|$)'),
        '');
    s = s.replaceAllMapped(RegExp(r'\s+([.,;:])'), (m) => m[1]!);
    s = s.replaceAll(RegExp(r'^[\s.,;:]+'), '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _approve(CrewEntry e) async {
    final s = e.lead;
    if (s == null) return;
    setState(() => _busy.add(s.id));
    final ok = await quickSend(
      client: widget.client,
      session: s.id,
      action: const QuickApprove(),
    );
    if (ok) widget.onRefresh();
    if (mounted) setState(() => _busy.remove(s.id));
  }

  String get _dateLabel {
    final now = DateTime.now();
    return '${_weekdays[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}';
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning'
        : h < 18
            ? 'Good afternoon'
            : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    // Keep Lead's dedicated session so Lead moves into Working when active.
    final sessions = widget.sessions ?? const <SessionInfo>[];
    final crew = deriveCrew(_agents, sessions, includeAgentNeedsYou: true);
    final sections = deriveHomeSections(crew, _groups);
    final recent = recentHomeSessions(sessions);
    final empty = crew.isEmpty && recent.isEmpty;
    final summary = [
      if (sections.needsCount > 0) '${sections.needsCount} need you',
      if (sections.working.isNotEmpty) '${sections.working.length} working',
    ].join('  ·  ');

    return ColoredBox(
      color: AppColors.panelBg,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // One reading column, the same measure as the chat.
          constraints: const BoxConstraints(maxWidth: 840),
          child: empty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 40, 12, 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_greeting,
                                style: sans(20,
                                    weight: FontWeight.w600,
                                    spacing: -0.2,
                                    color: AppColors.fg1)),
                            const SizedBox(height: 4),
                            Text(
                                summary.isEmpty
                                    ? _dateLabel
                                    : '$_dateLabel  ·  $summary',
                                style: sans(12.5, color: AppColors.fg3)),
                          ]),
                    ),
                    const SizedBox(height: 18),
                    if (sections.needsCount > 0) ...[
                      _sectionLabel('Needs you', sections.needsCount),
                      for (final e in sections.needs) _needsCard(e),
                      for (final g in sections.groupAsks)
                        _groupNeedsCard(
                            g, sections.groupWaitingNames[g.id] ?? const []),
                    ],
                    if (sections.working.isNotEmpty) ...[
                      _sectionLabel('Working', sections.working.length),
                      for (final e in sections.working) _crewRow(e),
                    ],
                    if (sections.available.isNotEmpty) ...[
                      _sectionLabel('Available', sections.available.length),
                      for (final e in sections.available) _crewRow(e),
                    ],
                    if (recent.isNotEmpty) ...[
                      _sectionLabel(
                        'Recent sessions',
                        recent.length,
                        action: 'View all',
                        onAction: widget.onOpenAllSessions,
                      ),
                      for (final s in recent.take(6)) _recentRow(s),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('No agents yet',
              style: sans(15, weight: W.label, color: AppColors.fg1)),
          const SizedBox(height: 6),
          Text('Start a session from the sidebar and an agent will pick it up.',
              style: sans(13, color: AppColors.fg3)),
        ]),
      );

  Widget _sectionLabel(
    String label,
    int count, {
    String? action,
    VoidCallback? onAction,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
        child: SizedBox(
          height: 22,
          child: Row(children: [
            Text('$label  $count',
                style:
                    sans(11.5, weight: FontWeight.w500, color: AppColors.fg3)),
            const Spacer(),
            if (action != null)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAction,
                  child: Text(action,
                      style: sans(11.5, color: AppColors.fg3)),
                ),
              ),
          ]),
        ),
      );

  Widget _needsCard(CrewEntry e) {
    final s = e.lead;
    final approval = e.isApproval && s != null;
    final busy = s != null && _busy.contains(s.id);
    final question = _cleanSubtitle(e.line);
    final open = s == null
        ? () => widget.onOpenAgent(e.agent)
        : () => widget.onOpenSession(s);
    return _HomeRow(
      onTap: open,
      leading: AgentMochi(e.agent.id, size: 24),
      title: e.agent.displayName,
      line: question.isEmpty ? 'Needs your input' : question,
      mark: const _Dot(),
      action: _HoverFillButton(
        width: approval ? 72 : 64,
        height: 26,
        fill: AppColors.surface3,
        hoverFill: AppColors.hoverPlate,
        onTap: busy ? null : (approval ? () => _approve(e) : open),
        child: busy
            ? Spinner(size: 12, color: AppColors.fg1)
            : Text(approval ? 'Approve' : 'Answer',
                style: sans(12, weight: W.label, color: AppColors.fg1)),
      ),
    );
  }

  Widget _groupNeedsCard(GroupSummary g, List<String> waitingNames) {
    final waiting = waitingNames.isEmpty
        ? 'Waiting on you'
        : 'Waiting on ${waitingNames.join(', ')}';
    void open() => openGroupThread(context, client: widget.client, group: g);
    return _HomeRow(
      onTap: open,
      leading: AgentCluster(ids: g.agentIds, size: 24),
      title: g.title.trim().isEmpty ? 'Group' : g.title.trim(),
      line: waiting,
      mark: const _Dot(),
      action: _HoverFillButton(
        width: 64,
        height: 26,
        fill: AppColors.surface3,
        hoverFill: AppColors.hoverPlate,
        onTap: open,
        child: Text('Answer',
            style: sans(12, weight: W.label, color: AppColors.fg1)),
      ),
    );
  }

  Widget _crewRow(CrewEntry e) {
    final a = e.agent;
    final n = e.sessions.length;
    final working = e.state == CrewState.working;
    final status = e.state == CrewState.standingBy
        ? (!a.available
            ? 'Wakes when you send'
            : e.lead == null
                ? 'Idle'
                : 'Idle  ·  last run: ${_sessionTitle(e.lead!)}')
        : _cleanSubtitle(e.line);
    final count = working && n > 1 ? '$n sessions  ·  ' : '';
    return _HomeRow(
      onTap: () => widget.onOpenAgent(a),
      leading: AgentMochi(a.id, size: 24),
      title: a.displayName,
      line: '$count${status.isEmpty ? 'Standing by' : status}',
      mark: working ? Spinner(size: 11, color: AppColors.fg3) : null,
      when: e.lead == null ? '' : relativeTime(e.lead!.lastActive),
    );
  }

  static String _sessionTitle(SessionInfo s) {
    final title = s.title.trim();
    return title.isEmpty ? 'Untitled session' : title;
  }

  String _sessionAgentName(SessionInfo s) {
    if (isDedicatedLeadSession(s.id)) return 'Lead';
    final id = s.displayAgentId;
    if (id == null || id == 'lead') return 'Lead';
    // The default agent has its own name; never fold it into Lead.
    for (final a in _agents) {
      if (a.id == id) return a.displayName.trim().isEmpty ? id : a.displayName;
    }
    return id;
  }

  Widget _recentRow(SessionInfo s) {
    final folder = lastPathSegment(s.projectFolder,
        ifEmpty: lastPathSegment(s.folder, ifEmpty: ''));
    final who = _sessionAgentName(s);
    return _HomeRow(
      onTap: () => widget.onOpenSession(s),
      leading: AgentMochi(s.displayAgentId ?? 'lead', size: 24),
      title: _sessionTitle(s),
      line: folder.isEmpty ? who : '$who  ·  $folder',
      when: relativeTime(s.lastActive),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration:
            BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
      );
}

/// Every Home row: avatar, a title over one quiet line, then a mark, an
/// optional action and the age. Same shape as the Sessions page.
class _HomeRow extends StatefulWidget {
  const _HomeRow({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.line,
    this.mark,
    this.action,
    this.when = '',
  });

  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String line;
  final Widget? mark;
  final Widget? action;
  final String when;

  @override
  State<_HomeRow> createState() => _HomeRowState();
}

class _HomeRowState extends State<_HomeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hover ? AppColors.hoverPlate : Colors.transparent,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(children: [
              SizedBox.square(dimension: 24, child: ClipOval(child: widget.leading)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13,
                            weight: FontWeight.w500, color: AppColors.fg1)),
                    const SizedBox(height: 3),
                    Text(widget.line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (widget.mark != null) ...[
                widget.mark!,
                const SizedBox(width: 10),
              ],
              if (widget.action != null) ...[
                widget.action!,
                if (widget.when.isNotEmpty) const SizedBox(width: 10),
              ],
              if (widget.when.isNotEmpty)
                Text(widget.when,
                    style: sans(11.5, color: AppColors.fg3, tabular: true)),
            ]),
          ),
        ),
      );
}

class _HoverFillButton extends StatefulWidget {
  const _HoverFillButton({
    required this.child,
    required this.onTap,
    this.width,
    this.height,
    this.fill,
    this.hoverFill,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final Color? fill;
  final Color? hoverFill;

  @override
  State<_HoverFillButton> createState() => _HoverFillButtonState();
}

class _HoverFillButtonState extends State<_HoverFillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final base = widget.fill ?? Colors.transparent;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled && _hover
                ? (widget.hoverFill ?? widget.fill ?? AppColors.hoverPlate)
                : base,
            borderRadius: BorderRadius.circular(R.of(6)),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
