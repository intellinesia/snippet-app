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
import 'lead/lead_state.dart' show isDedicatedLeadSession;

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

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((a) {
      if (mounted) setState(() => _agents = a);
    }).catchError((_) {});
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
    final sessions = [
      for (final s in widget.sessions ?? const <SessionInfo>[])
        if (!isDedicatedLeadSession(s.id)) s
    ];
    final crew = deriveCrew(_agents, sessions);
    final needs = [for (final e in crew) if (e.state == CrewState.needsYou) e];
    final working =
        [for (final e in crew) if (e.state == CrewState.working) e];
    final rest = [for (final e in crew) if (e.state == CrewState.standingBy) e];
    final available = [for (final e in rest) if (e.agent.available) e];
    final asleep = [for (final e in rest) if (!e.agent.available) e];
    return ColoredBox(
      color: AppColors.bg,
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
              if (needs.isNotEmpty) ...[
                _label('Needs you', needs.length),
                for (final e in needs) _ask(e),
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
            title: e.line,
            subtitle: s == null || s.title.isEmpty ? null : s.title,
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
    final when = e.lead == null ? '' : relativeTime(e.lead!.lastActive);
    return _HomeRow(
      onTap: () => widget.onOpenAgent(a),
      leading: AgentMochi(a.id, size: 28),
      title: a.displayName,
      sub: e.state == CrewState.standingBy && !a.available
          ? 'Wakes when you send'
          : e.line,
      provider: profile,
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
  });
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
                        style: sans(14,
                            weight: W.label, color: AppColors.fg1)),
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
                Text(widget.count!,
                    style: sans(12, color: AppColors.fg2)),
                const SizedBox(width: 16),
              ],
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
