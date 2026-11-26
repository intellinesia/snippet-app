import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../components.dart' show Spinner;
import '../menu_widgets.dart' show relativeTime;
import '../mochi.dart';
import '../models.dart';
import '../panel.dart' show presentScreen, PanelStyle;
import '../shell_panel.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart' show AppIcon;
import 'compact_btn.dart';
import 'lead/lead_state.dart' show isDedicatedLeadSession, isInboxSessionRow;
import 'session_list_row.dart' show sessionNeedsYou, projectLabel;
import 'shell_nav.dart' show sessionBusy;

enum SessionsFilter { all, needsYou, running, mine }

/// Desktop Sessions page: the cross-agent session inbox. Needs-you first,
/// then running, then recent. Opening a row opens the session as a tab.
class SessionsInboxView extends StatefulWidget {
  const SessionsInboxView({
    super.key,
    required this.client,
    this.initial = const [],
    required this.onOpen,
    this.onNewSession,
  });

  final DaemonClient client;
  final List<SessionInfo> initial;
  final ValueChanged<SessionInfo> onOpen;
  final VoidCallback? onNewSession;

  @override
  State<SessionsInboxView> createState() => _SessionsInboxViewState();
}

class _SessionsInboxViewState extends State<SessionsInboxView> {
  late List<SessionInfo> _sessions = widget.initial;
  Map<String, String> _names = const {};
  SessionsFilter _filter = SessionsFilter.all;
  Timer? _poll;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      final all = await widget.client.sessions();
      if (!mounted || seq != _loadSeq) return;
      setState(() => _sessions = all);
    } catch (_) {}
    if (!mounted || seq != _loadSeq || _names.isNotEmpty) return;
    try {
      final agents = await widget.client.coordinationAgents();
      if (!mounted || seq != _loadSeq) return;
      setState(() => _names = {
            for (final a in agents)
              if (a.displayName.trim().isNotEmpty) a.id: a.displayName.trim(),
          });
    } catch (_) {}
  }

  bool _keep(SessionInfo s) => switch (_filter) {
        SessionsFilter.all => true,
        SessionsFilter.needsYou => sessionNeedsYou(s),
        SessionsFilter.running => !sessionNeedsYou(s) && sessionBusy(s),
        SessionsFilter.mine => !s.agentManaged,
      };

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final list = [
      for (final s in _sessions)
        if (!isDedicatedLeadSession(s.id) && !isInboxSessionRow(s) && _keep(s))
          s
    ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final needs = [for (final s in list) if (sessionNeedsYou(s)) s];
    final running = [
      for (final s in list)
        if (!sessionNeedsYou(s) && sessionBusy(s)) s
    ];
    final recent = [
      for (final s in list)
        if (!sessionNeedsYou(s) && !sessionBusy(s)) s
    ];
    final empty = _sessions.every(
        (s) => isDedicatedLeadSession(s.id) || isInboxSessionRow(s));
    return ColoredBox(
      color: AppColors.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
          child: Row(children: [
            Text('Sessions',
                style: sans(17, weight: FontWeight.w500, color: AppColors.fg1)),
            const Spacer(),
            Text('Cross-agent inbox',
                style: sans(12, color: AppColors.fg3)),
          ]),
        ),
        if (empty)
          Expanded(child: _empty())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 14, 32, 0),
            child: Row(children: [
              for (final (f, label) in const [
                (SessionsFilter.all, 'All'),
                (SessionsFilter.needsYou, 'Needs you'),
                (SessionsFilter.running, 'Running'),
                (SessionsFilter.mine, 'Mine'),
              ]) ...[
                _FilterChip(
                    label: label,
                    selected: _filter == f,
                    onTap: () => setState(() => _filter = f)),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(32, 22, 32, 24),
              children: [
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text('Nothing here for this filter.',
                          style: sans(12, color: AppColors.fg3)),
                    ),
                  ),
                ..._section('Needs you', needs),
                ..._section('Running', running),
                ..._section('Recent', recent),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  List<Widget> _section(String label, List<SessionInfo> all) {
    if (all.isEmpty) return const [];
    // Long histories stay cheap: the count is real, the rows stop at 60.
    final rows = all.take(60);
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(label,
              style: sans(13, weight: FontWeight.w500, color: AppColors.fg2)),
          const SizedBox(width: 6),
          Text('${all.length}',
              style: sans(12, color: AppColors.fg3, tabular: true)),
        ]),
      ),
      for (final s in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SessionInboxRow(
            session: s,
            agentName: _names[s.displayAgentId] ?? '',
            onTap: () => widget.onOpen(s),
          ),
        ),
      const SizedBox(height: 12),
    ];
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: AppColors.surface2, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: AppIcon('chat-thread', size: 26, color: AppColors.fg3),
          ),
          const SizedBox(height: 24),
          Text('No sessions yet',
              style: sans(16, weight: FontWeight.w500, color: AppColors.fg1)),
          const SizedBox(height: 8),
          Text('Start a session from Home, or mention an agent anywhere.',
              style: sans(12, color: AppColors.fg2)),
          if (widget.onNewSession != null) ...[
            const SizedBox(height: 22),
            CompactBtn('Start a session',
                primary: true, onTap: widget.onNewSession),
          ],
          const SizedBox(height: 22),
          Text('Needs-you items will appear here first.',
              style: sans(11, color: AppColors.fg3)),
        ]),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.surface2 : AppColors.surface1,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(label,
                  style: sans(11,
                      weight: FontWeight.w500,
                      color: selected ? AppColors.fg1 : AppColors.fg2)),
            ),
          ),
        ),
      );
}

/// One session in the inbox: who and what on the left, the latest line in
/// the middle, state and age on the right.
class SessionInboxRow extends StatefulWidget {
  const SessionInboxRow(
      {super.key,
      required this.session,
      required this.agentName,
      required this.onTap});
  final SessionInfo session;
  final String agentName;
  final VoidCallback onTap;

  @override
  State<SessionInboxRow> createState() => _SessionInboxRowState();
}

class _SessionInboxRowState extends State<SessionInboxRow> {
  bool _hover = false;

  String get _summary {
    final s = widget.session;
    if (sessionNeedsYou(s)) {
      final a = s.attention;
      final t = '${a?['label'] ?? a?['text'] ?? ''}'.trim();
      if (t.isNotEmpty) return _plain(t);
      return s.status == 'in_review' ? 'Ready for review' : 'Waiting for your answer';
    }
    final r = (s.resultSummary ?? '').trim();
    if (r.isNotEmpty) return _plain(r);
    return projectLabel(s);
  }

  /// First line as plain text: links keep their label, marks are dropped.
  static String _plain(String md) => md
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[`*]+'), '')
      .replaceFirst(RegExp(r'^\s*[#>]+\s*'), '')
      .trim();

  Widget _state() {
    final s = widget.session;
    final needs = sessionNeedsYou(s);
    final busy = !needs && sessionBusy(s);
    final label = needs
        ? 'Needs you'
        : busy
            ? 'Running'
            : s.settled
                ? 'Done'
                : 'Idle';
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (needs) ...[
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ] else if (busy) ...[
          Spinner(size: 10, color: AppColors.fg3),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: sans(10.5, weight: FontWeight.w500, color: AppColors.fg2)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final title = s.title.trim().isEmpty ? 'Untitled session' : s.title.trim();
    final who = widget.agentName.isNotEmpty
        ? widget.agentName
        : (s.agentManaged ? 'Agent' : 'You');
    final name = sans(12.5, weight: FontWeight.w500, color: AppColors.fg1);
    return Semantics(
      button: true,
      label: '$who, $title',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            decoration: BoxDecoration(
              color: _hover ? AppColors.surface2 : AppColors.surface1,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              ClipOval(
                  child: AgentMochi(s.displayAgentId ?? 'snippet', size: 30)),
              const SizedBox(width: 12),
              SizedBox(
                width: 294,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(who,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: name),
                    const SizedBox(height: 2),
                    Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: name),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 19),
                  child: Text(_summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11.5, color: AppColors.fg3)),
                ),
              ),
              const SizedBox(width: 16),
              _state(),
              SizedBox(
                width: 64,
                child: Text(relativeTime(s.lastActive),
                    textAlign: TextAlign.right,
                    style: sans(11, color: AppColors.fg3, tabular: true)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Opens the Sessions page as a main-area tab.
void openSessionsInbox(BuildContext c,
    {required DaemonClient client,
    List<SessionInfo> initial = const [],
    required ValueChanged<SessionInfo> onOpen,
    VoidCallback? onNewSession}) {
  presentScreen<void>(
    c,
    style: PanelStyle.drawer,
    purpose: ShellPanelPurpose.sessions,
    panelId: 'all-sessions',
    originClient: client,
    title: 'Sessions',
    builder: (_, __) => SessionsInboxView(
      client: client,
      initial: initial,
      onOpen: onOpen,
      onNewSession: onNewSession,
    ),
  );
}
