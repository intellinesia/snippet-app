import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../models.dart';
import '../mochi.dart';
import '../platform.dart';
import '../presence.dart';
import '../screens/agent_panel.dart';
import '../wake_models.dart';
import '../screens/agent_profile_panel.dart';
import '../screens/agent_records.dart';
import '../screens/memory_screen.dart';
import '../screens/mobile_chrome.dart';
import '../screens/tasks/tasks_panel.dart';
import '../shell_panel.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_style.dart';

enum AgentDetailsTab { info, tasks, inbox, board }

Future<void> showAgentDetailsSheet(
  BuildContext context, {
  required DaemonClient client,
  String? agentId,
  String? agentName,
  GroupSummary? group,
  AgentDetailsTab initialTab = AgentDetailsTab.info,
  VoidCallback? onCall,
  VoidCallback? onDeleted,
  ValueChanged<GroupSummary>? onGroupChanged,
  VoidCallback? onGroupDeleted,
}) {
  assert(group != null || (agentId != null && agentId.isNotEmpty));
  final media = MediaQuery.of(context);
  Widget buildBody(VoidCallback close) => AgentDetails(
        client: client,
        agentId: agentId,
        agentName: agentName,
        group: group,
        initialTab: initialTab,
        onCall: onCall,
        onClose: close,
        onDeleted: onDeleted,
        onGroupChanged: onGroupChanged,
        onGroupDeleted: onGroupDeleted,
      );

  if (kMobile) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => AppSheetSurface(
        color: AppColors.windowBg,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: media.size.height * 0.92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Expanded(
                  child: buildBody(() => Navigator.of(sheetCtx).pop()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: AppColors.windowBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        child: buildBody(() => Navigator.of(dialogCtx).pop()),
      ),
    ),
  );
}

class AgentDetails extends StatefulWidget {
  const AgentDetails({
    super.key,
    required this.client,
    this.agentId,
    this.agentName,
    this.group,
    this.initialTab = AgentDetailsTab.info,
    this.onCall,
    this.onClose,
    this.onDeleted,
    this.onGroupChanged,
    this.onGroupDeleted,
  }) : assert(group != null || (agentId != null && agentId != ''));

  final DaemonClient client;
  final String? agentId;
  final String? agentName;
  final GroupSummary? group;
  final AgentDetailsTab initialTab;
  final VoidCallback? onCall;
  final VoidCallback? onClose;
  final VoidCallback? onDeleted;
  final ValueChanged<GroupSummary>? onGroupChanged;
  final VoidCallback? onGroupDeleted;

  @override
  State<AgentDetails> createState() => _AgentDetailsState();
}

class _AgentDetailsState extends State<AgentDetails> {
  late AgentDetailsTab _tab = widget.initialTab;
  late GroupSummary? _group = widget.group;

  bool _loading = true;
  bool _busy = false;
  String? _releasingSession;
  AgentNow? _now;
  CoordinationAgent? _agent;
  List<CoordinationAgent> _allAgents = const [];
  bool _pushEnabled = false;
  bool _keepWarmEnabled = false;
  int? _memoryFiles;
  bool _groupNotify = true;

  bool get _isGroup => _group != null;
  String get _agentId => widget.agentId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AgentDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agentId != widget.agentId ||
        oldWidget.group?.id != widget.group?.id) {
      _group = widget.group;
      _tab = widget.initialTab;
      _load();
    } else if (widget.group != null && widget.group != oldWidget.group) {
      _group = widget.group;
    }
  }

  Future<void> _load() async {
    if (_isGroup) {
      await _loadGroup();
    } else {
      await _loadAgent();
    }
  }

  Future<void> _loadGroup() async {
    if (mounted) setState(() => _loading = _allAgents.isEmpty);
    try {
      final prefsFuture = SharedPreferences.getInstance();
      final agentsFuture =
          widget.client.coordinationAgents().catchError((_) => <CoordinationAgent>[]);
      final prefs = await prefsFuture;
      final agents = await agentsFuture;
      if (!mounted) return;
      setState(() {
        _allAgents = agents;
        _groupNotify = prefs.getBool('group_notify:${_group!.id}') ?? true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAgent() async {
    if (mounted) setState(() => _loading = _now == null && _agent == null);
    final id = _agentId;
    final results = await Future.wait<Object?>([
      widget.client.agentNow(id).then<Object?>((v) => v).catchError((_) => null),
      widget.client
          .coordinationAgents()
          .then<Object?>((v) => v)
          .catchError((_) => <CoordinationAgent>[]),
      widget.client.agentReach(id).then<Object?>((v) => v).catchError((_) => null),
      widget.client.keepWarmFor(id).then<Object?>((v) => v).catchError((_) => null),
      widget.client
          .memoryScopes()
          .then<Object?>((v) => v)
          .catchError((_) => <MemoryScope>[]),
    ]);
    if (!mounted) return;
    final now = results[0] as AgentNow?;
    final agents = results[1] as List<CoordinationAgent>;
    final reach = results[2] as AgentReach?;
    final warm = results[3] as KeepWarmEntry?;
    final scopes = results[4] as List<MemoryScope>;

    CoordinationAgent? match;
    for (final a in agents) {
      if (a.id == id) {
        match = a;
        break;
      }
    }
    int? memoryFiles;
    for (final s in scopes) {
      if (s.key == 'agent:$id') {
        memoryFiles = s.files;
        break;
      }
    }
    setState(() {
      _now = now;
      _agent = match ?? _agent;
      _allAgents = agents;
      if (reach != null) _pushEnabled = reach.channel('push').enabled;
      if (warm != null) _keepWarmEnabled = warm.enabled;
      _memoryFiles = memoryFiles;
      _loading = false;
    });
  }

  String get _displayName {
    final fromAgent = _agent?.displayName.trim() ?? '';
    if (fromAgent.isNotEmpty) return fromAgent;
    final explicit = (widget.agentName ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    return _agentId;
  }

  String get _roleLine {
    final a = _agent;
    if (a == null) return '@$_agentId';
    if (a.capabilities.isNotEmpty) {
      return a.capabilities.take(3).join(' · ');
    }
    if (a.kind.trim().isNotEmpty && a.kind != 'agent') return a.kind;
    return a.handle.trim().isNotEmpty ? '@${a.handle.trim()}' : '@${a.id}';
  }

  String get _groupTitle {
    final g = _group!;
    final t = g.title.trim();
    if (t.isNotEmpty) return t;
    final ids = g.agentIds;
    if (ids.isEmpty) return 'Group';
    return ids.map(_memberDisplayName).join(', ');
  }

  String _memberDisplayName(String id) {
    for (final a in _allAgents) {
      if (a.id == id) {
        final n = a.displayName.trim();
        if (n.isNotEmpty) return n;
      }
    }
    return id;
  }

  String _relativeAge(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final d = DateTime.now().difference(dt.toLocal());
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  String _presenceLabel(Presence? p) {
    if (_now?.presence != null && _now!.presence!.state.trim().isNotEmpty) {
      final detail = _now!.presence!.detail.trim();
      final state = _now!.presence!.state.trim();
      return detail.isNotEmpty ? '$state · $detail' : state;
    }
    if (_agent?.status == 'paused') return 'paused';
    if (p == null || p.state.trim().isEmpty) return 'idle';
    final detail = p.detail.trim();
    return detail.isNotEmpty ? '${p.state} · $detail' : p.state;
  }

  String _memberPresenceLabel(String id) {
    final p = widget.client.presence.presenceForAgentId(id);
    if (p != null && p.state.trim().isNotEmpty) {
      final detail = p.detail.trim();
      return detail.isNotEmpty ? '${p.state} · $detail' : p.state;
    }
    for (final a in _allAgents) {
      if (a.id == id && a.status == 'paused') return 'paused';
    }
    return 'waiting';
  }

  Future<void> _releaseSeat(AgentNowSession seat) async {
    if (_releasingSession != null) return;
    setState(() => _releasingSession = seat.session);
    try {
      await widget.client.releaseAgentSeat(_agentId, seat.session);
      if (!mounted) return;
      toast(context, 'Session released');
      await _loadAgent();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _releasingSession = null);
    }
  }

  Future<void> _togglePush(bool v) async {
    final prev = _pushEnabled;
    setState(() => _pushEnabled = v);
    try {
      final r = await widget.client
          .setAgentReach(_agentId, channels: {'push': {'enabled': v}});
      if (mounted) {
        setState(() => _pushEnabled = r.channel('push').enabled);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pushEnabled = prev);
        toast(context, '$e', danger: true);
      }
    }
  }

  Future<void> _toggleKeepWarm(bool v) async {
    final prev = _keepWarmEnabled;
    setState(() => _keepWarmEnabled = v);
    try {
      final entry = await widget.client.setKeepWarm(_agentId, enabled: v);
      if (mounted) setState(() => _keepWarmEnabled = entry.enabled);
    } catch (e) {
      if (mounted) {
        setState(() => _keepWarmEnabled = prev);
        toast(context, '$e', danger: true);
      }
    }
  }

  Future<void> _togglePause(bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.client.setAgentStatus(_agentId, v ? 'paused' : 'active');
      if (!mounted) return;
      await _loadAgent();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openProfile() async {
    final a = _agent ??
        CoordinationAgent.fromJson({
          'id': _agentId,
          'display_name': _displayName,
          'handle': _agentId,
        });
    await showAgentProfileSettings(
      context,
      client: widget.client,
      agent: a,
      name: _displayName,
      onChanged: _loadAgent,
    );
  }

  Future<void> _openMemory() async {
    final panel = ShellPanelScope.maybeOf(context);
    if (panel != null) {
      panel.open(agentPanelRequest(
        'memory',
        client: widget.client,
        agentId: _agentId,
        agentName: _displayName,
      ));
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (page) => Material(
        color: AppColors.bg,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileBackBar(
                title: 'Memory',
                onBack: () => Navigator.of(page).pop(),
              ),
              Expanded(
                child: MemoryScreen(
                  client: widget.client,
                  embedded: true,
                  onBack: () => Navigator.of(page).pop(),
                  hideBack: true,
                  initialKey: 'agent:$_agentId',
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Future<void> _resetDeskSession() async {
    if (_busy) return;
    final ok = await confirmAction(
      context,
      title: 'Reset desk session?',
      body: 'Clears the desk conversation for $_displayName. '
          'The next message starts a fresh session.',
      confirmLabel: 'Reset desk session',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.deleteSession('inbox-$_agentId');
      if (mounted) toast(context, 'Desk session reset');
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleGroupNotify(bool v) async {
    setState(() => _groupNotify = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('group_notify:${_group!.id}', v);
    } catch (_) {}
  }

  Future<void> _updateGroup(Future<GroupSummary> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await call();
      if (!mounted) return;
      setState(() => _group = updated);
      widget.onGroupChanged?.call(updated);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAddMember() async {
    final g = _group!;
    final addable = [
      for (final a in _allAgents)
        if (!a.isMissionControl &&
            a.status != 'archived' &&
            !g.agentIds.contains(a.id))
          a,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));

    await showAppSheet<void>(
      context,
      title: 'Add member',
      maxWidth: 360,
      child: addable.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Every available agent is already in this group.',
                style: TS.body(ChatColors.meta),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in addable)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _updateGroup(() => widget.client
                          .updateGroup(g.id, addMembers: [a.id]));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      child: Row(
                        children: [
                          AgentMochi(a.id, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              a.displayName.trim().isEmpty
                                  ? a.id
                                  : a.displayName.trim(),
                              style: TS.body(AppColors.fg1),
                            ),
                          ),
                          AppIcon('plus', size: 16, color: AppColors.fg3),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _openMemberActions(GroupMember member) async {
    if (!member.isAgent) return;
    final g = _group!;
    final name = _memberDisplayName(member.id);
    await showAppSheet<void>(
      context,
      title: name,
      maxWidth: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (member.id != g.lead)
            _SheetActionRow(
              label: 'Make lead',
              onTap: () {
                Navigator.of(context).pop();
                _updateGroup(() => widget.client.updateGroup(g.id, lead: member.id));
              },
            ),
          _SheetActionRow(
            key: ValueKey('remove-${member.id}'),
            label: 'Remove from group',
            danger: true,
            onTap: () {
              Navigator.of(context).pop();
              _updateGroup(() =>
                  widget.client.updateGroup(g.id, removeMembers: [member.id]));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup() async {
    if (_busy) return;
    final g = _group!;
    final ok = await confirmAction(
      context,
      title: 'Delete $_groupTitle?',
      body: 'This removes the group chat and its messages for everyone in it. '
          'The agents stay. This can\'t be undone.',
      confirmLabel: 'Delete group',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.deleteGroup(g.id);
      if (!mounted) return;
      toast(context, 'Deleted $_groupTitle');
      widget.onClose?.call();
      widget.onGroupDeleted?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.windowBg,
      child: _isGroup ? _buildGroupBody() : _buildAgentBody(),
    );
  }

  Widget _buildAgentBody() {
    final name = _displayName;
    final mochiSize = kMobile ? 88.0 : 72.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            children: [
              AgentMochi(_agentId, size: mochiSize),
              const SizedBox(height: 10),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(20, weight: W.title, color: AppColors.fg1),
              ),
              const SizedBox(height: 2),
              Text(
                _roleLine,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.meta(ChatColors.meta),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundActionButton(
                    icon: 'terminal',
                    label: 'Desk',
                    onTap: () =>
                        openAgentDesk(context, widget.client, _agentId, name),
                  ),
                  _RoundActionButton(
                    icon: 'task',
                    label: 'Tasks',
                    onTap: () => setState(() => _tab = AgentDetailsTab.tasks),
                  ),
                  if (widget.onCall != null)
                    _RoundActionButton(
                      icon: 'mic',
                      label: 'Call',
                      onTap: widget.onCall!,
                    ),
                  _RoundActionButton(
                    icon: 'more-horizontal',
                    label: 'More',
                    onTap: () => openAgentActions(
                      context,
                      client: widget.client,
                      agentId: _agentId,
                      agentName: name,
                      views: false,
                      onDeleted: () {
                        widget.onClose?.call();
                        widget.onDeleted?.call();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SegmentedTabs(
                current: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            AgentDetailsTab.info => _buildAgentInfo(),
            AgentDetailsTab.tasks =>
              TasksPanel(client: widget.client, phoneHeader: false),
            AgentDetailsTab.inbox => AgentInboxView(
                client: widget.client,
                agentId: _agentId,
                agentName: name,
                filterChips: true,
              ),
            AgentDetailsTab.board => AgentBoardView(
                client: widget.client,
                agentId: _agentId,
                agentName: name,
                filterChips: true,
              ),
          },
        ),
      ],
    );
  }

  Widget _buildAgentInfo() {
    if (_loading && _now == null && _agent == null) {
      return const Center(child: AppLoading());
    }
    final sessions = _now?.sessions ?? const <AgentNowSession>[];
    final profileText =
        (_agent?.profile ?? '').trim().isNotEmpty ? _agent!.profile! : 'Default';
    final memoryText = _memoryFiles == null
        ? 'Browse'
        : '$_memoryFiles ${_memoryFiles == 1 ? 'topic' : 'topics'}';

    return ListenableBuilder(
      listenable: widget.client.presence,
      builder: (_, __) {
        final livePresence = widget.client.presence.presenceForAgentId(_agentId);
        final presenceText = _presenceLabel(livePresence);
        final sinceRaw = _now?.presence?.since ?? '';
        final sinceText = sinceRaw.isNotEmpty ? _relativeAge(sinceRaw) : '';

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _GroupedCard(
              children: [
                _InfoRow(
                  label: 'Now',
                  subtitle: presenceText,
                  trailingText: sinceText,
                ),
                for (final seat in sessions)
                  _SessionSeatRow(
                    seat: seat,
                    age: _relativeAge(
                      seat.lastProgressAt.isNotEmpty
                          ? seat.lastProgressAt
                          : seat.since,
                    ),
                    busy: _releasingSession == seat.session,
                    onRelease: seat.stale ? () => _releaseSeat(seat) : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _GroupedCard(
              children: [
                _SwitchRow(
                  label: 'Notify me',
                  value: _pushEnabled,
                  onChanged: _togglePush,
                ),
                _SwitchRow(
                  label: 'Keep warm',
                  value: _keepWarmEnabled,
                  onChanged: _toggleKeepWarm,
                ),
                _SwitchRow(
                  label: 'Pause agent',
                  value: _agent?.status == 'paused',
                  onChanged: _togglePause,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GroupedCard(
              children: [
                _NavRow(
                  label: 'Profile',
                  value: profileText,
                  onTap: _openProfile,
                ),
                _NavRow(
                  label: 'Memory',
                  value: memoryText,
                  onTap: _openMemory,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GroupedCard(
              children: [
                _DestructiveRow(
                  label: 'Reset desk session',
                  onTap: _busy ? null : _resetDeskSession,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupBody() {
    final g = _group!;
    final agentCount = g.agentIds.length;
    final subtitle =
        '$agentCount ${agentCount == 1 ? 'agent' : 'agents'} and you';
    final mochiSize = kMobile ? 72.0 : 56.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Center(
          child: _StackedMochis(agentIds: g.agentIds, size: mochiSize),
        ),
        const SizedBox(height: 10),
        Text(
          _groupTitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: sans(20, weight: W.title, color: AppColors.fg1),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TS.meta(ChatColors.meta),
        ),
        const SizedBox(height: 18),
        ListenableBuilder(
          listenable: widget.client.presence,
          builder: (_, __) => _GroupedCard(
            children: [
              for (final m in g.members)
                _GroupMemberRow(
                  member: m,
                  name: m.isHuman ? 'You' : _memberDisplayName(m.id),
                  isLead: m.id == g.lead,
                  presenceText: m.isHuman ? 'You' : _memberPresenceLabel(m.id),
                  onTap: m.isAgent ? () => _openMemberActions(m) : null,
                ),
              InkWell(
                onTap: _busy ? null : _openAddMember,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      AppIcon('plus', size: 16, color: AppColors.fg1),
                      const SizedBox(width: 10),
                      Text(
                        'Add member',
                        style: sans(14, weight: W.label, color: AppColors.fg1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GroupedCard(
          children: [
            _SwitchRow(
              label: 'Notify me',
              value: _groupNotify,
              onChanged: _toggleGroupNotify,
            ),
            const _InfoRow(
              label: 'Agents reply to each other',
              trailingText: 'Only when mentioned',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _GroupedCard(
          children: [
            _DestructiveRow(
              label: 'Delete group',
              onTap: _busy ? null : _deleteGroup,
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ChatColors.cardButton,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(icon, size: 18, color: AppColors.fg1),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: sans(11, weight: W.label, color: AppColors.fg2),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.current, required this.onChanged});

  final AgentDetailsTab current;
  final ValueChanged<AgentDetailsTab> onChanged;

  static const _tabs = [
    (AgentDetailsTab.info, 'Info'),
    (AgentDetailsTab.tasks, 'Tasks'),
    (AgentDetailsTab.inbox, 'Inbox'),
    (AgentDetailsTab.board, 'Board'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ChatColors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final (tab, label) in _tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tab),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: tab == current
                        ? ChatColors.cardButton
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: sans(
                      13,
                      weight: tab == current ? W.label : W.body,
                      color:
                          tab == current ? AppColors.fg1 : ChatColors.meta,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ChatColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.line,
                ),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    this.subtitle,
    this.trailingText = '',
  });

  final String label;
  final String? subtitle;
  final String trailingText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: sans(14, weight: W.body, color: AppColors.fg1)),
                if ((subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TS.meta(ChatColors.meta),
                  ),
                ],
              ],
            ),
          ),
          if (trailingText.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(trailingText, style: TS.meta(ChatColors.meta)),
          ],
        ],
      ),
    );
  }
}

class _SessionSeatRow extends StatelessWidget {
  const _SessionSeatRow({
    required this.seat,
    required this.age,
    required this.busy,
    this.onRelease,
  });

  final AgentNowSession seat;
  final String age;
  final bool busy;
  final VoidCallback? onRelease;

  @override
  Widget build(BuildContext context) {
    final title = seat.taskTitle.trim().isNotEmpty ? seat.taskTitle : seat.session;
    final parts = <String>[
      if (seat.taskStatus.trim().isNotEmpty) seat.taskStatus.trim(),
      if (age.isNotEmpty) age,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, weight: W.body, color: AppColors.fg1),
                ),
                if (parts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.meta(ChatColors.meta),
                  ),
                ],
              ],
            ),
          ),
          if (onRelease != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: busy ? null : onRelease,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                busy ? 'Releasing...' : 'Release',
                style: sans(13, weight: W.label, color: AppColors.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: sans(14, weight: W.body, color: AppColors.fg1),
            ),
          ),
          AppSwitch(on: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: sans(14, weight: W.body, color: AppColors.fg1),
              ),
            ),
            Text(value, style: TS.meta(ChatColors.meta)),
            const SizedBox(width: 6),
            AppIcon('chevron-right', size: 14, color: ChatColors.meta),
          ],
        ),
      ),
    );
  }
}

class _DestructiveRow extends StatelessWidget {
  const _DestructiveRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          label,
          style: sans(14, weight: W.label, color: AppColors.danger),
        ),
      ),
    );
  }
}

class _GroupMemberRow extends StatelessWidget {
  const _GroupMemberRow({
    required this.member,
    required this.name,
    required this.isLead,
    required this.presenceText,
    this.onTap,
  });

  final GroupMember member;
  final String name;
  final bool isLead;
  final String presenceText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = isLead ? '$name · Lead' : name;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (member.isAgent)
              AgentMochi(member.id, size: 28)
            else
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: ChatColors.cardButton,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AppIcon('user', size: 14, color: AppColors.fg2),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(14, weight: W.body, color: AppColors.fg1),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              presenceText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TS.meta(ChatColors.meta),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              AppIcon('chevron-right', size: 14, color: ChatColors.meta),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  const _SheetActionRow({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
          label,
          style: sans(
            14,
            weight: W.label,
            color: danger ? AppColors.danger : AppColors.fg1,
          ),
        ),
      ),
    );
  }
}

class _StackedMochis extends StatelessWidget {
  const _StackedMochis({required this.agentIds, required this.size});

  final List<String> agentIds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ids = agentIds.take(2).toList();
    if (ids.isEmpty) return AgentMochi('', size: size);
    if (ids.length == 1) return AgentMochi(ids.first, size: size);
    final single = size * 0.78;
    return SizedBox(
      width: single * 1.55,
      height: single,
      child: Stack(
        children: [
          Positioned(left: 0, child: AgentMochi(ids[0], size: single)),
          Positioned(
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.windowBg,
                shape: BoxShape.circle,
              ),
              child: AgentMochi(ids[1], size: single - 4),
            ),
          ),
        ],
      ),
    );
  }
}
