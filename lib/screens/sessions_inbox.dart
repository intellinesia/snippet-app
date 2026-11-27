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
import '../widgets.dart' show AppIcon, HeaderAction;
import 'lead/lead_state.dart' show isDedicatedLeadSession, isInboxSessionRow;
import 'session_list_row.dart' show sessionNeedsYou, projectLabel;
import 'shell_nav.dart' show sessionBusy;

enum SessionsFilter { all, needsYou, running, mine }

enum _Group {
  needsYou('Needs you'),
  running('Running'),
  recent('Recent');

  const _Group(this.label);
  final String label;
}

/// Desktop Sessions page in the Tasks layout: a header strip, then one 32pt
/// row per session grouped needs-you, running, recent. Opening a row opens the session as a tab.
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
    final all = [
      for (final s in _sessions)
        if (!isDedicatedLeadSession(s.id) && !isInboxSessionRow(s)) s
    ];
    final list = [for (final s in all) if (_keep(s)) s]
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final needs = [for (final s in list) if (sessionNeedsYou(s)) s];
    final running = [
      for (final s in list)
        if (!sessionNeedsYou(s) && sessionBusy(s)) s
    ];
    final recent = [
      for (final s in list)
        if (!sessionNeedsYou(s) && !sessionBusy(s)) s
    ];
    final groups = [
      if (needs.isNotEmpty) (_Group.needsYou, needs),
      if (running.isNotEmpty) (_Group.running, running),
      if (recent.isNotEmpty) (_Group.recent, recent),
    ];
    return ColoredBox(
      color: AppColors.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The Tasks header strip: title and count, filters and the action.
        Container(
          height: PaneRow.height,
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: AppColors.paneLine, width: AppColors.hairline))),
          child: Row(children: [
            Text('Sessions',
                style: sans(13, weight: W.label, color: PaneRow.labelOn)),
            const SizedBox(width: 8),
            Text('${all.length}',
                style: sans(12, color: AppColors.fg4, tabular: true)),
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
            if (widget.onNewSession != null) ...[
              const SizedBox(width: 10),
              HeaderAction('New session', onTap: widget.onNewSession),
            ],
          ]),
        ),
        Expanded(
          child: all.isEmpty
              ? _empty()
              : list.isEmpty
                  ? Center(
                      child: Text('Nothing here for this filter.',
                          style: sans(12, color: AppColors.fg3)))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        for (var g = 0; g < groups.length; g++)
                          ..._section(groups[g].$1, groups[g].$2,
                              first: g == 0),
                      ],
                    ),
        ),
      ]),
    );
  }

  List<Widget> _section(_Group group, List<SessionInfo> all,
      {required bool first}) {
    // Long histories stay cheap: the count is real, the rows stop at 60.
    final rows = all.take(60);
    return [
      Padding(
        // The same inset and 22pt mark column as the task group headings.
        padding: EdgeInsets.fromLTRB(14, first ? 8 : 18, 14, 6),
        child: Row(children: [
          SizedBox(width: 22, child: Center(child: _groupMark(group))),
          const SizedBox(width: 4),
          Text(group.label,
              style: sans(12.5, weight: W.label, color: AppColors.fg2)),
          const SizedBox(width: 8),
          Text('${all.length}', style: sans(12, color: AppColors.fg4)),
        ]),
      ),
      for (final s in rows)
        SessionInboxRow(
          session: s,
          agentName: _names[s.displayAgentId] ?? '',
          onTap: () => widget.onOpen(s),
        ),
    ];
  }

  static Widget _groupMark(_Group g) => switch (g) {
        _Group.needsYou => Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
        _Group.running => AppIcon('activity', size: 13, color: AppColors.fg3),
        _Group.recent => AppIcon('clock', size: 13, color: AppColors.fg3),
      };

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
              height: PaneRow.pill,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? PaneRow.plate : Colors.transparent,
                borderRadius: BorderRadius.circular(PaneRow.radius),
              ),
              child: Text(label,
                  style: sans(PaneRow.label,
                      color: selected ? PaneRow.labelOn : PaneRow.labelOff)),
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
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hover ? AppColors.hoverPlate : Colors.transparent,
              borderRadius: BorderRadius.circular(PaneRow.radius),
            ),
            child: Row(children: [
              SizedBox(
                  width: 22,
                  child: Center(
                      child: ClipOval(
                          child: AgentMochi(s.displayAgentId ?? 'snippet',
                              size: rowAvatarSize(32))))),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: PaneRow.labelOn)),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Text(summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5, color: AppColors.fg4)),
                ),
              ] else
                const Spacer(flex: 4),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: Text(who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg3)),
              ),
              SizedBox(
                  width: 22,
                  child: mark == null ? null : Center(child: mark)),
              SizedBox(
                width: 34,
                child: Text(relativeTime(s.lastActive),
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: sans(12, color: AppColors.fg4, tabular: true)),
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
