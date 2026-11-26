import 'package:flutter/material.dart';

import '../ambient_loop.dart';
import '../api.dart';
import '../clock.dart';
import '../crew_status.dart';
import '../markdown_preview.dart';
import '../models.dart';
import '../pins.dart';
import '../platform.dart';
import '../presence.dart';
import '../composer/composer_pill.dart' show C7;
import '../theme.dart';
import '../widgets.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton;
import 'package:flutter/services.dart';
import '../mochi.dart';
import '../settings_form.dart' show Grouped;
import 'agent_wake_panel.dart';
import 'agent_appearance.dart';
import 'agent_profile_panel.dart';

/// Which section of the phone's Agents page an agent belongs to.
enum AgentGroup { needsYou, working, recent }

/// Group an agent for the phone list: waiting on the user, busy, or recent.
AgentGroup agentGroupFor(CoordinationAgent agent, {Presence? presence}) {
  final p = presence;
  final waitingYou = p != null &&
      p.state == 'waiting' &&
      (p.detail.isEmpty || p.detail == 'user');
  final blocked = agent.tasksIn({'blocked', 'failed'});
  if (agent.available && (waitingYou || blocked > 0)) {
    return AgentGroup.needsYou;
  }
  final open = agent.tasksIn({'in_progress', 'todo'});
  if (agent.available && (open > 0 || (p?.active ?? false))) {
    return AgentGroup.working;
  }
  return AgentGroup.recent;
}

final _uuidToken = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b');

/// Strip raw ids out of an agent's last-message text so the status line never
/// shows `group:<uuid>`, task uuids or other ids. A `group:` reference becomes
/// the group's title when known, otherwise it is dropped.
String cleanAgentStatusText(String text,
    {Map<String, String> groupTitles = const {}}) {
  var t = flattenMarkdown(text);
  t = t.replaceAllMapped(
      RegExp(r'\bgroup:([0-9A-Za-z][0-9A-Za-z-]*)', caseSensitive: false), (m) {
    final title = groupTitles[m[1] ?? '']?.trim() ?? '';
    return title.isEmpty ? '' : title;
  });
  t = t.replaceAll(RegExp(r'\btask\s+' + _uuidToken.pattern), '');
  t = t.replaceAll(_uuidToken, '');
  t = t
      .replaceAll(RegExp(r'\(\s*[,·]?\s*\)'), '')
      .replaceAll(RegExp(r'\(\s*,\s*'), '(')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'\s*·\s*'), ' · ')
      .replaceAll(RegExp(r'^[\s·\-–—:,→]+'), '')
      .replaceAll(RegExp(r'[\s·\-–—:,→]+$'), '')
      .trim();
  return t;
}

/// The readable second line under an agent's name on the phone list.
String agentStatusLine(CoordinationAgent agent,
    {Presence? presence, Map<String, String> groupTitles = const {}}) {
  final last = agent.lastMessage;
  // Restart notices are the harness talking, not the agent.
  final noise =
      last != null && last.text.trim().startsWith('Snippet restarted');
  var context = last == null || noise
      ? ''
      : cleanAgentStatusText(last.text, groupTitles: groupTitles);
  if (last?.fromUser ?? false) {
    if (context.isNotEmpty) context = 'You: $context';
  } else if (context.endsWith('?')) {
    context = 'Asked: $context';
  }
  return switch (agentGroupFor(agent, presence: presence)) {
    AgentGroup.needsYou =>
      context.isEmpty ? 'Waiting on you' : 'Waiting on you · $context',
    AgentGroup.working => context.isEmpty ? 'Working' : context,
    AgentGroup.recent =>
      context.isEmpty ? (last == null ? 'No messages yet' : 'Quiet') : context,
  };
}

/// v5 row time: 'now', clock today, weekday this week, 'd MMM' older.
String agentRowTime(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  at = at.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  if (n.difference(at) < const Duration(minutes: 1)) return 'now';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  if (at.year == n.year && at.month == n.month && at.day == n.day) {
    return clock12(at);
  }
  if (n.difference(at).inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[at.weekday - 1];
  }
  return '${at.day} ${months[at.month - 1]}';
}

/// Desktop row time: how long ago, as 'now', '5m', '2h', '3d', '2w', '4mo', '1y'.
String agentRowAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 30) return '${d.inDays ~/ 7}w';
  if (d.inDays < 365) return '${d.inDays ~/ 30}mo';
  return '${d.inDays ~/ 365}y';
}

/// The clock to sit beside [agentRowTime] when that shows only a day or date.
String agentRowClock(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  at = at.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final today = at.year == n.year && at.month == n.month && at.day == n.day;
  return today ? '' : clock12(at);
}

/// One agent on the phone's Agents page, in the Lead card's shape:
/// who it is, whether it is working, and its task counts.
class AgentCard extends StatefulWidget {
  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onChanged;

  /// Group id → title, so `group:<id>` refs in the status line can be named.
  final Map<String, String>? groupTitles;
  final bool pinned;
  final VoidCallback? onTogglePin;

  /// Phone: the agent's sessions, for the ask or the work in its line.
  final CrewEntry? crew;

  /// Phone: the section it sits in, when the list already decided it.
  final AgentGroup? group;

  /// Desktop: draw the row on the selected surface.
  final bool selected;

  /// Desktop: the host label when a failed refresh leaves cached rows offline.
  final String? offlineHost;

  /// Desktop: whether live session sub-rows are expanded.
  final bool expanded;

  /// Desktop: whether live session sub-rows can be expanded.
  final bool expandable;

  /// Desktop: explicit user toggle for the session sub-rows.
  final VoidCallback? onToggleExpansion;

  const AgentCard({
    super.key,
    required this.client,
    required this.agent,
    required this.onOpen,
    this.onDelete,
    this.onChanged,
    this.groupTitles,
    this.pinned = false,
    this.onTogglePin,
    this.crew,
    this.group,
    this.selected = false,
    this.offlineHost,
    this.expanded = false,
    this.expandable = false,
    this.onToggleExpansion,
  });

  @override
  State<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<AgentCard> {
  Future<void> _pickProfile(String name, {Offset? point}) =>
      showAgentProfileSettings(
        context,
        client: widget.client,
        agent: widget.agent,
        name: name,
        point: point,
        onChanged: widget.onChanged,
      );

  String get _nicknameLabel =>
      widget.agent.nickname == null ? 'Set nickname' : 'Edit nickname';

  Future<void> _editNickname({Offset? point}) async {
    final agent = widget.agent;
    final full =
        agent.fullName.trim().isEmpty ? agent.id : agent.fullName.trim();
    final next = await promptText(context,
        title: 'Nickname for $full',
        initial: agent.nickname ?? '',
        hint: 'Leave empty to use the name',
        anchored: true,
        point: point);
    if (next == null || next == (agent.nickname ?? '') || !mounted) return;
    try {
      await widget.client
          .setAgentNickname(agent.id, next.isEmpty ? null : next);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _openWakes(String name, Offset? point) =>
      showAgentWakeSettings(context,
          client: widget.client,
          owner: widget.agent.id,
          name: name,
          point: point,
          onChanged: widget.onChanged);

  bool get _isPinned =>
      widget.pinned ||
      Pins.instance
          .isPinned(Pins.agent, widget.agent.id, host: widget.client.baseUrl);

  void _togglePin() {
    if (widget.onTogglePin != null) {
      widget.onTogglePin!();
    } else {
      Pins.instance
          .toggle(Pins.agent, widget.agent.id, host: widget.client.baseUrl);
    }
  }

  Future<void> _actions(Offset? point) async {
    final name = widget.agent.displayName.trim().isEmpty
        ? widget.agent.id
        : widget.agent.displayName.trim();
    final pinned = _isPinned;
    if (kMobile) {
      showAppSheet(context,
          title: name,
          subtitle: 'Agent',
          child: SheetActions([
            if (!widget.agent.isLead)
              SheetAction(
                pinned ? 'pin-off' : 'pin',
                pinned ? 'Unpin' : 'Pin',
                () {
                  Navigator.pop(context);
                  _togglePin();
                },
                detail: pinned
                    ? 'Remove from the top of the list'
                    : 'Keep at the top of the list',
              ),
            if (!widget.agent.isLead)
              SheetAction('edit', _nicknameLabel, () {
                Navigator.pop(context);
                _editNickname();
              }, detail: 'What it is called here'),
            SheetAction('sparkles', 'Appearance', () {
              Navigator.pop(context);
              showAgentAppearance(
                  context, widget.client, widget.agent.id, name);
            }, detail: 'Avatar and colour across the app'),
            if (!widget.agent.isLead)
              SheetAction('calendar-clock', 'Wakes and reporting', () {
                Navigator.pop(context);
                _openWakes(name, null);
              }, detail: 'When it wakes and where it reports'),
            if (!widget.agent.isLead)
              SheetAction('cpu', 'Change inference profile', () {
                Navigator.pop(context);
                _pickProfile(name);
              }, detail: 'The model it runs on'),
            if (widget.onDelete != null)
              SheetAction('trash', 'Delete agent', () {
                Navigator.pop(context);
                widget.onDelete?.call();
              },
                  danger: true,
                  detail: 'Remove the agent, its identity and notes'),
          ]));
      return;
    }
    // Desktop keeps the quick actions here; settings live in the side panel.
    final items = [
      if (!widget.agent.isLead)
        appMenuItem(
            value: 'pin',
            icon: pinned ? 'pin-off' : 'pin',
            label: pinned ? 'Unpin' : 'Pin'),
      if (!widget.agent.isLead)
        appMenuItem(value: 'nickname', icon: 'edit', label: _nicknameLabel),
      if (widget.onDelete != null)
        appMenuItem(
            value: 'delete',
            icon: 'trash',
            label: 'Delete agent',
            danger: true),
    ];
    if (items.isEmpty) return;
    final picked = await showAppMenu<String>(
      context,
      point: point,
      anchor: point == null ? context : null,
      items: items,
    );
    if (picked == 'pin') _togglePin();
    if (picked == 'delete') widget.onDelete?.call();
    if (picked == 'nickname' && mounted) _editNickname(point: point);
  }

  List<TaskItem> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AgentCard old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client || old.agent.id != widget.agent.id) _load();
  }

  Future<void> _load() async {
    if (widget.agent.taskCounts != null) return;
    final id = widget.agent.id;
    try {
      final tasks = await widget.client.tasks(agentId: id, limit: 100);
      if (mounted) setState(() => _tasks = tasks);
    } catch (_) {}
  }

  int _count(Set<TaskStatus> statuses, Set<String> keys) =>
      widget.agent.taskCounts != null
          ? widget.agent.tasksIn(keys)
          : _tasks.where((t) => statuses.contains(t.status)).length;

  /// The ask, else the session it works in, else the last message.
  String _phoneLine(
      CoordinationAgent agent, CrewEntry? crew, Presence? presence) {
    final titles = widget.groupTitles ?? const {};
    if (crew != null && crew.state != CrewState.standingBy) {
      final text = cleanAgentStatusText(crew.line, groupTitles: titles);
      if (crew.state == CrewState.working) return text;
      final kind = crew.attention?['type'];
      return kind == 'approval'
          ? 'Approval: $text'
          : kind == 'question'
              ? 'Asked: $text'
              : 'Waiting on you · $text';
    }
    final line =
        agentStatusLine(agent, presence: presence, groupTitles: titles);
    if (line == 'No messages yet' && crew?.lead != null) {
      return cleanAgentStatusText(crew!.line, groupTitles: titles);
    }
    return line;
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final working = _count({TaskStatus.inProgress}, {'in_progress'});
    final last = agent.lastMessage;
    if (kMobile) {
      final presence = widget.client.presence.presenceForAgentId(agent.id);
      final crew = widget.crew;
      final group = widget.group ?? agentGroupFor(agent, presence: presence);
      final status = _phoneLine(agent, crew, presence);
      final lead = crew?.lead;
      final time =
          crew != null && crew.state != CrewState.standingBy && lead != null
              ? agentRowTime(
                  DateTime.fromMillisecondsSinceEpoch(lead.lastActive * 1000))
              : agentRowTime(agent.lastMessage?.at);
      final needs = group == AgentGroup.needsYou;
      final busy = group == AgentGroup.working;
      final characterState = !agent.available
          ? AgentCharacterState.sleeping
          : needs
              ? AgentCharacterState.needs
              : busy
                  ? AgentCharacterState.working
                  : AgentCharacterState.sleeping;
      final sub = status;
      final subStyle = TeamRow.subtitleStyle();
      return TeamRow(
        tall: false,
        onTap: () {
          tapHaptic();
          widget.onOpen();
        },
        onLongPress: () {
          holdHaptic();
          _actions(null);
        },
        child: Opacity(
          opacity: agent.available ? 1 : 0.55,
          child: Row(children: [
            SizedBox.square(
              key: ValueKey('agent-avatar-${characterState.name}'),
              dimension: 40,
              child: AgentMochi(agent.id,
                  size: 40, state: characterState, badge: needs ? '?' : null),
            ),
            SizedBox(width: S.of(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TeamRow.titleStyle(
                              agent.available ? AppColors.fg1 : AppColors.fg3)),
                    ),
                    if (_isPinned) ...[
                      SizedBox(width: S.s6),
                      AppIcon('pin', size: 14, color: AppColors.fg3),
                    ],
                  ]),
                  SizedBox(height: S.of(1)),
                  Row(children: [
                    if (busy) ...[
                      Container(
                        key: const ValueKey('agent-working-dot'),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: S.of(7)),
                    ],
                    Flexible(
                      child: Text.rich(markdownPreviewSpan(sub, subStyle),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (time.isNotEmpty && !busy)
                      Text(', $time', maxLines: 1, style: subStyle),
                  ]),
                ],
              ),
            ),
            SizedBox(width: S.s8),
            AppIcon('chevron-right', size: 16, color: AppColors.fg3),
          ]),
        ),
      );
    }
    final ring = agent.available &&
        (widget.group != null
            ? widget.group == AgentGroup.working
            : working > 0);
    final presence = widget.client.presence.presenceForAgentId(agent.id);
    final group = widget.group ?? agentGroupFor(agent, presence: presence);
    // Desktop agent rows carry state but no needs-you count/badge; session
    // surfaces own that attention signal.
    final needs =
        kMobile && (group == AgentGroup.needsYou || agent.needsYou > 0);
    final crew = widget.crew;
    final lead = crew?.lead;
    final at =
        crew != null && crew.state != CrewState.standingBy && lead != null
            ? DateTime.fromMillisecondsSinceEpoch(lead.lastActive * 1000)
            : last?.at;
    final time = kMobile ? agentRowTime(at) : agentRowAgo(at);
    final detail = agent.presence?.detail.trim() ?? '';
    var line2 = _phoneLine(agent, crew, presence);
    if (kMobile && ring && crew == null && detail.isNotEmpty) line2 = detail;
    final running = !needs &&
        agent.available &&
        (crew?.state == CrewState.working ||
            ring ||
            (presence?.active ?? false) ||
            (agent.presence?.live ?? false) ||
            agent.tasksIn({'in_progress'}) > 0);
    final offline = widget.offlineHost?.trim().isNotEmpty ?? false;
    final statusKind = offline
        ? AgentRowStatusKind.offline
        : needs
            ? AgentRowStatusKind.needsYou
            : running
                ? AgentRowStatusKind.running
                : AgentRowStatusKind.idle;
    if (!agent.available) line2 = 'Wakes when you send';
    return AgentRowShell(
      selected: widget.selected,
      onTap: widget.onOpen,
      onLongPress: () {
        holdHaptic();
        _actions(null);
      },
      onSecondaryTapUp: (d) => _actions(d.globalPosition),
      avatar: AgentMochi(agent.id, size: 28),
      working: running,
      name: name,
      pinned: _isPinned,
      time: time,
      timeDetail: kMobile ? agentRowClock(at) : '',
      preview: line2,
      needs: needs,
      statusKind: statusKind,
      needsCount: agent.needsYou > 0 ? agent.needsYou : (needs ? 1 : 0),
      unread: last?.unread ?? false,
      offlineHost: widget.offlineHost,
      expanded: widget.expanded,
      expandable: widget.expandable,
      onToggleExpansion: widget.onToggleExpansion,
    );
  }
}

enum AgentRowStatusKind {
  running,
  error,
  rateLimited,
  offline,
  paused,
  needsYou,
  idle,
}

/// Desktop sidebar row for an agent or Lead: a 28 px portrait, name and time,
/// and one status line at a 40 px pitch.
class AgentRowShell extends StatefulWidget {
  const AgentRowShell({
    super.key,
    required this.avatar,
    required this.name,
    required this.preview,
    required this.onTap,
    this.time = '',
    this.timeDetail = '',
    this.dot,
    this.dotKey,
    this.needs = false,
    this.selected = false,
    this.working = false,
    this.dim = false,
    this.pinned = false,
    this.trailing,
    this.stateIcon,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.wideAvatar = false,
    this.tint,
    this.avatarFor,
    this.statusKind,
    this.needsCount = 0,
    this.unread = false,
    this.offlineHost,
    this.expanded = false,
    this.expandable = false,
    this.onToggleExpansion,
  });

  /// Draws the whole 28x22 slot, given the row's backdrop colour for rings.
  final Widget Function(Color backdrop)? avatarFor;

  final Widget avatar;

  /// The character's colour; when set the avatar sits on a lit tile.
  final Color? tint;

  /// Draws the avatar unplated in a 36x22 box spilling past the 28 px slot,
  /// so a group's side-by-side faces stay full size while names line up.
  final bool wideAvatar;
  final String name;
  final String preview;
  final String time;

  /// Smaller clock after a day-only [time], e.g. "Sat" then "4:12 pm".
  final String timeDetail;
  final Color? dot;
  final Key? dotKey;
  final bool needs;
  final bool selected;

  /// Desktop: equaliser bars take the time slot while work is under way.
  final bool working;
  final bool dim;
  final bool pinned;
  final Widget? trailing;

  /// Desktop: the one state mark at the right edge (spinner, hand or moon).
  final Widget? stateIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;

  /// The row's one explicit state. Null falls back to the legacy booleans so
  /// older callers keep their meaning.
  final AgentRowStatusKind? statusKind;
  final int needsCount;
  final bool unread;
  final String? offlineHost;

  /// Desktop: explicit expansion affordance for live session sub-rows.
  final bool expanded;
  final bool expandable;
  final VoidCallback? onToggleExpansion;

  @override
  State<AgentRowShell> createState() => _AgentRowShellState();
}

class _AgentRowShellState extends State<AgentRowShell> {
  bool _hover = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'agent-row-${widget.name}')
      ..addListener(_focusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  AgentRowStatusKind get _kind {
    final k = widget.statusKind ??
        (widget.needs
            ? AgentRowStatusKind.needsYou
            : widget.working
                ? AgentRowStatusKind.running
                : AgentRowStatusKind.idle);
    // Desktop agent rows carry no needs-you count; the Sessions inbox does.
    if (!kMobile && k == AgentRowStatusKind.needsYou) {
      return widget.working
          ? AgentRowStatusKind.running
          : AgentRowStatusKind.idle;
    }
    return k;
  }

  void _open({bool newTab = false}) {
    if (newTab) {
      middleClickOpen = true;
      widget.onTap();
      middleClickOpen = false;
    } else {
      widget.onTap();
    }
  }

  KeyEventResult _keyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    _open(newTab: keys.isMetaPressed || keys.isControlPressed);
    return KeyEventResult.handled;
  }

  String get _statusText {
    final text = widget.preview.trim();
    return switch (_kind) {
      AgentRowStatusKind.offline =>
        'Offline - ${widget.offlineHost?.trim().isNotEmpty == true ? widget.offlineHost!.trim() : 'host'}',
      AgentRowStatusKind.error => text.isEmpty ? 'Error' : text,
      AgentRowStatusKind.rateLimited => text.isEmpty ? 'Rate limited' : text,
      AgentRowStatusKind.paused => text.isEmpty ? 'Paused by you' : text,
      AgentRowStatusKind.running => text.isEmpty ? 'Running' : text,
      AgentRowStatusKind.needsYou => text,
      AgentRowStatusKind.idle => text.isEmpty ? 'Idle' : text,
    };
  }

  Widget _desktopRow(BuildContext context) {
    final focused = _focusNode.hasFocus;
    final fill = focused
        ? AppColors.sidebarFocus
        : widget.selected
            ? AppColors.sidebarPlate
            : _hover
                ? AppColors.hoverPlate
                : Colors.transparent;
    final still = reduceMotion(context);
    final kind = _kind;
    final offline = kind == AgentRowStatusKind.offline;
    final strongName = widget.selected || widget.unread;
    final nameColor = offline
        ? AppColors.fg3
        : strongName
            ? AppColors.fg1
            : AppColors.fg2;
    final needs = kind == AgentRowStatusKind.needsYou;
    final needsCount = widget.needsCount > 0
        ? widget.needsCount
        : widget.needs
            ? 1
            : 0;
    final statusStyle = switch (kind) {
      AgentRowStatusKind.needsYou => sans(12,
          weight: FontWeight.w500, height: 16 / 12, color: AppColors.fg2),
      AgentRowStatusKind.error || AgentRowStatusKind.rateLimited => sans(12,
          weight: FontWeight.w400, height: 16 / 12, color: AppColors.fg2),
      _ => sans(12,
          weight: FontWeight.w400, height: 16 / 12, color: AppColors.fg3),
    };

    Widget avatar = widget.avatar;
    if (offline) {
      avatar = ColorFiltered(
        colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.6), BlendMode.srcATop),
        child: avatar,
      );
    }

    final statusChildren = <Widget>[];
    if (needs) {
      statusChildren.addAll([
        Container(
          key: const ValueKey('agent-needs-dot'),
          width: 6,
          height: 6,
          decoration:
              BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$needsCount needs you',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: statusStyle,
          ),
        ),
      ]);
    } else {
      if (kind == AgentRowStatusKind.error ||
          kind == AgentRowStatusKind.rateLimited) {
        statusChildren.addAll([
          AppIcon('x', size: 10, color: AppColors.fg2),
          const SizedBox(width: 5),
        ]);
      } else if (kind == AgentRowStatusKind.paused) {
        statusChildren.addAll([
          AppIcon('pause', size: 10, color: AppColors.fg3),
          const SizedBox(width: 5),
        ]);
      }
      statusChildren.add(
        Expanded(
          child: Text(_statusText,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: statusStyle),
        ),
      );
      if (kind == AgentRowStatusKind.running) {
        statusChildren.addAll([
          const SizedBox(width: 6),
          Spinner(size: 11, color: AppColors.fg3),
        ]);
      }
      if (widget.unread) {
        statusChildren.addAll([
          const SizedBox(width: 6),
          Container(
            key: const ValueKey('agent-unread'),
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: AppColors.fg1, shape: BoxShape.circle),
          ),
        ]);
      }
    }

    final row = AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 150),
      curve: const Cubic(0.23, 1, 0.32, 1),
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration:
          BoxDecoration(color: fill, borderRadius: BorderRadius.circular(8)),
      child: Stack(clipBehavior: Clip.none, children: [
        if (focused)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 2,
            child: ColoredBox(color: AppColors.fg1),
          ),
        Positioned(
          left: 8,
          top: 6,
          width: 28,
          height: 28,
          child: avatar,
        ),
        Positioned(
          left: 44,
          right: 10,
          top: 2,
          height: 17,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Flexible(
              child: Text(widget.name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      weight: strongName ? FontWeight.w500 : FontWeight.w400,
                      height: 17 / 13,
                      color: nameColor)),
            ),
            if (widget.time.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(widget.time,
                  maxLines: 1,
                  style: sans(11,
                      weight: FontWeight.w400,
                      height: 16 / 11,
                      color: AppColors.fg3,
                      tabular: true)),
            ],
            if (widget.expandable) ...[
              const SizedBox(width: 4),
              GestureDetector(
                key: const ValueKey('agent-expansion-toggle'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onToggleExpansion,
                child: SizedBox(
                  width: 24,
                  height: 17,
                  child: Center(
                    child: AppIcon(
                      widget.expanded ? 'chevron-down' : 'chevron-right',
                      size: 12,
                      color: AppColors.fg2,
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
        Positioned(
          left: 44,
          right: 10,
          top: 21,
          height: 16,
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: statusChildren),
        ),
      ]),
    );

    return Tooltip(
      message: widget.name,
      waitDuration: const Duration(milliseconds: 600),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _keyEvent,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Listener(
            onPointerDown: (e) {
              if (e.kind == PointerDeviceKind.mouse &&
                  e.buttons & kMiddleMouseButton != 0) {
                _open(newTab: true);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _open,
              onLongPress: widget.onLongPress,
              onSecondaryTapUp: widget.onSecondaryTapUp,
              child: row,
            ),
          ),
        ),
      ),
    );
  }

  Widget _legacyRow(BuildContext context) {
    final fill = widget.selected
        ? AppColors.surface3
        : _hover
            ? AppColors.fg1.withValues(alpha: 0.07)
            : Colors.transparent;
    final ring = Color.alphaBlend(fill, AppColors.windowBg);
    final still = reduceMotion(context);
    final tiled = !kMobile &&
        (widget.avatarFor != null ||
            (widget.tint != null && !widget.wideAvatar));
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (e) {
          if (!kMobile &&
              e.kind == PointerDeviceKind.mouse &&
              e.buttons & kMiddleMouseButton != 0) {
            middleClickOpen = true;
            widget.onTap();
            middleClickOpen = false;
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTapUp: widget.onSecondaryTapUp,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: AnimatedContainer(
              duration:
                  still ? Duration.zero : const Duration(milliseconds: 150),
              curve: const Cubic(0.23, 1, 0.32, 1),
              padding: EdgeInsets.symmetric(
                  horizontal: 8, vertical: kMobile ? 6 : 5.5),
              decoration: BoxDecoration(
                  color: fill, borderRadius: BorderRadius.circular(R.of(8))),
              child: Opacity(
                opacity: widget.dim ? 0.55 : 1,
                // One line: avatar, name and last-message time; the avatar dot
                // and the trailing mark carry the state.
                child: Row(children: [
                  // Lit tiles: a 20px slot flush with the header, 10px to the
                  // name, as in the reference; plates keep the 28px slot.
                  SizedBox(
                    width: tiled || !kMobile ? rowAvatarSize(34) : 28,
                    height: tiled ? rowAvatarSize(34) : 22,
                    child: Stack(clipBehavior: Clip.none, children: [
                      if (widget.avatarFor != null)
                        Positioned.fill(child: widget.avatarFor!(ring))
                      else if (widget.tint != null && !widget.wideAvatar)
                        Positioned.fill(
                            child: LitTile(widget.tint!, widget.avatar))
                      else if (widget.wideAvatar)
                        Positioned(
                          left: -4,
                          top: 0,
                          width: 36,
                          height: 22,
                          child: widget.avatar,
                        )
                      else
                        Positioned(
                          left: 3,
                          top: 0,
                          width: 22,
                          height: 22,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(R.of(6)),
                            child: ColoredBox(
                                color: AppColors.surface2,
                                child: FittedBox(child: widget.avatar)),
                          ),
                        ),
                      if (widget.dot != null && kMobile)
                        Positioned(
                          right: 1,
                          bottom: -2,
                          child: Container(
                            key: widget.dotKey,
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: widget.dot,
                              shape: BoxShape.circle,
                              border: Border.all(color: ring, width: 2),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(children: [
                      Flexible(
                        child: Text(widget.name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: kMobile
                                ? sans(13,
                                    weight: FontWeight.w500,
                                    color: widget.needs
                                        ? AppColors.fg1
                                        : AppColors.fg2)
                                : sans(14, color: AppColors.fg1)),
                      ),
                      if (widget.pinned) ...[
                        const SizedBox(width: 6),
                        AppIcon('pin', size: 11, color: AppColors.fg4),
                      ],
                    ]),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 6),
                    widget.trailing!,
                  ],
                  // Last at the edge so the state marks form one column.
                  if (!kMobile) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: Center(child: widget.stateIcon)),
                  ] else if (widget.time.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text.rich(
                        TextSpan(children: [
                          TextSpan(text: widget.time),
                          if (widget.timeDetail.isNotEmpty)
                            TextSpan(
                                text: ' ${widget.timeDetail}',
                                style: sans(10,
                                    color: AppColors.fg4.withValues(alpha: 0.7),
                                    tabular: true)),
                        ]),
                        maxLines: 1,
                        style: kMobile
                            ? sans(11, color: AppColors.fg3, tabular: true)
                            : sans(12.5, color: AppColors.fg3, tabular: true)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      kMobile ? _legacyRow(context) : _desktopRow(context);
}

/// A short accent arc turning round an avatar while its agent works.
class WorkingRing extends StatefulWidget {
  const WorkingRing({super.key});

  @override
  State<WorkingRing> createState() => _WorkingRingState();
}

class _WorkingRingState extends State<WorkingRing> {
  final _spin = AmbientLoop(const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spin.bind(context);
    if (reduceMotion(context)) {
      _spin.stop();
    } else {
      _spin.start();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _RingPainter(_spin, AppColors.accent),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.turn, this.color) : super(repaint: turn);

  final Animation<double> turn;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final outline = avatarBorder(rect.width).getOuterPath(rect);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.18);
    canvas.drawPath(outline, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    // Same sweep as the old 1.9 rad arc, traced along whatever outline the theme uses.
    final metric = outline.computeMetrics().first;
    final len = metric.length;
    final start = turn.value * len;
    final end = start + len * 1.9 / (2 * 3.141592653589793);
    canvas.drawPath(metric.extractPath(start, end.clamp(0, len)), arc);
    if (end > len) canvas.drawPath(metric.extractPath(0, end - len), arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

/// Desktop sidebar row: 60px, radius 14, 2px gap, selected on the row surface.
class DeskRow extends StatelessWidget {
  const DeskRow({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.time = '',
    this.trailing,
    this.selected = false,
    this.dim = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.plate = true,
  });

  final Widget avatar;

  /// False draws [avatar] bare, e.g. a group's stacked members.
  final bool plate;
  final Widget title;
  final Widget subtitle;
  final String time;
  final Widget? trailing;
  final bool selected;
  final bool dim;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;

  static TextStyle nameStyle([Color? c]) =>
      sans(13, weight: W.label, color: c ?? AppColors.fg1);
  static TextStyle previewStyle() =>
      sans(12, height: 16 / 12, color: AppColors.fg3);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onSecondaryTapUp: onSecondaryTapUp,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: selected ? C7.row : Colors.transparent,
            borderRadius: BorderRadius.circular(R.of(10)),
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(R.of(10)),
              hoverColor: C7.row.withValues(alpha: 0.5),
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Opacity(
                    opacity: dim ? 0.55 : 1,
                    child: Row(children: [
                      plate
                          ? Container(
                              width: 28,
                              height: 28,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: Grouped.plate),
                              alignment: Alignment.center,
                              child: avatar,
                            )
                          : SizedBox.square(
                              dimension: 28,
                              child: OverflowBox(
                                  maxWidth: 36, maxHeight: 36, child: avatar)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Expanded(child: title),
                                  if (time.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(time,
                                        maxLines: 1,
                                        style: sans(11,
                                            color: AppColors.fg4,
                                            tabular: true)),
                                  ],
                                ]),
                            const SizedBox(height: 2),
                            Row(children: [
                              Expanded(child: subtitle),
                              if (trailing != null) ...[
                                const SizedBox(width: 8),
                                trailing!,
                              ],
                            ]),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Phone grouped rows: each row its own surface on the page, 2px apart, the
/// group rounded 20 at its ends and 4 inside.
class TeamRows extends StatelessWidget {
  const TeamRows({super.key, required this.children});

  final List<Widget> children;

  static const ends = 20.0;
  static const inner = 4.0;

  @override
  Widget build(BuildContext context) {
    final n = children.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(i == 0 ? ends : inner),
              bottom: Radius.circular(i == n - 1 ? ends : inner),
            ),
            child: ColoredBox(color: TeamRow.surface, child: children[i]),
          ),
        ],
      ],
    );
  }
}

/// One row inside [TeamRows]: min 64 (76 when tall), padding 12/16.
class TeamRow extends StatelessWidget {
  const TeamRow({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tall = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool tall;

  static Color get surface => AppColors.surface3;

  static TextStyle titleStyle([Color? c]) =>
      sans(17, height: 22 / 17, color: c ?? AppColors.fg1);

  static TextStyle subtitleStyle([Color? c]) =>
      sans(15, height: 20 / 15, color: c ?? AppColors.fg3);

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppColors.hover,
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tall ? 76 : 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
          ),
        ),
      );
}

/// Squarish tile in the character's colour, lit from the top left.
class LitTile extends StatelessWidget {
  const LitTile(this.tint, this.avatar, {super.key, this.ring});
  final Color tint;
  final Widget avatar;

  /// Cut-out ring in the backdrop colour, for a tile overlapping another.
  final Color? ring;

  /// An agent's character on its lit tile; plain plate until colours load.
  static Widget agent(String id, {double size = 22, Color? ring}) {
    final tint = agentTintFor(id);
    final face = AgentMochi(id, size: size);
    return SizedBox(
      width: size,
      height: size,
      child: tint == null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.27),
              child: ColoredBox(
                  color: AppColors.surface2, child: FittedBox(child: face)))
          : LitTile(tint, face, ring: ring),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = HSLColor.fromColor(tint);
    final light = h
        .withSaturation(h.saturation.clamp(0.0, 0.70))
        .withLightness(0.42)
        .toColor();
    final deep = h
        .withSaturation(h.saturation.clamp(0.0, 0.60))
        .withLightness(0.16)
        .toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: ring == null ? null : Border.all(color: ring!, width: 2),
        gradient: RadialGradient(
          center: const Alignment(-0.36, -0.44),
          radius: 1.0,
          colors: [light, deep],
          stops: const [0, 0.75],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(1, 2, 1, 0),
          child: FittedBox(child: avatar),
        ),
      ),
    );
  }
}
