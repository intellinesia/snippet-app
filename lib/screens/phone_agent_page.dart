import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/chat_card.dart';
import '../chat/signal_row.dart' show prettyProfile;
import '../mochi.dart';
import '../models.dart';
import '../quiet.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_profile_panel.dart';
import 'lead/coordination_agent_detail.dart';
import 'session_list_row.dart' show sessionNeedsYou;
import 'shell_nav.dart' show sessionBusy;

/// Phone agent page: who the agent is and what it is doing, with the
/// conversation one tap away. Back from the conversation returns here.
class PhoneAgentPage extends StatefulWidget {
  const PhoneAgentPage({
    super.key,
    required this.agent,
    required this.client,
    required this.sessions,
    required this.onClose,
    required this.onOpenSession,
    required this.onAllSessions,
    this.onDecide,
  });

  final CoordinationAgent agent;
  final DaemonClient client;
  final List<SessionInfo> sessions;
  final VoidCallback onClose;
  final void Function(SessionInfo s) onOpenSession;
  final VoidCallback onAllSessions;
  final Future<bool> Function(SessionInfo s, bool approve)? onDecide;

  @override
  State<PhoneAgentPage> createState() => _PhoneAgentPageState();
}

class _PhoneAgentPageState extends State<PhoneAgentPage> {
  bool _chat = false;
  bool _busy = false;

  CoordinationAgent get a => widget.agent;
  String get _name =>
      a.displayName.trim().isEmpty ? a.id : a.displayName.trim();

  @override
  Widget build(BuildContext context) {
    if (_chat) {
      return CoordinationAgentDetail(
        key: const ValueKey('agent-detail'),
        agent: a,
        client: widget.client,
        embedded: false,
        onClose: () => setState(() => _chat = false),
      );
    }
    final mine = [
      for (final s in widget.sessions)
        if (s.displayAgentId == a.id) s
    ]..sort((x, y) => y.lastActive.compareTo(x.lastActive));
    final ask = mine.where(sessionNeedsYou).firstOrNull;
    final busy = mine.any((s) => !s.settled && sessionBusy(s));
    final state = ask != null || a.needsYou > 0
        ? 'Needs you'
        : busy
            ? 'Working'
            : a.available
                ? 'Available'
                : 'Asleep';
    final profile = a.deskProfile ?? a.profile;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconBtn('chevron-left',
                  size: 48, iconSize: 22, tooltip: 'Back', onTap: widget.onClose),
            ),
            Center(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(R.of(20)),
                  child: AgentMochi(a.id, size: 72)),
            ),
            const SizedBox(height: 12),
            Text(_name,
                textAlign: TextAlign.center,
                style: sans(24, weight: W.label, color: AppColors.fg1)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(state, style: sans(14, color: AppColors.fg2)),
              if (profile != null && profile.trim().isNotEmpty) ...[
                Text(' · ', style: sans(14, color: AppColors.fg3)),
                if (providerLogoAsset(profile) != null) ...[
                  ProviderLogo(profile, size: 14, color: AppColors.fg2),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                      [prettyProfile(profile), if ((a.deskModel ?? '').trim().isNotEmpty) a.deskModel!.trim()].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14, color: AppColors.fg2)),
                ),
              ],
            ]),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                    child: Btn('Message', onTap: () => setState(() => _chat = true))),
                const SizedBox(width: 8),
                Expanded(
                  child: Btn('Profile',
                      variant: BtnVariant.secondary,
                      onTap: () => showAgentProfileSettings(context,
                          client: widget.client, agent: a, name: _name)),
                ),
              ]),
            ),
            if (ask != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _askCard(ask),
              ),
            ],
            if (mine.isNotEmpty) ...[
              const QuietSectionLabel('Sessions'),
              for (final s in mine.take(6))
                QuietRow(
                  title: s.title.isEmpty ? 'Untitled session' : s.title,
                  meta: relativeTime(s.lastActive),
                  leading: sessionNeedsYou(s)
                      ? const QuietHand(size: 20)
                      : AppIcon(
                          !s.settled && sessionBusy(s) ? 'circle' : 'check',
                          size: 20,
                          color: AppColors.fg3),
                  trailing:
                      AppIcon('chevron-right', size: 16, color: AppColors.fg3),
                  onTap: () => widget.onOpenSession(s),
                ),
              QuietRow(title: 'All sessions', onTap: widget.onAllSessions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _askCard(SessionInfo s) {
    final text = '${s.attention?['text'] ?? ''}'.trim();
    final approval = s.attention?['type'] == 'approval' && widget.onDecide != null;
    return ChatCard(children: [
      ChatCardHeader(
        title: text.isEmpty ? s.title : text,
        subtitle: text.isEmpty || s.title.isEmpty ? null : s.title,
        eyebrow: Row(children: [
          const QuietHand(size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text('$_name asks',
                  style: sans(13, color: AppColors.fg2))),
          Text(relativeTime(s.lastActive),
              style: sans(13, color: AppColors.fg3)),
        ]),
      ),
      ChatCardActions(buttons: [
        if (approval)
          ChatCardButton('Approve', busy: _busy, onTap: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await widget.onDecide!(s, true);
                  if (mounted) setState(() => _busy = false);
                }),
        ChatCardButton(approval ? 'Reply' : 'Open',
            kind: ChatCardButtonKind.secondary,
            onTap: () => widget.onOpenSession(s)),
      ]),
    ]);
  }
}
