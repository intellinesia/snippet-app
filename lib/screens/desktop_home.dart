import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/chat_card.dart';
import '../crew_status.dart';
import '../models.dart';
import '../mochi.dart';
import '../quiet.dart';
import '../session_quick_send.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import '../chat/agent_cluster.dart';
import 'group_messaging.dart' show openGroupThread;

/// Desktop Home, agent first: who needs you, then what each agent is doing,
/// on one 720 pt measure.
class DesktopHome extends StatefulWidget {
  const DesktopHome({
    super.key,
    required this.client,
    required this.sessions,
    required this.onOpenSession,
    required this.onOpenAgent,
    required this.onRefresh,
  });

  final DaemonClient client;
  final List<SessionInfo>? sessions;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(CoordinationAgent a) onOpenAgent;
  final VoidCallback onRefresh;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  List<CoordinationAgent> _agents = const [];
  final Set<String> _busy = {};
  List<GroupSummary> _groups = const [];
  Map<String, String> _providers = const {};
  String? _activeProvider;

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((a) {
      if (mounted) setState(() => _agents = a);
    }).catchError((_) {});
    widget.client.groups().then((g) {
      if (mounted) setState(() => _groups = g);
    }).catchError((_) {});
    widget.client.getConfig().then((cfg) {
      if (!mounted) return;
      final active = cfg.profiles.where((p) => p.active).firstOrNull;
      setState(() {
        _providers = {for (final p in cfg.profiles) p.name: p.provider};
        _activeProvider = active?.provider;
      });
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
    s = s.replaceAll(RegExp(r'\b(?:of|for|to|from|on|in|about|against)\s*(?=[.,;:]|$)'), '');
    s = s.replaceAll(RegExp(r'\s+([.,;:])'), r'\1');
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

  @override
  Widget build(BuildContext context) {
    // Keep Lead's dedicated session so Lead moves into Working when active.
    final sessions = widget.sessions ?? const <SessionInfo>[];
    final crew = deriveCrew(_agents, sessions);
    final needs = [
      for (final e in crew)
        if (e.state == CrewState.needsYou) e
    ];
    final askers = {for (final e in needs) e.agent.id: e.agent.displayName};
    // A group needs you when any member is waiting on you.
    final groupAsks = [
      for (final g in _groups)
        if (g.agentIds.any(askers.containsKey)) g
    ];
    final working = [
      for (final e in crew)
        if (e.state == CrewState.working) e
    ];
    final rest = [
      for (final e in crew)
        if (e.state == CrewState.standingBy) e
    ];
    final available = [
      for (final e in rest)
        if (e.agent.available) e
    ];
    final asleep = [
      for (final e in rest)
        if (!e.agent.available) e
    ];
    return ColoredBox(
      color: AppColors.panelBg,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
            children: [
              if (crew.isEmpty && _agents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Text('No agents yet.',
                      style: sans(14, color: AppColors.fg3)),
                ),
              if (needs.isNotEmpty || groupAsks.isNotEmpty) ...[
                _label('Needs you', needs.length + groupAsks.length),
                for (final e in needs) _ask(e),
                for (final g in groupAsks)
                  _HomeRow(
                    onTap: () => openGroupThread(context,
                        client: widget.client, group: g),
                    leading: AgentCluster(ids: g.agentIds, size: 28),
                    title: g.title.trim().isEmpty ? 'Group' : g.title.trim(),
                    sub: 'Waiting on ${[
                      for (final id in g.agentIds)
                        if (askers.containsKey(id)) askers[id]
                    ].join(', ')}',
                    trailing: const QuietHand(size: 14),
                  ),
              ],
              if (working.isNotEmpty) ...[
                _label('Working', working.length),
                for (final e in working) _row(e),
              ],
              if (available.isNotEmpty) ...[
                _label('Available', available.length),
                for (final e in available) _row(e),
              ],
              if (asleep.isNotEmpty) ...[
                _label('Asleep', asleep.length),
                for (final e in asleep) _row(e),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text('$t $n',
            style: sans(12, weight: W.label, color: AppColors.fg2)),
      );

  Widget _ask(CrewEntry e) {
    final s = e.lead;
    final approval = e.isApproval && s != null;
    final busy = s != null && _busy.contains(s.id);
    final when = s == null ? '' : relativeTime(s.lastActive);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChatCard(
        children: [
          ChatCardHeader(
            title: _cleanSubtitle(e.line),
            subtitle: s == null || s.title.isEmpty ? null : s.title,
            padBottom: false,
            eyebrow: Row(children: [
              const QuietHand(size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${e.agent.displayName} asks',
                    style: sans(12, color: AppColors.fg2)),
              ),
              Text(when, style: sans(12, color: AppColors.fg3)),
            ]),
          ),
          const SizedBox(height: 16),
          ChatCardActions(buttons: [
            if (approval)
              ChatCardButton('Approve',
                  busy: busy, onTap: busy ? null : () => _approve(e)),
            ChatCardButton(approval ? 'Reply' : 'Open',
                kind: ChatCardButtonKind.secondary,
                onTap: s == null ? null : () => widget.onOpenSession(s)),
          ]),
        ],
      ),
    );
  }

  Widget _row(CrewEntry e) {
    final a = e.agent;
    final n = e.sessions.length;
    final profile = a.deskProfile ?? a.profile;
    final provider =
        (profile != null ? (_providers[profile] ?? profile) : null) ??
            _activeProvider;
    final when = e.lead == null ? '' : relativeTime(e.lead!.lastActive);
    final rawSub = e.state == CrewState.standingBy && !a.available
        ? 'Wakes when you send'
        : _cleanSubtitle(e.line);
    return _HomeRow(
      onTap: () => widget.onOpenAgent(a),
      leading: AgentMochi(a.id, size: 28),
      title: a.displayName,
      sub: rawSub.isEmpty ? 'Standing by' : rawSub,
      provider: provider,
      count: e.state == CrewState.working && n > 0
          ? (n == 1 ? '1 session' : '$n sessions')
          : null,
      when: when,
    );
  }
}

class _HomeRow extends StatefulWidget {
  const _HomeRow({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.sub,
    this.provider,
    this.count,
    this.when = '',
    this.trailing,
  });
  final Widget? trailing;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String sub;
  final String? provider;
  final String? count;
  final String when;

  @override
  State<_HomeRow> createState() => _HomeRowState();
}

class _HomeRowState extends State<_HomeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _hover ? AppColors.surface1 : Colors.transparent,
              borderRadius: BorderRadius.circular(R.of(8)),
            ),
            child: Row(children: [
              widget.leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: sans(14, weight: W.label, color: AppColors.fg1)),
                    Text(widget.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ],
                ),
              ),
              if (widget.provider != null &&
                  providerLogoAsset(widget.provider) != null) ...[
                ProviderLogo(widget.provider, size: 14, color: AppColors.fg2),
                const SizedBox(width: 8),
              ],
              if (widget.count != null) ...[
                Text(widget.count!, style: sans(12, color: AppColors.fg2)),
                const SizedBox(width: 16),
              ],
              if (widget.trailing != null) widget.trailing!,
              SizedBox(
                width: 36,
                child: Text(widget.when,
                    textAlign: TextAlign.right,
                    style: sans(12, color: AppColors.fg3)),
              ),
            ]),
          ),
        ),
      );
}
