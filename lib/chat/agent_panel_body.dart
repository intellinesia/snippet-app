import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../screens/tasks/task_common.dart' show openTaskDetail;
import '../settings_form.dart' show Grouped, SettingsSwitch;
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';
import 'mc_panel_sections.dart';

/// One row of the panel's Settings section.
class AgentSettingRow {
  const AgentSettingRow(this.icon, this.label, this.sub, this.onTap);
  final String icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
}

/// The desktop agent panel, in the session panel's language: identity, a
/// presence card, quick links, then accordion sections. Visual constants
/// follow `session_rail.dart`.
class AgentPanelBody extends StatefulWidget {
  const AgentPanelBody({
    super.key,
    required this.client,
    required this.agentId,
    required this.name,
    required this.sub,
    required this.settings,
    this.agent,
    this.header,
    this.onInbox,
    this.onBoard,
    this.onMemory,
    this.onTasks,
    this.onDesk,
    this.onNickname,
    this.onDelete,
    this.onHeroLongPress,
    this.sessionId,
    this.onModel,
  });

  /// Lead's session, for its model and cold-resume rows.
  final String? sessionId;
  final VoidCallback? onModel;
  final DaemonClient client;
  final String agentId;
  final String name;
  final String sub;
  final CoordinationAgent? agent;
  final List<AgentSettingRow> settings;

  /// Shown above the presence card (Lead's context meter).
  final Widget? header;
  final VoidCallback? onInbox;
  final VoidCallback? onBoard;
  final VoidCallback? onMemory;
  final VoidCallback? onTasks;
  final VoidCallback? onDesk;
  final VoidCallback? onNickname;
  final VoidCallback? onDelete;
  final VoidCallback? onHeroLongPress;

  @override
  State<AgentPanelBody> createState() => _AgentPanelBodyState();
}

const String _openPref = 'agent_panel_open_';
final Map<String, bool> _open = {};

class _AgentPanelBodyState extends State<AgentPanelBody> {
  List<TaskItem> _tasks = const [];
  List<SessionInfo> _sessions = const [];
  WakeSchedule? _wake;
  KeepWarmEntry? _warm;
  bool _warmLoaded = false;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AgentPanelBody old) {
    super.didUpdateWidget(old);
    final p = widget.agent?.presence, o = old.agent?.presence;
    if (old.agentId != widget.agentId ||
        p?.state != o?.state ||
        p?.detail != o?.detail) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.agentId;
    _loadedFor = id;
    final c = widget.client;
    final mc = _mc;
    final r = await Future.wait<Object?>([
      c
          .tasks(agentId: mc ? null : id, limit: mc ? 300 : 60)
          .catchError((_) => <TaskItem>[]),
      c.wake(id).catchError((_) => null),
      c.keepWarmFor(id).catchError((_) => null),
      if (mc) c.sessions().catchError((_) => <SessionInfo>[]),
    ]);
    if (!mounted || _loadedFor != id) return;
    setState(() {
      if (mc) _sessions = r[3] as List<SessionInfo>;
      _tasks = r[0] as List<TaskItem>;
      _wake = r[1] as WakeSchedule?;
      _warm = r[2] as KeepWarmEntry?;
      _warmLoaded = true;
    });
  }

  Future<void> _setWarm(bool on) async {
    final before = _warm;
    setState(() => _warmLoaded = true);
    try {
      final e = await widget.client.setKeepWarm(widget.agentId, enabled: on);
      if (mounted) setState(() => _warm = e);
    } catch (e) {
      if (mounted) {
        setState(() => _warm = before);
        toast(context, '$e', danger: true);
      }
    }
  }

  static String _elapsed(DateTime since) {
    final d = DateTime.now().difference(since);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dayOf(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    if (days == 0) return 'Today';
    if (days < 7) return _days[t.weekday - 1];
    return '${t.day} ${_months[t.month - 1]}';
  }

  static String _nextAt(int unix) {
    final t = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    final d = t.difference(DateTime.now());
    if (d.isNegative) return 'overdue';
    final hm = '${_two(t.hour)}:${_two(t.minute)}';
    if (d.inHours < 24) return hm;
    return '${_days[t.weekday - 1]} $hm';
  }

  bool get _mc =>
      widget.agentId == 'lead' ||
      (widget.agent?.isLead ?? false);

  // ---- header ---------------------------------------------------------

  Widget _identity() {
    final hasMenu = (widget.onDesk != null && !_mc) ||
        widget.onNickname != null ||
        widget.onDelete != null;
    return Semantics(
      label: '${widget.name}, ${widget.sub}',
      container: true,
      child: GestureDetector(
        onLongPress: widget.onHeroLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 0, 0),
          child: Row(children: [
            AgentMochi(widget.agentId, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            sans(15, weight: W.strong, color: AppColors.fg1)),
                    const SizedBox(height: 2),
                    Text(widget.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ]),
            ),
            if (hasMenu)
              Builder(
                builder: (bc) => IconBtn('ellipsis',
                    size: 30,
                    iconSize: 16,
                    tooltip: 'More',
                    onTap: () => _menu(bc)),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext anchor) async {
    final pick = await showAppMenu<String>(anchor,
        anchor: anchor,
        minWidth: 180,
        items: [
          if (widget.onNickname != null)
            appMenuItem(value: 'nickname', icon: 'edit', label: 'Nickname'),
          if (widget.onDelete != null)
            appMenuItem(
                value: 'delete',
                icon: 'trash',
                label: 'Delete agent',
                danger: true),
        ]);
    switch (pick) {
      case 'desk':
        widget.onDesk?.call();
      case 'nickname':
        widget.onNickname?.call();
      case 'delete':
        widget.onDelete?.call();
    }
  }

  // ---- presence -------------------------------------------------------

  Widget? _presence() {
    final a = widget.agent;
    final p = a?.presence;
    String state;
    String? since;
    String line;
    Color color;
    if (p != null && p.active) {
      final waiting = const {'waiting', 'blocked'}.contains(p.state) ||
          (a?.needsYou ?? 0) > 0;
      color = waiting ? AppColors.run : AppColors.accent;
      state = p.state[0].toUpperCase() + p.state.substring(1);
      since = p.since == null ? null : _elapsed(p.since!);
      line = p.detail;
      if (line.isEmpty) return null;
    } else {
      final m = a?.lastMessage?.text.trim() ?? '';
      // Restart notices say nothing about the agent; show its idle state.
      final noise = m.isEmpty || m.startsWith('Snippet restarted while');
      color = AppColors.fg4;
      state = 'Quiet';
      final at = a?.lastMessage?.at;
      since = noise || at == null ? null : _elapsed(at);
      line = noise ? 'Nothing on its desk.' : m;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: _cardDecoration(),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _Dot(color),
            const SizedBox(width: 6),
            Text(state, style: sans(12, color: color)),
            if (since != null) ...[
              const SizedBox(width: 6),
              Text('· $since', style: sans(12, color: color, tabular: true)),
            ],
          ]),
          const SizedBox(height: 5),
          Text(line,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: sans(13,
                  color:
                      p != null && p.active ? AppColors.fg1 : AppColors.fg3)),
        ]),
      ),
    );
  }

  // ---- quick links ----------------------------------------------------

  Widget _strip() {
    final cells = <(String, String, VoidCallback)>[
      if (widget.onInbox != null) ('inbox', 'Inbox', widget.onInbox!),
      if (widget.onBoard != null) ('kanban', 'Board', widget.onBoard!),
      if (widget.onMemory != null) ('book', 'Memory', widget.onMemory!),
      if (widget.onTasks != null) ('task', 'Tasks', widget.onTasks!),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();
    final row = <Widget>[];
    for (final c in cells) {
      if (row.isNotEmpty) {
        row.add(Container(width: 1, color: Grouped.hairline));
      }
      row.add(Expanded(
        child: InkWell(
          onTap: c.$3,
          hoverColor: Colors.transparent,
          child: SizedBox(
            height: 54,
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(c.$1, size: 15, color: AppColors.fg3),
                  const SizedBox(height: 4),
                  Text(c.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11.5, color: AppColors.fg3)),
                ]),
          ),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        decoration: _cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: IntrinsicHeight(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: row),
          ),
        ),
      ),
    );
  }

  // ---- sections -------------------------------------------------------

  Widget? _onNow() {
    final p = widget.agent?.presence;
    final rows = <Widget>[];
    final live = _tasks
        .where((t) => const {
              TaskStatus.inProgress,
              TaskStatus.inReview,
              TaskStatus.blocked,
            }.contains(t.status))
        .take(4);
    for (final t in live) {
      final step = (t.currentStep ?? '').trim();
      final stuck = t.status == TaskStatus.blocked;
      rows.add(_Row(
        icon: 'task',
        title: t.title,
        dot: stuck ? AppColors.run : AppColors.accent,
        sub: step.isEmpty ? t.status.label : '${t.status.label} · $step',
        chevron: true,
        onTap: () => openTaskDetail(context, widget.client, t.id),
      ));
    }
    if (p != null && p.active && widget.onDesk != null && !_mc) {
      rows.add(_Row(
        icon: 'terminal',
        title: 'Desk',
        dot: AppColors.accent,
        sub: [
          if (p.detail.isNotEmpty) p.detail,
          if (p.since != null) _elapsed(p.since!),
        ].join(' · '),
        chevron: true,
        onTap: widget.onDesk,
      ));
    }
    if (rows.isEmpty) return null;
    return _Section('On now', meta: '${rows.length}', children: rows);
  }

  Widget _next() {
    final w = _wake;
    final rows = <Widget>[
      if (w != null && w.enabled)
        _Row(
          icon: 'calendar-clock',
          title: w.title.isNotEmpty ? w.title : w.scheduleText,
          value: w.nextRunAt > 0 ? _nextAt(w.nextRunAt) : null,
        ),
      if (_warmLoaded)
        _Row(
          icon: 'zap',
          title: 'Keep warm',
          trailing: SettingsSwitch(
              value: _warm?.enabled ?? false, onChanged: _setWarm),
          onTap: () => _setWarm(!(_warm?.enabled ?? false)),
        ),
    ];
    return _Section('Next', children: rows);
  }

  Widget? _cameBack() {
    final done = _tasks.where((t) => t.status == TaskStatus.done).toList()
      ..sort((a, b) => (b.completedAt ?? b.updatedAt)
          .compareTo(a.completedAt ?? a.updatedAt));
    if (done.isEmpty) return null;
    return _Section('Completed', meta: '${done.length}', children: [
      for (final t in done.take(3))
        _Row(
          icon: 'check',
          title: t.title,
          sub: () {
            final at = DateTime.tryParse(t.completedAt ?? t.updatedAt);
            return at == null ? 'Task' : 'Task · ${_dayOf(at.toLocal())}';
          }(),
          onTap: () => openTaskDetail(context, widget.client, t.id),
        ),
    ]);
  }

  // ---- Lead ------------------------------------------------------------

  AgentSettingRow? get _wakesSetting {
    for (final s in widget.settings) {
      if (s.label == 'Automated wakes') return s;
    }
    return null;
  }

  Widget _mcNow() {
    final p = widget.agent?.presence;
    final w = _wake;
    final active = p != null && p.active;
    final lastRun = w?.lastRunAt;
    final head = active
        ? p.state[0].toUpperCase() + p.state.substring(1)
        : lastRun != null && lastRun > 0
            ? 'Quiet · woke ${mcAge(DateTime.fromMillisecondsSinceEpoch(lastRun * 1000))} ago'
            : 'Quiet';
    final now = DateTime.now();
    final flight =
        _tasks.where((t) => t.status == TaskStatus.inProgress).length;
    final doneToday = _tasks.where((t) {
      final at = DateTime.tryParse(t.completedAt ?? '')?.toLocal();
      return t.status == TaskStatus.done &&
          at != null &&
          at.year == now.year &&
          at.month == now.month &&
          at.day == now.day;
    }).length;
    final action = active && p.detail.isNotEmpty ? p.detail : 'No action';
    final next = w != null && w.enabled && w.nextRunAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(w.nextRunAt * 1000)
        : null;
    final wakes = _wakesSetting;
    final on = w?.enabled ?? false;
    return _Section('Now', children: [
      _Row(
        icon: 'check',
        title: head,
        sub: '$action · $flight in flight · $doneToday done today',
        dot: active ? AppColors.accent : null,
      ),
      _Row(
        icon: 'calendar-clock',
        title: 'Next wake',
        value: next == null
            ? 'Off'
            : '${_nextAt(w!.nextRunAt)} · ${mcUntil(next)}',
        valueMono: true,
      ),
      _Row(
        icon: 'activity',
        title: 'Automated wakes',
        trailing: SettingsSwitch(
            value: on, onChanged: (_) => wakes?.onTap()),
        onTap: wakes?.onTap,
      ),
      if (_warmLoaded)
        _Row(
          icon: 'zap',
          title: 'Keep warm',
          trailing: SettingsSwitch(
              value: _warm?.enabled ?? false, onChanged: _setWarm),
          onTap: () => _setWarm(!(_warm?.enabled ?? false)),
        ),
    ]);
  }

  Widget _mcGoTo() {
    final open = _tasks.where((t) => !t.status.isTerminal).length;
    final rows = <(String, String, String?, VoidCallback?)>[
      ('inbox', 'Inbox', null, widget.onInbox),
      ('kanban', 'Board', null, widget.onBoard),
      ('book', 'Memory', null, widget.onMemory),
      ('task', 'Tasks', _tasks.isEmpty ? null : '$open open', widget.onTasks),
    ];
    return _Section('Go to', children: [
      for (final r in rows)
        if (r.$4 != null)
          _Row(
              icon: r.$1,
              title: r.$2,
              value: r.$3,
              valueMono: true,
              chevron: true,
              onTap: r.$4),
    ]);
  }

  String? _resumeOverride;

  String? get _resumeMode {
    if (_resumeOverride != null) return _resumeOverride;
    final id = widget.sessionId;
    if (id == null) return null;
    for (final s in _sessions) {
      if (s.id == id) return s.resumeMode;
    }
    return null;
  }

  Future<void> _pickResume(BuildContext anchor) async {
    final id = widget.sessionId;
    if (id == null) return;
    final pick = await showAppMenu<String>(anchor,
        anchor: anchor,
        minWidth: 180,
        items: [
          appMenuItem(value: 'ask', icon: 'help-circle', label: 'Ask'),
          appMenuItem(value: 'lean', icon: 'zap', label: 'Lean'),
          appMenuItem(value: 'full', icon: 'book', label: 'Full'),
        ]);
    if (pick == null || !mounted) return;
    final before = _resumeOverride;
    setState(() => _resumeOverride = pick);
    try {
      await widget.client.setResumeMode(id, pick);
    } catch (e) {
      if (!mounted) return;
      setState(() => _resumeOverride = before);
      toast(context, "Couldn't change cold resume: $e", danger: true);
    }
  }

  Widget? _mcSession() {
    if (widget.onModel == null && widget.sessionId == null) return null;
    final profile = (widget.agent?.profile ?? '').trim();
    final mode = _resumeMode;
    return _Section('Session', children: [
      if (widget.onModel != null)
        _Row(
            icon: 'cpu',
            title: 'Model',
            value: profile.isEmpty ? 'Default' : profile,
            chevron: true,
            onTap: widget.onModel),
      if (widget.sessionId != null)
        Builder(
          builder: (bc) => _Row(
              icon: 'repeat',
              title: 'Cold resume',
              value: switch (mode) {
                'lean' => 'Lean',
                'full' => 'Full',
                null => null,
                _ => 'Ask',
              },
              chevron: true,
              onTap: () => _pickResume(bc)),
        ),
    ]);
  }

  Widget _buildMc() {
    final needs = mcNeeds(widget.client, _tasks, _sessions);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _identity(),
            if (_presence() case final p?) p,
          ]),
        ),
        McNeedsYou(needs: needs, carded: true),
        _mcNow(),
        _mcGoTo(),
        if (_mcSession() case final s?) s,
        _Section('Settings', initiallyOpen: false, children: [
          for (final s in widget.settings)
            _Row(
                icon: s.icon,
                title: s.label,
                sub: s.sub,
                chevron: true,
                onTap: s.onTap),
        ]),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mc) return _buildMc();
    final presence = _presence();
    final sections = [_onNow(), _next(), _cameBack()].whereType<Widget>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _identity(),
            if (widget.header != null) ...[
              const SizedBox(height: 12),
              widget.header!,
            ],
            if (presence != null) presence,
            _strip(),
          ]),
        ),
        for (final s in sections) s,
        _Section('Settings', initiallyOpen: false, children: [
          for (final s in widget.settings)
            _Row(
                icon: s.icon,
                title: s.label,
                sub: s.sub,
                chevron: true,
                onTap: s.onTap),
        ]),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// The settings card: faint fill, 1px border, 10px corners.
BoxDecoration _cardDecoration() => BoxDecoration(
      color: Grouped.card,
      border: Border.all(color: Grouped.cardBorder),
      borderRadius: BorderRadius.circular(Grouped.radiusEnd),
    );

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// An accordion section, same chrome as the session panel's `_RailGroup`.
class _Section extends StatefulWidget {
  const _Section(this.label,
      {required this.children, this.meta, this.initiallyOpen = true});
  final String label;
  final String? meta;
  final bool initiallyOpen;
  final List<Widget> children;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool get _isOpen => _open[widget.label] ?? widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    if (!_open.containsKey(widget.label)) {
      SharedPreferences.getInstance().then((p) {
        final v = p.getBool('$_openPref${widget.label}');
        if (v == null || !mounted) return;
        setState(() => _open[widget.label] = v);
      });
    }
  }

  Future<void> _toggle() async {
    final v = !_isOpen;
    setState(() => _open[widget.label] = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('$_openPref${widget.label}', v);
  }

  @override
  Widget build(BuildContext context) {
    final open = _isOpen;
    final head = InkWell(
      onTap: _toggle,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: SizedBox(
        height: 24,
        child: Row(children: [
          const SizedBox(width: 2),
          Text(widget.label,
              style: sans(12.5, weight: FontWeight.w500, color: AppColors.fg2)),
          if (widget.meta != null) ...[
            const SizedBox(width: 6),
            Text(widget.meta!,
                style: sans(12.5, color: AppColors.fg4, tabular: true)),
          ],
          const Spacer(),
          AnimatedRotation(
            turns: open ? 0.25 : 0,
            duration: Motion.fast,
            child: AppIcon('chevron-right', size: 12, color: AppColors.fg3),
          ),
          const SizedBox(width: 2),
        ]),
      ),
    );
    final rows = <Widget>[];
    for (final c in widget.children) {
      if (rows.isNotEmpty) {
        rows.add(Container(height: 1, color: Grouped.hairline));
      }
      rows.add(c);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: open && rows.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      decoration: _cardDecoration(),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: rows),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.sub,
    this.value,
    this.valueMono = false,
    this.dot,
    this.trailing,
    this.chevron = false,
    this.onTap,
  });
  final String icon;
  final String title;
  final String? sub;
  final String? value;
  final bool valueMono;
  final Color? dot;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasSub = sub != null && sub!.isNotEmpty;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: hasSub ? 52 : 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.fg1.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(R.of(7)),
                ),
                child: AppIcon(icon, size: 15, color: AppColors.fg2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                      if (hasSub)
                        Row(children: [
                          if (dot != null) ...[
                            _Dot(dot!),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(sub!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(12, color: AppColors.fg3)),
                          ),
                        ]),
                    ]),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                Text(value!,
                    style: valueMono
                        ? mono(11.5, color: AppColors.fg3)
                        : sans(12, color: AppColors.fg3, tabular: true)),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
              if (chevron) ...[
                const SizedBox(width: 6),
                AppIcon('chevron-right', size: 13, color: AppColors.fg3),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
