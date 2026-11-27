import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../components.dart' show Spinner;
import '../composer/chat_composer.dart' show kChatMeasure;
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
      child: empty
          ? _empty()
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                // One reading column, the same measure as the chat.
                constraints: const BoxConstraints(maxWidth: kChatMeasure),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                        child: Row(children: [
                          Text('Sessions',
                              style: sans(15,
                                  weight: FontWeight.w600,
                                  color: AppColors.fg1)),
                          const Spacer(),
                          for (final (f, label) in const [
                            (SessionsFilter.all, 'All'),
                            (SessionsFilter.needsYou, 'Needs you'),
                            (SessionsFilter.running, 'Running'),
                            (SessionsFilter.mine, 'Mine'),
                          ]) ...[
                            const SizedBox(width: 2),
                            _FilterChip(
                                label: label,
                                selected: _filter == f,
                                onTap: () => setState(() => _filter = f)),
                          ],
                        ]),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
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
                    ]),
              ),
            ),
    );
  }

  List<Widget> _section(String label, List<SessionInfo> all) {
    if (all.isEmpty) return const [];
    // Long histories stay cheap: the count is real, the rows stop at 60.
    final rows = all.take(60);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text('$label  ${all.length}',
            style: sans(11.5, weight: FontWeight.w500, color: AppColors.fg3)),
      ),
      for (final s in rows)
        SessionInboxRow(
          session: s,
          agentName: _names[s.displayAgentId] ?? '',
          onTap: () => widget.onOpen(s),
        ),
      const SizedBox(height: 10),
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
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.hoverPlate : Colors.transparent,
                borderRadius: BorderRadius.circular(R.of(6)),
              ),
              child: Text(label,
                  style: sans(12,
                      weight: FontWeight.w500,
                      color: selected ? AppColors.fg1 : AppColors.fg3)),
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

  /// Only live states earn a mark; idle and done rows stay quiet.
  Widget? _mark() {
    final s = widget.session;
    if (sessionNeedsYou(s)) {
      return Container(
        key: const ValueKey('session-needs-dot'),
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
      );
    }
    if (sessionBusy(s)) return Spinner(size: 11, color: AppColors.fg3);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final title = s.title.trim().isEmpty ? 'Untitled session' : s.title.trim();
    final who = widget.agentName.isNotEmpty
        ? widget.agentName
        : (s.agentManaged ? 'Agent' : 'You');
    final summary = _summary;
    final mark = _mark();
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
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hover ? AppColors.hoverPlate : Colors.transparent,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(children: [
              ClipOval(
                  child: AgentMochi(s.displayAgentId ?? 'snippet', size: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13,
                            weight: FontWeight.w500, color: AppColors.fg1)),
                    const SizedBox(height: 3),
                    Text(summary.isEmpty ? who : '$who  ·  $summary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (mark != null) ...[mark, const SizedBox(width: 10)],
              Text(relativeTime(s.lastActive),
                  style: sans(11.5, color: AppColors.fg3, tabular: true)),
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
