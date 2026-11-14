import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../desktop_layout.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../shell_panel.dart';
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';
import 'agent_wake_panel.dart';
import 'session.dart';
import 'shell_nav.dart';

/// Every agent and session wake schedule, with keep-warm status below.
class WakesScreen extends StatefulWidget {
  const WakesScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
  });

  final DaemonClient client;
  final bool embedded;

  /// Phone drill-down back action; the screen then draws its own header.
  final VoidCallback? onBack;

  @override
  State<WakesScreen> createState() => _WakesScreenState();
}

class _WakesScreenState extends State<WakesScreen> {
  late Future<(WakeList, KeepWarmList?, List<CoordinationAgent>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Map<String, String> _sessionTitles = const {};

  Future<(WakeList, KeepWarmList?, List<CoordinationAgent>)> _load() async {
    final c = widget.client;
    final wakes = await c.wakes();
    final warm = await c
        .keepWarm()
        .then<KeepWarmList?>((v) => v)
        .catchError((_) => null);
    final agents =
        await c.coordinationAgents().catchError((_) => <CoordinationAgent>[]);
    if (warm?.entries.any((e) => e.enabled && e.ownerKind == 'session') ??
        false) {
      final sessions =
          await c.sessions().catchError((_) => <SessionInfo>[]);
      _sessionTitles = {
        for (final s in sessions)
          if (s.title.trim().isNotEmpty) s.id: s.title.trim()
      };
    }
    return (wakes, warm, agents);
  }

  void _refresh() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  String _name(String owner, List<CoordinationAgent> agents) {
    for (final a in agents) {
      if (a.id == owner) {
        return a.displayName.trim().isEmpty ? a.id : a.displayName.trim();
      }
    }
    return owner;
  }

  void _open(BuildContext ctx, String owner, String name,
      List<CoordinationAgent> agents) {
    showAgentWakeSettings(ctx,
        client: widget.client,
        owner: owner,
        name: name,
        point: lastPointerDown,
        onChanged: _refresh);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final desk = !kMobile && widget.embedded && widget.onBack == null;
    Widget page(List<Widget> children) => desk
        ? SettingsColumn(children: [
            const SettingsHeader(
              title: 'Wakes',
              subtitle: 'Agent schedules and keep-warm.',
            ),
            const SizedBox(height: S.s8),
            ...children,
          ])
        : PageBody(children: children);
    final body =
        FutureBuilder<(WakeList, KeepWarmList?, List<CoordinationAgent>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return desk ? page(const []) : const ListSkeleton();
        }
        if (snap.hasError) {
          return page([
            Padding(
              padding: const EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, S.s24),
              child: Text('${snap.error}', style: TS.ui(AppColors.danger)),
            ),
          ]);
        }
        final (wakes, warm, agents) = snap.data!;
        final warmOn = [
          for (final e in warm?.entries ?? const <KeepWarmEntry>[])
            if (e.enabled) e
        ];
        return page([
          if (wakes.wakes.isEmpty && warmOn.isEmpty)
            const EmptyState(
              icon: 'calendar-clock',
              title: 'No wakes yet',
              body:
                  'Give an agent a timetable and a brief from its menu in the crew list. It reports back to Mission Control.',
            )
          else if (wakes.wakes.isNotEmpty) ...[
            if (kMobile)
              const SettingsGroupLabel('Schedules')
            else
              const SectionLabel('Schedules'),
            ListGroup(children: [
              for (final w in wakes.wakes) _wakeRow(context, w, agents),
            ]),
          ],
          if (warmOn.isNotEmpty) ...[
            if (wakes.wakes.isNotEmpty) SizedBox(height: kMobile ? 0 : S.s20),
            if (kMobile)
              const SettingsGroupLabel('Keep warm')
            else
              const SectionLabel('Keep warm'),
            ListGroup(children: [
              for (final e in warmOn) _warmRow(context, e, agents),
            ]),
            if (warm != null && warm.calls7d > 0)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    kMobile ? S.s16 : S.s4, S.s8, kMobile ? S.s16 : S.s4, 0),
                child: Text(
                    '${warm.calls7d} warm calls in the last 7 days, ${tokensLabel(warm.cacheReadTokens7d)} tokens read from cache.',
                    style: TS.meta()),
              ),
          ],
        ]);
      },
    );
    final child = kMobile ? CardGroupScope(child: body) : body;
    if (widget.onBack == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kMobile)
          SettingsHeader(
              title: 'Wakes', compact: true, onBack: widget.onBack!)
        else
          NavBackRow(title: 'Wakes', onBack: widget.onBack!),
        Expanded(child: child),
      ],
    );
  }

  Widget _wakeRow(
      BuildContext context, WakeSchedule w, List<CoordinationAgent> agents) {
    final name = _name(w.owner, agents);
    final next = !w.enabled
        ? 'paused'
        : w.nextRunAt <= 0
            ? ''
            : w.nextRunAt * 1000 < DateTime.now().millisecondsSinceEpoch
                ? 'overdue'
                : 'next ${wakeWhen(w.nextRunAt)}';
    final sub = [
      w.scheduleText.isEmpty ? w.schedule : w.scheduleText,
      if (next.isNotEmpty) next,
    ].join(' · ');
    return Builder(
      builder: (ctx) => ListRow(
        key: ValueKey('wake-${w.owner}'),
        title: name,
        subtitle: w.lastError != null ? '$sub · ${w.lastError}' : sub,
        leading: kMobile
            ? V5IconTile('calendar-clock',
                color: w.enabled ? AppColors.fg2 : AppColors.fg4)
            : AppIcon('calendar-clock',
                size: 19, color: w.enabled ? AppColors.fg3 : AppColors.fg4),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (w.lastStatus != null)
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: wakeStatusColor(w.lastStatus),
                    shape: BoxShape.circle)),
          const SizedBox(width: S.s6),
          Text(w.ownerKind, style: TS.meta()),
        ]),
        onTap: () => _open(ctx, w.owner, name, agents),
      ),
    );
  }

  Widget _warmRow(
      BuildContext context, KeepWarmEntry e, List<CoordinationAgent> agents) {
    final session = e.ownerKind == 'session';
    final name = session
        ? (_sessionTitles[e.owner] ??
            _sessionTitles[e.sessionId] ??
            'Untitled conversation')
        : _name(e.owner, agents);
    final reason = e.reason;
    final sub = [
      if (session) 'Conversation',
      if (reason != null)
        reason == 'quiet hours'
            ? 'Paused for quiet hours'
            : '${reason[0].toUpperCase()}${reason.substring(1)}'
      else if (e.lastWarmAt != null)
        'Warmed ${wakeWhen(e.lastWarmAt!)}'
      else
        'Every ${e.intervalMinutes} min',
    ].join(' · ');
    return Builder(
      builder: (ctx) => ListRow(
        key: ValueKey('warm-${e.owner}'),
        title: name,
        subtitle: sub,
        leading: kMobile
            ? const V5IconTile('gauge')
            : AppIcon('gauge', size: 19, color: AppColors.fg3),
        trailing: e.warms > 0
            ? Text('${e.warms} warm${e.warms == 1 ? '' : 's'}',
                style: TS.meta())
            : null,
        onTap: session
            ? () => unawaited(_sessionWarmMenu(ctx, e, name))
            : () => _open(ctx, e.owner, name, agents),
      ),
    );
  }

  Future<void> _sessionWarmMenu(
      BuildContext ctx, KeepWarmEntry e, String name) async {
    final picked = await showAppMenu<String>(ctx,
        anchor: ctx,
        point: kMobile ? null : lastPointerDown,
        items: [
          appMenuItem(
              value: 'open', label: 'Open conversation', icon: 'message'),
          appMenuItem(
              value: 'off',
              label: 'Stop keeping warm',
              icon: 'gauge',
              danger: true),
        ]);
    if (!mounted || picked == null) return;
    final id = e.sessionId.isNotEmpty ? e.sessionId : e.owner;
    if (picked == 'open') {
      final tab = openSessionInTab;
      if (!kMobile && tab != null) {
        tab(widget.client, id, name);
        return;
      }
      unawaited(presentScreen(context,
          builder: (_, close) => SessionScreen(
              client: widget.client,
              sessionId: id,
              title: name,
              onMenu: close)));
      return;
    }
    try {
      await widget.client.setKeepWarm(e.owner, enabled: false);
    } catch (err) {
      if (mounted) toast(context, '$err', danger: true);
      return;
    }
    _refresh();
  }
}
