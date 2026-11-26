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

/// Desktop Home: needs-you cards, a compact crew readout, recent sessions,
/// and the pinned start composer.
class DesktopHome extends StatefulWidget {
  const DesktopHome({
    super.key,
    required this.client,
    required this.sessions,
    required this.onOpenSession,
    required this.onOpenAgent,
    required this.onRefresh,
    required this.onStart,
    required this.onOpenAllSessions,
    this.profileLabel,
    this.projectLabel,
  });

  final DaemonClient client;
  final List<SessionInfo>? sessions;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(CoordinationAgent a) onOpenAgent;
  final VoidCallback onRefresh;
  final void Function(String text, {String? agentId, String? folder}) onStart;
  final VoidCallback onOpenAllSessions;
  final String? profileLabel;
  final String? projectLabel;

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
  final FocusNode _composerFocus = FocusNode();

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

  @override
  void dispose() {
    _composerFocus.dispose();
    super.dispose();
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

  String? get _lastUsedFolder {
    final sessions = (widget.sessions ?? const <SessionInfo>[]).toList()
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    for (final s in sessions) {
      if (s.projectFolder.trim().isNotEmpty) return s.projectFolder;
      if (s.folder.trim().isNotEmpty) return s.folder;
    }
    return null;
  }

  String get _projectChipLabel {
    final explicit = widget.projectLabel?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final folder = _lastUsedFolder;
    final base = folder == null ? '' : lastPathSegment(folder);
    return base.isEmpty ? 'No project selected' : base;
  }

  @override
  Widget build(BuildContext context) {
    // Keep Lead's dedicated session so Lead moves into Working when active.
    final sessions = widget.sessions ?? const <SessionInfo>[];
    final crew = deriveCrew(_agents, sessions, includeAgentNeedsYou: true);
    final sections = deriveHomeSections(crew, _groups);
    final recent = recentHomeSessions(sessions);
    final empty = crew.isEmpty && recent.isEmpty;

    return ColoredBox(
      color: AppColors.panelBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            SizedBox(
              height: 34,
              child: Row(children: [
                Text('Home',
                    style: sans(16, weight: W.label, color: AppColors.fg1)),
                const Spacer(),
                Text(_dateLabel, style: sans(12, color: AppColors.fg3)),
              ]),
            ),
            Expanded(
              child: empty
                  ? _emptyState()
                  : LayoutBuilder(builder: (context, constraints) {
                      final recentCap = constraints.maxWidth < 850 ? 3 : 7;
                      final shownRecent = recent.take(recentCap).toList();
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          if (sections.needsCount > 0) ...[
                            _sectionLabel('Needs you', sections.needsCount),
                            for (final e in sections.needs) _needsCard(e),
                            for (final g in sections.groupAsks)
                              _groupNeedsCard(g,
                                  sections.groupWaitingNames[g.id] ?? const []),
                          ],
                          if (sections.working.isNotEmpty) ...[
                            _sectionLabel('Working', sections.working.length),
                            for (final e in sections.working) _crewRow(e),
                          ],
                          if (sections.available.isNotEmpty) ...[
                            _sectionLabel(
                                'Available', sections.available.length),
                            for (final e in sections.available) _crewRow(e),
                          ],
                          if (shownRecent.isNotEmpty) ...[
                            _sectionLabel(
                              'Recent sessions',
                              recent.length,
                              action: 'View all',
                              onAction: widget.onOpenAllSessions,
                            ),
                            for (final s in shownRecent) _recentRow(s),
                          ],
                        ],
                      );
                    }),
            ),
            // Frame 01: the start composer is a 900 column, centred.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StartComposer(
                      agents: _agents,
                      folder: _lastUsedFolder,
                      profileLabel: widget.profileLabel,
                      focusNode: _composerFocus,
                      onStart: widget.onStart,
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 24,
                      child: Row(children: [
                        const SizedBox(width: 4),
                        AppIcon('folder', size: 13, color: AppColors.fg3),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _projectChipLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12, color: AppColors.fg3),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('No agents yet',
              style: sans(15, weight: W.label, color: AppColors.fg1)),
          const SizedBox(height: 6),
          Text('Start a session below and an agent will pick it up.',
              style: sans(13, color: AppColors.fg3)),
          const SizedBox(height: 16),
          _HoverFillButton(
            width: 96,
            height: 28,
            fill: AppColors.surface3,
            hoverFill: AppColors.hoverPlate,
            onTap: _composerFocus.requestFocus,
            child: Text('New session',
                style: sans(12, weight: W.label, color: AppColors.fg1)),
          ),
        ]),
      );

  Widget _sectionLabel(
    String label,
    int count, {
    String? action,
    VoidCallback? onAction,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: SizedBox(
          height: 24,
          child: Row(children: [
            Text(label, style: sans(12, weight: W.label, color: AppColors.fg2)),
            const SizedBox(width: 8),
            Text('$count', style: sans(12, color: AppColors.fg3)),
            const Spacer(),
            if (action != null)
              TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(action, style: sans(12, color: AppColors.fg3)),
                  ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _NeedsCard(
        leading: AgentMochi(e.agent.id, size: 24),
        name: e.agent.displayName,
        question: question.isEmpty ? 'Needs your input' : question,
        onOpen: open,
        primaryLabel: approval ? 'Approve' : 'Answer',
        primaryBusy: approval && busy,
        onPrimary: approval ? () => _approve(e) : open,
      ),
    );
  }

  Widget _groupNeedsCard(GroupSummary g, List<String> waitingNames) {
    final waiting = waitingNames.isEmpty
        ? 'Waiting on you'
        : 'Waiting on ${waitingNames.join(', ')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _NeedsCard(
        leading: AgentCluster(ids: g.agentIds, size: 24),
        name: g.title.trim().isEmpty ? 'Group' : g.title.trim(),
        question: waiting,
        onOpen: () => openGroupThread(context, client: widget.client, group: g),
        primaryLabel: 'Answer',
        onPrimary: () =>
            openGroupThread(context, client: widget.client, group: g),
      ),
    );
  }

  Widget _crewRow(CrewEntry e) {
    final a = e.agent;
    final n = e.sessions.length;
    final when = e.lead == null ? '' : relativeTime(e.lead!.lastActive);
    final status = e.state == CrewState.standingBy
        ? (!a.available
            ? 'Wakes when you send'
            : e.lead == null
                ? 'Idle'
                : 'Idle, last run: ${_sessionTitle(e.lead!)}')
        : _cleanSubtitle(e.line);
    return _HomeLineRow(
      onTap: () => widget.onOpenAgent(a),
      leading: AgentMochi(a.id, size: 20),
      title: a.displayName,
      status: status.isEmpty ? 'Standing by' : status,
      running: e.state == CrewState.working,
      meta: e.state == CrewState.working && n > 0
          ? (n == 1 ? '1 session' : '$n sessions')
          : hostOf(widget.client.baseUrl),
      when: when,
    );
  }

  static String _sessionTitle(SessionInfo s) {
    final title = s.title.trim();
    return title.isEmpty ? 'Untitled session' : title;
  }

  String _sessionAgentName(SessionInfo s) {
    if (isDedicatedLeadSession(s.id)) return 'Lead';
    final id = s.displayAgentId;
    if (id == null || id == 'lead' || id == 'snippet') return 'Lead';
    for (final a in _agents) {
      if (a.id == id) return a.displayName;
    }
    return id;
  }

  Widget _recentRow(SessionInfo s) {
    final folder = lastPathSegment(s.projectFolder,
        ifEmpty: lastPathSegment(s.folder, ifEmpty: ''));
    return _RecentSessionRow(
      onTap: () => widget.onOpenSession(s),
      agent: _sessionAgentName(s),
      title: _sessionTitle(s),
      meta: folder,
      when: relativeTime(s.lastActive),
    );
  }
}

class _NeedsCard extends StatefulWidget {
  const _NeedsCard({
    required this.leading,
    required this.name,
    required this.question,
    required this.onOpen,
    required this.primaryLabel,
    this.onPrimary,
    this.primaryBusy = false,
  });

  final Widget leading;
  final String name;
  final String question;
  final VoidCallback? onOpen;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryBusy;

  @override
  State<_NeedsCard> createState() => _NeedsCardState();
}

class _NeedsCardState extends State<_NeedsCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final open = widget.onOpen;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surface2 : AppColors.surface1,
            borderRadius: BorderRadius.circular(R.of(8)),
          ),
          child: Row(children: [
            SizedBox(width: 24, height: 24, child: widget.leading),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: W.label, color: AppColors.fg1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.question,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg2),
              ),
            ),
            const SizedBox(width: 8),
            const _NeedsYouMark(),
            const SizedBox(width: 8),
            _HoverFillButton(
              width: 56,
              height: 28,
              fill: AppColors.surface3,
              hoverFill: AppColors.hoverPlate,
              onTap: open,
              child: Text('Open',
                  style: sans(12, weight: W.label, color: AppColors.fg1)),
            ),
            if (widget.primaryLabel.isNotEmpty) ...[
              const SizedBox(width: 6),
              _HoverFillButton(
                width: 72,
                height: 28,
                fill: AppColors.surface3,
                hoverFill: AppColors.hoverPlate,
                onTap: widget.primaryBusy ? null : widget.onPrimary,
                child: widget.primaryBusy
                    ? Spinner(size: 12, color: AppColors.fg1)
                    : Text(
                        widget.primaryLabel,
                        style: sans(12, weight: W.label, color: AppColors.fg1),
                      ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _NeedsYouMark extends StatelessWidget {
  const _NeedsYouMark();

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration:
              BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('Needs you',
            style: sans(12, weight: W.label, color: AppColors.fg2)),
      ]);
}

class _HomeLineRow extends StatefulWidget {
  const _HomeLineRow({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.status,
    required this.running,
    required this.when,
    this.meta,
  });

  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String status;
  final bool running;
  final String when;
  final String? meta;

  @override
  State<_HomeLineRow> createState() => _HomeLineRowState();
}

class _HomeLineRowState extends State<_HomeLineRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hover ? AppColors.hoverPlate : Colors.transparent,
              borderRadius: BorderRadius.circular(R.of(8)),
            ),
            child: Row(children: [
              SizedBox(width: 20, height: 20, child: widget.leading),
              const SizedBox(width: 10),
              SizedBox(
                width: 150,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, weight: W.label, color: AppColors.fg1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(children: [
                  if (widget.running) ...[
                    Spinner(size: 12, color: AppColors.fg3),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      widget.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg2),
                    ),
                  ),
                ]),
              ),
              if ((widget.meta ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    widget.meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: sans(12, color: AppColors.fg3),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text(
                  widget.when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: sans(12, color: AppColors.fg3),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _RecentSessionRow extends StatefulWidget {
  const _RecentSessionRow({
    required this.onTap,
    required this.agent,
    required this.title,
    required this.meta,
    required this.when,
  });

  final VoidCallback onTap;
  final String agent;
  final String title;
  final String meta;
  final String when;

  @override
  State<_RecentSessionRow> createState() => _RecentSessionRowState();
}

class _RecentSessionRowState extends State<_RecentSessionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 27,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _hover ? AppColors.hoverPlate : Colors.transparent,
              borderRadius: BorderRadius.circular(R.of(8)),
            ),
            child: Row(children: [
              SizedBox(
                width: 120,
                child: Text(
                  widget.agent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3),
                ),
              ),
              const SizedBox(width: 64),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, weight: W.label, color: AppColors.fg1),
                ),
              ),
              if (widget.meta.isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    widget.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: sans(11, color: AppColors.fg3),
                  ),
                ),
              ],
              const SizedBox(width: 16),
              SizedBox(
                width: 40,
                child: Text(
                  widget.when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: sans(11, color: AppColors.fg3),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _StartComposer extends StatefulWidget {
  const _StartComposer({
    required this.agents,
    required this.folder,
    required this.profileLabel,
    required this.focusNode,
    required this.onStart,
  });

  final List<CoordinationAgent> agents;
  final String? folder;
  final String? profileLabel;
  final FocusNode focusNode;
  final void Function(String text, {String? agentId, String? folder}) onStart;

  @override
  State<_StartComposer> createState() => _StartComposerState();
}

class _StartComposerState extends State<_StartComposer> {
  final TextEditingController _controller = TextEditingController();
  String? _selectedAgentId;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_textChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_textChanged)
      ..dispose();
    super.dispose();
  }

  void _textChanged() => setState(() {});

  CoordinationAgent get _leadAgent {
    for (final a in widget.agents) {
      if (a.isLead) return a;
    }
    return CoordinationAgent.fromJson(<String, dynamic>{
      'id': 'lead',
      'display_name': 'Lead',
      'kind': 'lead',
    });
  }

  CoordinationAgent get _selectedAgent {
    final id = _selectedAgentId;
    if (id != null) {
      for (final a in widget.agents) {
        if (a.id == id) return a;
      }
    }
    return _leadAgent;
  }

  List<CoordinationAgent> get _pickerAgents {
    final lead = _leadAgent;
    return [
      lead,
      for (final a in widget.agents)
        if (a.id != lead.id && a.kind != 'group') a
    ];
  }

  Future<void> _pickAgent(BuildContext anchor) async {
    final selected = _selectedAgent;
    final profile = widget.profileLabel?.trim();
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 220,
      maxWidth: 300,
      items: [
        for (final a in _pickerAgents)
          appMenuRow<String>(
            value: a.id,
            leading: AgentMochi(a.id, size: 16),
            label: a.displayName,
            description: a.isLead && profile != null && profile.isNotEmpty
                ? profile
                : null,
            selected: a.id == selected.id,
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _selectedAgentId = picked);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onStart(text, agentId: _selectedAgent.id, folder: widget.folder);
    _controller.clear();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    final agent = _selectedAgent;
    return Container(
      height: 76,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.of(12)),
      ),
      child: Column(children: [
        SizedBox(
          height: 20,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              cursorColor: AppColors.fg1,
              style: sans(13, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText:
                    'Start a session: ask anything, @ to mention agents or files, / for commands',
                hintStyle: sans(13, color: AppColors.fg3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 28,
          child: Row(children: [
            _HoverFillButton(
              size: 28,
              tooltip: 'Attachments are not available in Home yet',
              onTap: null,
              child: AppIcon('plus', size: 14, color: AppColors.fg2),
            ),
            const SizedBox(width: 4),
            Builder(builder: (anchor) {
              final profile = widget.profileLabel?.trim();
              return _AgentPickerChip(
                agent: agent,
                tooltip: profile == null || profile.isEmpty
                    ? 'Choose agent'
                    : 'Choose agent · $profile',
                onTap: () => _pickAgent(anchor),
              );
            }),
            const SizedBox(width: 8),
            _HoverFillButton(
              size: 28,
              tooltip: 'Session options are not available in Home yet',
              onTap: null,
              child:
                  AppIcon('sliders-horizontal', size: 14, color: AppColors.fg2),
            ),
            const Spacer(),
            _HoverFillButton(
              size: 28,
              tooltip: 'Voice input is not available in Home yet',
              onTap: null,
              child: AppIcon('mic', size: 14, color: AppColors.fg2),
            ),
            const SizedBox(width: 6),
            _HoverFillButton(
              size: 28,
              radius: 14,
              tooltip: 'Start session',
              fill: AppColors.accentFill,
              hoverFill: AppColors.accentFill.withValues(alpha: 0.86),
              onTap: hasText ? _submit : null,
              child: AppIcon(
                'arrow-up',
                size: 14,
                color: AppColors.accentFg,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _AgentPickerChip extends StatefulWidget {
  const _AgentPickerChip({
    required this.agent,
    required this.tooltip,
    required this.onTap,
  });

  final CoordinationAgent agent;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_AgentPickerChip> createState() => _AgentPickerChipState();
}

class _AgentPickerChipState extends State<_AgentPickerChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget chip = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 84,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _hover ? AppColors.hoverPlate : AppColors.surface3,
            borderRadius: BorderRadius.circular(R.of(6)),
          ),
          child: Row(children: [
            AgentMochi(widget.agent.id, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.agent.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, weight: W.label, color: AppColors.fg1),
              ),
            ),
            AppIcon('chevron-down', size: 10, color: AppColors.fg2),
          ]),
        ),
      ),
    );
    chip = Tooltip(message: widget.tooltip, child: chip);
    return chip;
  }
}

class _HoverFillButton extends StatefulWidget {
  const _HoverFillButton({
    required this.child,
    required this.onTap,
    this.size,
    this.width,
    this.height,
    this.radius,
    this.fill,
    this.hoverFill,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double? size;
  final double? width;
  final double? height;
  final double? radius;
  final Color? fill;
  final Color? hoverFill;
  final String? tooltip;

  @override
  State<_HoverFillButton> createState() => _HoverFillButtonState();
}

class _HoverFillButtonState extends State<_HoverFillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final base = widget.fill ?? Colors.transparent;
    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: widget.size ?? widget.width,
          height: widget.size ?? widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled && _hover
                ? (widget.hoverFill ?? widget.fill ?? AppColors.hoverPlate)
                : base,
            borderRadius: BorderRadius.circular(widget.radius ?? R.of(6)),
          ),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
