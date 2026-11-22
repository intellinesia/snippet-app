import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../mochi.dart';
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
import '../tap_detector.dart';

/// Every agent and session wake schedule, or with [keepWarm] the sessions
/// kept warm.
class WakesScreen extends StatefulWidget {
  const WakesScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.keepWarm = false,
    this.onBack,
    this.tab = false,
  });

  final DaemonClient client;
  final bool embedded;
  final bool keepWarm;

  /// Phone drill-down back action; the screen then draws its own header.
  final VoidCallback? onBack;

  /// Shown as a workspace tab rather than inside Settings.
  final bool tab;

  @override
  State<WakesScreen> createState() => _WakesScreenState();
}

class _WakesScreenState extends State<WakesScreen> {
  late Future<(WakeBook, KeepWarmList?, List<CoordinationAgent>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Map<String, String> _sessionTitles = const {};
  List<CoordinationAgent>? _agents;

  Future<(WakeBook, KeepWarmList?, List<CoordinationAgent>)> _load() async {
    final c = widget.client;
    final wakes = await c.wakeBook();
    final warm = await c
        .keepWarm()
        .then<KeepWarmList?>((v) => v)
        .catchError((_) => null);
    final agents =
        await c.coordinationAgents().catchError((_) => <CoordinationAgent>[]);
    final needTitles =
        (warm?.entries.any((e) => e.enabled && e.ownerKind == 'session') ??
                false) ||
            wakes.every.any((w) => w.ownerKind == 'session') ||
            wakes.once.any((w) => w.ownerKind == 'session');
    if (needTitles) {
      final sessions = await c.sessions().catchError((_) => <SessionInfo>[]);
      _sessionTitles = {
        for (final s in sessions)
          if (s.title.trim().isNotEmpty) s.id: s.title.trim()
      };
    }
    _agents = agents;
    return (wakes, warm, agents);
  }

  void _refresh() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  String _name(String owner, List<CoordinationAgent> agents) {
    if (owner == 'mission-control') return 'Mission Control';
    final title = _sessionTitles[owner];
    if (title != null) return title;
    for (final a in agents) {
      if (a.id == owner) {
        return a.displayName.trim().isEmpty ? a.id : a.displayName.trim();
      }
    }
    // Ids are lowercase; a bare id still reads as a name.
    return owner.isEmpty ? owner : owner[0].toUpperCase() + owner.substring(1);
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
    final warmPage = widget.keepWarm;
    final title = warmPage ? 'Keep warm' : 'Wakes';
    final subtitle = warmPage
        ? 'Sessions that hold their prompt cache while idle.'
        : 'When each agent wakes on its own.';
    Widget page(List<Widget> children) => !kMobile && widget.tab
        ? ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Text(title,
                            style: sans(kMobile ? 20 : 16,
                                weight: FontWeight.w600, color: AppColors.fg1)),
                        const SizedBox(height: 4),
                        Text(subtitle, style: sans(12.5, color: AppColors.fg4)),
                        const SizedBox(height: 12),
                        ...children,
                      ]),
                ),
              ),
            ),
          ])
        : desk
            ? SettingsColumn(children: [
                SettingsHeader(title: title, subtitle: subtitle, actions: [
                  if (!warmPage && _agents != null)
                    Builder(
                        builder: (ctx) => Btn('New wake',
                            small: true,
                            variant: BtnVariant.secondary,
                            onTap: () => _newWake(ctx, _agents!))),
                ]),
                SizedBox(height: S.s8),
                ...children,
              ])
            : PageBody(children: children);
    final body =
        FutureBuilder<(WakeBook, KeepWarmList?, List<CoordinationAgent>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return desk ? page(const []) : const ListSkeleton();
        }
        if (snap.hasError) {
          return page([
            Padding(
              padding: EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, S.s24),
              child: Text('${snap.error}', style: TS.ui(AppColors.danger)),
            ),
          ]);
        }
        final (book, warm, agents) = snap.data!;
        final warmOn = [
          for (final e in warm?.entries ?? const <KeepWarmEntry>[])
            if (e.enabled) e
        ];
        final warmGroup = SettingsGroup(
          header: 'Keep warm',
          footer: warm != null && warm.calls7d > 0 && warmOn.isNotEmpty
              ? '${warm.calls7d} warm calls in the last 7 days, ${tokensLabel(warm.cacheReadTokens7d)} tokens read from cache.'
              : null,
          children: [
            if (warmOn.isEmpty)
              const SettingsRow(
                key: Key('keep-warm-empty'),
                label: 'No session is kept warm',
                sub:
                    'A warm session keeps its prompt cache while idle, so the next turn is cheaper.',
              )
            else
              for (final e in warmOn) _warmRow(context, e, agents),
          ],
        );
        if (warmPage) return page([warmGroup]);
        if (book.isEmpty) {
          // One empty state that fills the pane; a scrolling column cannot centre it.
          final empty = EmptyState(
            icon: 'calendar-clock',
            title: 'Nothing wakes on its own yet',
            body:
                'Add a schedule, a one-off reminder or a watch and agents act without being asked.',
            action: Btn('New wake', onTap: () => _newWake(context, agents)),
          );
          if (!desk) return empty;
          return page([
            SettingsGroup(header: 'Schedules', children: [
              SettingsRow(
                icon: 'calendar-clock',
                label: 'Nothing wakes on its own yet',
                sub: 'Add a schedule, a one-off reminder or a watch.',
                onTap: () => _newWake(context, agents),
              ),
            ]),
            warmGroup,
          ]);
        }
        return page([
          SettingsGroup(header: 'Schedules', children: [
            for (final w in book.every) _wakeRow(context, w, agents),
            if (book.every.isEmpty)
              const SettingsRow(
                  label: 'No schedules',
                  sub: 'Agents and sessions on a timetable appear here.'),
            if (kMobile)
              Builder(
                  builder: (ctx) => SettingsRow(
                      key: const Key('wake-new'),
                      icon: 'plus',
                      label: 'New wake',
                      onTap: () => _newWake(ctx, agents))),
          ]),
          if (book.once.isNotEmpty)
            SettingsGroup(header: 'Once', children: [
              for (final w in book.once) _onceRow(context, w, agents),
            ]),
          if (book.watches.isNotEmpty)
            SettingsGroup(header: 'Watches', children: [
              for (final w in book.watches) _watchRow(context, w, agents),
            ]),
          warmGroup,
        ]);
      },
    );
    final child = kMobile ? CardGroupScope(child: body) : body;
    if (widget.onBack == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kMobile)
          SettingsHeader(title: title, compact: true, onBack: widget.onBack!)
        else
          NavBackRow(title: title, onBack: widget.onBack!),
        Expanded(child: child),
      ],
    );
  }

  // A list of schedules reads better as a clock time than a countdown.
  static String _wakeAt(int unixSec) {
    final t = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final now = DateTime.now();
    final days = DateTime(t.year, t.month, t.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (days > 6) return 'in ${days}d';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final day = switch (days) {
      0 => 'today',
      1 => 'tomorrow',
      _ => names[t.weekday - 1],
    };
    return '$day $hm';
  }

  Widget _ownerLeading(String owner, String kind, bool on, String icon) {
    if (kind != 'agent') {
      return Opacity(opacity: on ? 1 : 0.5, child: V5IconTile(icon));
    }
    // Every agent has a face, so the hashed default stands in for unset ones.
    final character = agentCharacterFor(owner) ?? defaultAgentCharacter(owner);
    return Opacity(
        opacity: on ? 1 : 0.5,
        child: AgentCharacter(character, size: kMobile ? 24 : 20));
  }

  Future<void> _setEnabled(String id, bool on, {bool watch = false}) async {
    try {
      await widget.client.patchWake(id, {'enabled': on});
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
    if (mounted) _refresh();
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
                : 'next ${_wakeAt(w.nextRunAt)}';
    final sub = [
      if (w.name != null || w.legacy)
        name
      else
        w.scheduleText.isEmpty ? w.schedule : w.scheduleText,
      if (w.legacy && w.scheduleText.isNotEmpty) w.scheduleText,
      if (next.isNotEmpty) next,
    ].join(' · ');
    final label = w.name ?? (w.legacy && w.title.isNotEmpty ? w.title : name);
    return Builder(
      builder: (ctx) => SettingsRow(
        key: ValueKey('wake-${w.id.isEmpty ? w.owner : w.id}'),
        label: label,
        sub: w.lastError != null ? '$sub · ${w.lastError}' : sub,
        leading: _ownerLeading(w.owner, w.ownerKind, w.enabled, 'repeat'),
        trailing: w.id.isEmpty
            ? null
            : AppSwitch(
                on: w.enabled, onChanged: (on) => _setEnabled(w.id, on)),
        onTap: () => _open(ctx, w.owner, name, agents),
      ),
    );
  }

  Widget _onceRow(
      BuildContext context, OnceWake w, List<CoordinationAgent> agents) {
    final name = _name(w.owner, agents);
    final due = w.dueAt == null ? '' : 'due ${_wakeAt(w.dueAt!)}';
    return SettingsRow(
      key: ValueKey('once-${w.id}'),
      label: w.title.isEmpty ? 'One-off wake' : w.title,
      sub: [name, if (due.isNotEmpty) due].join(' · '),
      leading: _ownerLeading(w.owner, w.ownerKind, true, 'clock'),
      trailing: TapDetector(
        key: ValueKey('once-cancel-${w.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _cancelOnce(w),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 44 : 32),
          child: Center(
              widthFactor: 1, child: Text('Cancel', style: TS.meta())),
        ),
      ),
    );
  }

  Future<void> _cancelOnce(OnceWake w) async {
    try {
      await widget.client.deleteWake(w.id);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
    if (mounted) _refresh();
  }

  Widget _watchRow(
      BuildContext context, AgentWatch w, List<CoordinationAgent> agents) {
    final name = _name(w.owner, agents);
    final sub = [
      name,
      w.modeLabel,
      if (!w.enabled) 'paused' else '${w.firesLastDay} fires today',
    ].join(' · ');
    return Builder(
      builder: (ctx) => SettingsRow(
        key: ValueKey('watch-${w.id}'),
        label: w.name,
        sub: w.lastError != null ? '$sub · ${w.lastError}' : sub,
        leading: _ownerLeading(w.owner, 'agent', w.enabled, 'eye'),
        trailing: AppSwitch(
            on: w.enabled,
            onChanged: (on) => _setEnabled(w.id, on, watch: true)),
        onTap: () => _open(ctx, w.owner, name, agents),
      ),
    );
  }

  /// A new wake starts from its owner: an agent, Mission Control or a session
  /// is picked, then the owner's wake panel takes the schedule.
  Future<void> _newWake(
      BuildContext ctx, List<CoordinationAgent> agents) async {
    final picked = await showAppMenu<String>(ctx,
        anchor: ctx,
        point: kMobile ? null : lastPointerDown,
        items: [
          appMenuHeading<String>('Wake who?'),
          appMenuItem(
              value: 'mission-control',
              label: 'Mission Control',
              icon: 'sparkles'),
          for (final a in agents)
            appMenuItem(
                value: a.id,
                label: a.displayName.trim().isEmpty ? a.id : a.displayName,
                icon: 'agent'),
        ]);
    if (!mounted || picked == null) return;
    // ignore: use_build_context_synchronously
    _open(ctx, picked, _name(picked, agents), agents);
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
    final warmed = e.lastWarmAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(e.lastWarmAt! * 1000);
    final sub = [
      if (reason != null)
        reason == 'quiet hours'
            ? 'Paused for quiet hours'
            : '${reason[0].toUpperCase()}${reason.substring(1)}'
      else ...[
        'Every ${e.intervalMinutes} min',
        if (warmed != null)
          'Warmed ${warmed.hour.toString().padLeft(2, '0')}:${warmed.minute.toString().padLeft(2, '0')}',
      ],
    ].join(' · ');
    return Builder(
      builder: (ctx) => SettingsRow(
        key: ValueKey('warm-${e.owner}'),
        label: name,
        sub: sub,
        leading: session ? null : const V5IconTile('gauge'),
        trailing: session
            ? TapDetector(
                key: ValueKey('warm-open-${e.owner}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openConversation(e, name),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: kMobile ? 44 : 32),
                  child: Center(
                    widthFactor: 1,
                    child: Text('Open conversation', style: TS.meta()),
                  ),
                ),
              )
            : (e.warms > 0
                ? Text('${e.warms} warm${e.warms == 1 ? '' : 's'}',
                    style: TS.meta())
                : null),
        onTap: session
            ? () => unawaited(_sessionWarmMenu(ctx, e, name))
            : () => _open(ctx, e.owner, name, agents),
      ),
    );
  }

  void _openConversation(KeepWarmEntry e, String name) {
    final id = e.sessionId.isNotEmpty ? e.sessionId : e.owner;
    final tab = openSessionInTab;
    if (!kMobile && tab != null) {
      tab(widget.client, id, name);
      return;
    }
    unawaited(presentScreen(context,
        builder: (_, close) => SessionScreen(
            client: widget.client, sessionId: id, title: name, onMenu: close)));
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
    if (picked == 'open') return _openConversation(e, name);
    try {
      await widget.client.setKeepWarm(e.owner, enabled: false);
    } catch (err) {
      if (mounted) toast(context, '$err', danger: true);
      return;
    }
    _refresh();
  }
}
