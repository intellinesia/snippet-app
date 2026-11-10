import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/agent_wake_panel.dart';
import 'screens/agent_appearance.dart';
import 'screens/agent_model_page.dart';
import 'crew_status.dart';
import 'mochi.dart';
import 'models.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// The provider logo for an agent's inference profile, or nothing when the
/// profile is unset or unknown.
class AgentProviderMark extends StatefulWidget {
  const AgentProviderMark(
      {super.key,
      required this.client,
      required this.profile,
      this.size = 14,
      this.orActive = false});

  final DaemonClient client;
  final String? profile;
  final double size;

  /// With no profile, show the daemon's active (default) profile instead.
  final bool orActive;

  @override
  State<AgentProviderMark> createState() => _AgentProviderMarkState();
}

class _AgentProviderMarkState extends State<AgentProviderMark> {
  InferenceProfile? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(AgentProviderMark old) {
    super.didUpdateWidget(old);
    if (old.profile != widget.profile || old.client != widget.client) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final name = widget.profile?.trim() ?? '';
    if (name.isEmpty && !widget.orActive) {
      if (_resolved != null) setState(() => _resolved = null);
      return;
    }
    try {
      final cfg = await widget.client.getConfig();
      if (!mounted || widget.profile?.trim() != name) return;
      InferenceProfile? hit;
      for (final p in cfg.profiles) {
        if (name.isEmpty ? p.active : p.name == name) hit = p;
      }
      setState(() => _resolved = hit);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _resolved;
    if (p == null || p.provider.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: 'Model ${p.name}, ${p.provider}',
      excludeSemantics: true,
      child: ProviderLogo(p.provider, size: widget.size),
    );
  }
}

Color crewColor(CrewState s) => switch (s) {
      CrewState.needsYou => AppColors.run,
      CrewState.working => AppColors.accent,
      CrewState.standingBy => AppColors.fg4,
    };

/// Needs-you first, then working, then standing by; each group keeps the
/// agent order the daemon gave.
List<CrewEntry> crewOrdered(List<CrewEntry> c) => [
      for (final s in CrewState.values) ...c.where((e) => e.state == s),
    ];

/// Colour and delete for one agent, from a right-click, long-press or the
/// card's more button. Deleting is refused by the daemon while the agent is
/// still on an unfinished task, and its message is shown as is.
Future<void> showCrewAgentMenu(
  BuildContext context, {
  required DaemonClient client,
  required CoordinationAgent agent,
  Offset? point,
  VoidCallback? onDeleted,
}) async {
  final picked = await showAppMenu<String>(
    context,
    point: point,
    anchor: point == null ? context : null,
    items: [
      appMenuItem(
          value: 'nickname',
          icon: 'edit',
          label: agent.nickname == null ? 'Set nickname' : 'Edit nickname'),
      appMenuItem(value: 'avatar', icon: 'sparkles', label: 'Change avatar'),
      appMenuItem(value: 'color', icon: 'sparkles', label: 'Change colour'),
      appMenuItem(
          value: 'model', icon: 'cpu', label: 'Change inference profile'),
      appMenuItem(
          value: 'wakes', icon: 'calendar-clock', label: 'Wakes and reporting'),
      appMenuItem(
          value: 'delete', icon: 'trash', label: 'Delete agent', danger: true),
    ],
  );
  if (!context.mounted || picked == null) return;
  await runCrewAgentAction(context, picked,
      client: client, agent: agent, point: point, onDeleted: onDeleted);
}

/// One agent action by name: nickname, color, wakes, model or delete. The crew
/// menu and the agent page's Actions both go through here.
Future<void> runCrewAgentAction(
  BuildContext context,
  String picked, {
  required DaemonClient client,
  required CoordinationAgent agent,
  Offset? point,
  VoidCallback? onDeleted,
}) async {
  final name =
      agent.displayName.trim().isEmpty ? agent.id : agent.displayName.trim();
  if (picked == 'nickname') {
    final next = await promptText(context,
        title:
            'Nickname for ${agent.fullName.trim().isEmpty ? agent.id : agent.fullName.trim()}',
        initial: agent.nickname ?? '',
        hint: 'Leave empty to use the name',
        anchored: true,
        point: point);
    if (next == null || next == (agent.nickname ?? '')) return;
    try {
      await client.setAgentNickname(agent.id, next.isEmpty ? null : next);
      onDeleted?.call();
    } catch (e) {
      if (context.mounted) toast(context, '$e', danger: true);
    }
  } else if (picked == 'color' || picked == 'avatar') {
    await showAgentAppearance(
        context,
        client,
        agent.id,
        name,
        picked == 'avatar'
            ? AgentAppearancePart.avatar
            : AgentAppearancePart.colour,
        point: point);
  } else if (picked == 'wakes') {
    await showAgentWakeSettings(context,
        client: client,
        owner: agent.id,
        name: name,
        point: point,
        onChanged: onDeleted);
  } else if (picked == 'model') {
    await _pickCrewModel(context, client, agent, name, point, onDeleted);
  } else if (picked == 'delete') {
    final ok = await confirmAction(context,
        title: 'Delete $name?',
        body:
            "This removes the agent, its identity and its notes. Its past task history loses it too. This can't be undone.",
        confirmLabel: 'Delete agent');
    if (!ok || !context.mounted) return;
    try {
      await client.deleteAgent(agent.id);
      if (context.mounted) toast(context, 'Deleted $name');
      onDeleted?.call();
    } catch (e) {
      if (context.mounted) toast(context, '$e', danger: true);
    }
  }
}

Future<void> _pickCrewModel(
    BuildContext context,
    DaemonClient client,
    CoordinationAgent agent,
    String name,
    Offset? point,
    VoidCallback? onChanged) async {
  if (kMobile) {
    await showAgentModelPage(context, client: client, agent: agent, name: name);
    onChanged?.call();
    return;
  }
  ServerConfig cfg;
  try {
    cfg = await client.getConfig();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
    return;
  }
  if (!context.mounted) return;
  if (cfg.profiles.isEmpty) {
    toast(context, 'No models configured');
    return;
  }
  final picked = await showAppMenu<String>(
    context,
    point: point,
    anchor: point == null ? context : null,
    minWidth: 260,
    maxWidth: 360,
    items: [
      appMenuHeading<String>('Works on'),
      appMenuRow<String>(
          value: '',
          icon: 'sparkles',
          label: 'Routing default',
          description: "Your Routing settings for desks",
          selected: agent.profile == null),
      for (final p in cfg.profiles)
        appMenuRow<String>(
            value: p.name,
            icon: 'provider:${p.provider}',
            label: p.name,
            description: '${p.provider} \u00b7 ${p.model}',
            selected: p.name == agent.profile),
    ],
  );
  if (picked == null || picked == (agent.profile ?? '')) return;
  try {
    await client.setAgentProfile(agent.id, picked.isEmpty ? null : picked);
    if (context.mounted) toast(context, 'Model updated');
    onChanged?.call();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
  }
}

/// Collapsed crew: overlapping avatars that open the roster in a popover on
/// hover or tap.
class CrewStack extends StatefulWidget {
  const CrewStack({
    super.key,
    required this.entries,
    required this.onOpen,
    this.onMenu,
    this.onNew,
  });

  final List<CrewEntry> entries;
  final ValueChanged<CoordinationAgent> onOpen;
  final Future<void> Function(BuildContext, CoordinationAgent, Offset)? onMenu;
  final VoidCallback? onNew;

  @override
  State<CrewStack> createState() => _CrewStackState();
}

class _CrewStackState extends State<CrewStack> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _hide;
  bool _pinned = false;

  void _show() {
    _hide?.cancel();
    if (!_portal.isShowing) _portal.show();
  }

  void _later() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 220), () {
      if (mounted && !_pinned && _portal.isShowing) _portal.hide();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = crewOrdered(widget.entries);
    final shown = list.take(4).toList();
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(14, -6),
          child: Align(
            alignment: Alignment.topLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Motion.fast,
              curve: Curves.easeOutCubic,
              builder: (_, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(
                    scale: 0.96 + 0.04 * t,
                    alignment: Alignment.topLeft,
                    child: child),
              ),
              child: MouseRegion(
                onEnter: (_) => _show(),
                onExit: (_) => _later(),
                child: Material(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 0,
                  child: Container(
                    width: 412,
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.lineStrong),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(children: [
                            Text('Crew',
                                style: sans(12,
                                    weight: W.label, color: AppColors.fg3)),
                            const SizedBox(width: 6),
                            Text('${list.length}',
                                style: mono(11, color: AppColors.fg4)),
                          ]),
                        ),
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          for (final e in list)
                            _CrewTile(
                              e,
                              onTap: () {
                                _portal.hide();
                                widget.onOpen(e.agent);
                              },
                              onMenu: widget.onMenu == null
                                  ? null
                                  : (ctx, a, p) async {
                                      _pinned = true;
                                      _hide?.cancel();
                                      try {
                                        await widget.onMenu!(ctx, a, p);
                                      } finally {
                                        _pinned = false;
                                        if (mounted) _later();
                                      }
                                    },
                            ),
                          if (widget.onNew != null)
                            _NewAgentTile(onTap: () {
                              _portal.hide();
                              widget.onNew!();
                            }),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _later(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _portal.isShowing ? _portal.hide() : _portal.show(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: SizedBox(
                height: 22,
                width: 22.0 + 14 * (shown.length.clamp(1, 4) - 1),
                child: Stack(children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: 14.0 * i,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: AppColors.bg, shape: BoxShape.circle),
                        child: AgentMochi(shown[i].agent.id, size: 18),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrewTile extends StatelessWidget {
  const _CrewTile(this.e, {required this.onTap, this.onMenu});
  final CrewEntry e;
  final VoidCallback onTap;
  final void Function(BuildContext, CoordinationAgent, Offset)? onMenu;

  @override
  Widget build(BuildContext context) {
    final idle = e.state == CrewState.standingBy;
    return SizedBox(
      width: 194,
      height: 52,
      child: HoverSurface(
        rest: Colors.transparent,
        hoverColor: AppColors.surface3,
        radius: 10,
        onTap: onTap,
        onSecondaryTapDown: onMenu == null
            ? null
            : (d) => onMenu!(context, e.agent, d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Opacity(
                opacity: idle ? .85 : 1,
                child: AgentMochi(e.agent.id, size: 30)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.agent.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, weight: W.label, color: AppColors.fg1)),
                  if (e.line.isNotEmpty)
                    Text(e.line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12,
                            color: idle ? AppColors.fg4 : crewColor(e.state))),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NewAgentTile extends StatelessWidget {
  const _NewAgentTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 194,
        height: 52,
        child: HoverSurface(
          rest: Colors.transparent,
          hoverColor: AppColors.surface3,
          radius: 10,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.lineStrong),
                ),
                child: AppIcon('plus', size: 14, color: AppColors.fg3),
              ),
              const SizedBox(width: 10),
              Text('New agent', style: sans(13, color: AppColors.fg3)),
            ]),
          ),
        ),
      );
}
