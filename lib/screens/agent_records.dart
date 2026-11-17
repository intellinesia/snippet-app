import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../clock.dart';
import '../swr.dart';
import '../crew_widgets.dart';
import '../media_views.dart' show DaemonScope;
import '../models.dart';
import '../motion_routes.dart';
import '../panel.dart';
import '../platform.dart';
import '../pull_refresh.dart';
import '../shell_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets.dart';
import '../mochi.dart' show AgentMochi;
import '../settings_form.dart';
import 'list_search_field.dart';
import 'memory_screen.dart';
import 'mobile_chrome.dart';
import 'session.dart';
import 'session_coordination_cards.dart';
import 'tasks/task_common.dart';

const _pageSize = 50;

double get _title => kMobile ? 15 : 13;
double get _body => kMobile ? 14 : 12.5;
double get _meta => kMobile ? 12 : 11;
double get _gutter => kMobile ? M.gutter : 12;

DateTime? _time(String raw) => DateTime.tryParse(raw)?.toLocal();

String _clock(DateTime t) => clock12(t);

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
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
  'Dec',
];

String _dayLabel(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  final date = '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
  return t.year == now.year ? date : '$date ${t.year}';
}

final _uuid = RegExp(
    r'\b([0-9a-f]{8})-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b');

String _plain(String text) => text
    .replaceAll(RegExp(r'^\s*[#>]+\s*', multiLine: true), '')
    .replaceAll(RegExp(r'[*`]+'), '')
    .replaceAllMapped(_uuid, (m) => m[1]!)
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _folder(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  return parts.length <= 2
      ? parts.join('/')
      : parts.sublist(parts.length - 2).join('/');
}

void _presentRecords(BuildContext host, String title, String agentName,
        Widget Function() view) =>
    openAgentRecordsPage(host, title, agentName, view);

/// Inbox or board as its own page. On a phone it stacks on whatever opened
/// it, so back returns there.
void openAgentRecordsPage(BuildContext host, String title, String agentName,
    Widget Function() view) {
  if (kMobile) {
    Navigator.of(host, rootNavigator: true).push<void>(AppPageRoute<void>(
        builder: (page) => _RecordsPage(
            title: title,
            subtitle: agentName,
            onClose: () => Navigator.of(page).pop(),
            child: view())));
    return;
  }
  presentScreen(host,
        style: PanelStyle.drawer,
        maxWidth: 720,
        maxHeight: 820,
        builder: (_, close) => _RecordsPage(
            title: title, subtitle: agentName, onClose: close, child: view()));
}

/// Entries that arrived since the inbox was last opened, as the inbox itself
/// marks them. Capped at one page.
Future<int> agentInboxUnread(DaemonClient client, String agentId) async {
  final seen =
      (await SharedPreferences.getInstance()).getInt('inbox_seen_$agentId') ??
          0;
  if (seen <= 0) return 0;
  final entries = await client.agentInbox(agentId, limit: _pageSize);
  return entries.where((e) => e.id > seen && e.fromKind != 'human').length;
}

const agentInboxFilters = [
  ('All', null),
  ('Task offers', 'offer'),
  ('Messages', 'message'),
  ('Task rooms', 'room'),
];

const agentBoardFilters = [
  ('All', null),
  ('By task', 'by-task'),
  ('By folder', 'by-folder'),
  ('Waiting', 'waiting'),
  ('Dispatched', 'dispatched'),
  ('Reported', 'reported'),
  ('Progress', 'progress'),
  ('Notes', 'noted'),
];

/// The inbox or board body, to sit inside another screen. With [filterChips]
/// off the host picks the filter and passes it as [filter].
Widget agentRecordsBody(DaemonClient client, String agentId, String agentName,
        {required bool board, String? filter, bool filterChips = true}) =>
    board
        ? AgentBoardView(
            client: client,
            agentId: agentId,
            agentName: agentName,
            filter: filter,
            filterChips: filterChips)
        : AgentInboxView(
            client: client,
            agentId: agentId,
            agentName: agentName,
            filter: filter,
            filterChips: filterChips);

void openAgentDesk(BuildContext context, DaemonClient client, String agentId,
        String agentName) =>
    _openSession(context, client, 'inbox-$agentId', '$agentName desk');

/// An agent's Actions: a full page on a phone. Desktop shows [AgentActions]
/// in the shell's right panel instead.
Future<void> openAgentActions(
  BuildContext context, {
  required DaemonClient client,
  required String agentId,
  required String agentName,
  VoidCallback? onDeleted,
  bool views = true,
}) {
  if (kMobile) {
    return Navigator.of(context).push<void>(AppPageRoute<void>(
      builder: (page) => Material(
        color: AppColors.pageBg,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    Grouped.gutter, 8, Grouped.gutter, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GroupedCircleButton(
                      icon: 'chevron-left',
                      tooltip: 'Back',
                      onTap: () => Navigator.of(page).pop()),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      Grouped.gutter, 0, Grouped.gutter, S.of(28)),
                  child: AgentActions(
                    client: client,
                    agentId: agentId,
                    agentName: agentName,
                    host: page,
                    views: views,
                    onDeleted: () {
                      Navigator.of(page).pop();
                      onDeleted?.call();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
  return presentScreen<void>(context,
      style: PanelStyle.drawer,
      maxWidth: 460,
      builder: (ctx, close) => Material(
            color: AppColors.pageBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Grouped.gutter, 8, Grouped.gutter, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GroupedCircleButton(
                        icon: 'x', tooltip: 'Close', onTap: close),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        Grouped.gutter, 0, Grouped.gutter, S.of(28)),
                    child: AgentActions(
                      client: client,
                      agentId: agentId,
                      agentName: agentName,
                      host: ctx,
                      views: views,
                      onDeleted: () {
                        close();
                        onDeleted?.call();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ));
}

/// The agent's actions as rows. With [onAction] each row reports its name
/// (`inbox`, `board`, `desk`, `memory`, `wakes`, `model`, `nickname`,
/// `avatar`, `color`, `delete`) to the caller, which is how the desktop shell
/// opens them inside its right panel. Without it a row opens its own screen
/// from [host], as on a phone.
class AgentActions extends StatefulWidget {
  const AgentActions({
    super.key,
    required this.client,
    required this.agentId,
    required this.agentName,
    this.host,
    this.dismiss,
    this.onDeleted,
    this.onAction,
    this.views = true,
  });

  final ValueChanged<String>? onAction;

  /// Off where the host already switches to the inbox, board and desk.
  final bool views;

  final DaemonClient client;
  final String agentId;
  final String agentName;

  /// Where the chosen action opens. On desktop [dismiss] closes the sheet first.
  final BuildContext? host;
  final VoidCallback? dismiss;
  final VoidCallback? onDeleted;

  @override
  State<AgentActions> createState() => AgentActionsState();
}

class AgentActionsState extends State<AgentActions> {
  CoordinationAgent? _agent;
  int? _unread;
  int? _memoryEntries;

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((all) {
      if (!mounted) return;
      setState(
          () => _agent = all.where((a) => a.id == widget.agentId).firstOrNull);
    }).catchError((_) {});
    if (widget.onAction == null && widget.views) {
      agentInboxUnread(widget.client, widget.agentId).then((n) {
        if (mounted) setState(() => _unread = n);
      }).catchError((_) {});
      widget.client.memoryScopes().then((all) {
        final mine =
            all.where((m) => m.key == 'agent:${widget.agentId}').firstOrNull;
        if (mounted && mine != null) {
          setState(() => _memoryEntries = mine.entries);
        }
      }).catchError((_) {});
    }
  }

  void _run(void Function(BuildContext) action, [String? name]) {
    final report = widget.onAction;
    if (report != null && name != null) return report(name);
    widget.dismiss?.call();
    action(widget.host!);
  }

  void _openRecords(String name, String title, Widget Function() view) => _run(
      (host) => _presentRecords(host, title, widget.agentName, view), name);

  Widget _row(String icon, String label, String detail,
          {bool danger = false, VoidCallback? onTap}) =>
      SettingsRow(
        leading: V5IconTile(icon, color: danger ? AppColors.danger : null),
        label: label,
        sub: kMobile ? detail : null,
        labelWidget: kMobile
            ? null
            : Row(children: [
                Text(label,
                    style: TS.rowTitle(
                        danger ? AppColors.danger : AppColors.fg1)),
                SizedBox(width: S.s8),
                Expanded(
                    child: Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.meta())),
              ]),
        danger: danger,
        chevron: !danger && onTap != null,
        onTap: onTap,
      );

  Widget _setting(String action, String icon, String label, String detail,
      {bool danger = false}) {
    final agent = _agent;
    return _row(
      icon,
      label,
      detail,
      danger: danger,
      onTap: agent == null && widget.onAction == null
          ? null
          : () => _run(
              (host) => runCrewAgentAction(host, action,
                  client: widget.client,
                  agent: agent!,
                  onDeleted: action == 'delete' ? widget.onDeleted : null),
              action),
    );
  }

  Widget _memory() => _row(
        'book-marked',
        'Memory',
        'What this agent remembers',
        onTap: () => _run(
            (host) => presentScreen(host,
                builder: (_, close) => MemoryScreen(
                    client: widget.client,
                    embedded: true,
                    onBack: close,
                    initialKey: 'agent:${widget.agentId}')),
            'memory'),
      );

  Widget _header() {
    final model = _agent?.deskProfile ?? _agent?.profile;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, S.s8),
      child: Row(children: [
        AgentMochi(widget.agentId, size: 64),
        SizedBox(width: S.s16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.agentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(20, weight: W.title, color: AppColors.fg1)),
              if (model != null && model.isNotEmpty)
                Text(model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg3)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _sheetRow(BuildContext ctx, String label, String? value,
          VoidCallback run) =>
      SettingsRow(
          label: label,
          value: value,
          chevron: true,
          onTap: () {
            Navigator.of(ctx).pop();
            run();
          });

  void _nameAndAppearance() {
    final agent = _agent;
    if (agent == null) return;
    showAppSheet<void>(
      context,
      title: 'Name and appearance',
      child: Builder(
        builder: (ctx) => SettingsGroup(children: [
          _sheetRow(
              ctx,
              'Nickname',
              agent.displayName,
              () => _run(
                  (h) => runCrewAgentAction(h, 'nickname',
                      client: widget.client,
                      agent: agent,
                      onDeleted: widget.onDeleted),
                  'nickname')),
          _sheetRow(
              ctx,
              'Appearance',
              null,
              () => _run(
                  (h) => runCrewAgentAction(h, 'appearance',
                      client: widget.client, agent: agent),
                  'appearance')),
        ]),
      ),
    );
  }

  Widget _pageBuild() {
    final client = widget.client;
    final id = widget.agentId;
    final name = widget.agentName;
    final agent = _agent;
    final profile = (agent?.profile ?? '').trim();
    final inbox = _unread;
    final presence = agent?.presence;
    final open = agent?.taskCounts == null
        ? null
        : agent!.tasksIn({'in_progress', 'todo'});
    final mem = _memoryEntries;
    String? plural(int? n, String one, String many) =>
        n == null ? null : '$n ${n == 1 ? one : many}';
    final tiles = <Widget>[
      _WorkTile(
          icon: 'inbox',
          label: 'Inbox',
          sub: inbox == null
              ? null
              : inbox == 0
                  ? 'Nothing new'
                  : '$inbox new',
          accent: (inbox ?? 0) > 0,
          onTap: () => _openRecords(
              'inbox',
              'Inbox',
              () => AgentInboxView(
                  client: client, agentId: id, agentName: name))),
      _WorkTile(
          icon: 'columns-3',
          label: 'Board',
          sub: plural(open, 'open', 'open'),
          onTap: () => _openRecords(
              'board',
              'Board',
              () => AgentBoardView(
                  client: client, agentId: id, agentName: name))),
      _WorkTile(
          icon: 'message-circle',
          label: 'Desk',
          sub: presence == null
              ? null
              : presence.active
                  ? '${presence.state[0].toUpperCase()}${presence.state.substring(1)}'
                  : 'Idle',
          onTap: () => _run(
              (host) => _openSession(host, client, 'inbox-$id', '$name desk'),
              'desk')),
      _WorkTile(
          icon: 'book',
          label: 'Memory',
          sub: plural(mem, 'entry', 'entries'),
          onTap: () => _run(
              (host) => presentScreen(host,
                  builder: (_, close) => MemoryScreen(
                      client: client,
                      embedded: true,
                      onBack: close,
                      initialKey: 'agent:$id')),
              'memory')),
    ];
    SettingsRow setting(String action, String icon, String label,
            {String? value}) =>
        SettingsRow(
          icon: icon,
          label: label,
          value: value,
          chevron: true,
          onTap: agent == null
              ? null
              : () => _run(
                  (host) => runCrewAgentAction(host, action,
                      client: client, agent: agent),
                  action),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '$name, ${profile.isEmpty ? 'Routing default' : profile}',
          excludeSemantics: true,
          child: Padding(
            padding: EdgeInsets.only(bottom: S.s16),
            child: SettingsHero(
              plate: false,
              avatar: AgentMochi(id, size: Grouped.avatarCharacter),
              name: name,
              sub: profile.isEmpty ? 'Routing default' : profile,
            ),
          ),
        ),
        if (widget.views)
          Padding(
            padding: EdgeInsets.only(bottom: Grouped.sectionGap),
            child: _TileGrid(tiles: tiles),
          ),
        SettingsGroup(header: 'Settings', children: [
          if (!widget.views)
            SettingsRow(
                icon: 'book',
                label: 'Memory',
                sub: 'What this agent remembers',
                chevron: true,
                onTap: () => tiles[3] is _WorkTile
                    ? (tiles[3] as _WorkTile).onTap()
                    : null),
          setting('wakes', 'repeat', 'Wakes and reporting'),
          setting('reach', 'bell', 'How it reaches you'),
          setting('model', 'cpu', 'Models and context',
              value: profile.isEmpty ? 'Default' : profile),
          SettingsRow(
              icon: 'star',
              label: 'Name and appearance',
              value: agent?.displayName ?? name,
              chevron: true,
              onTap: agent == null ? null : _nameAndAppearance),
        ]),
        SettingsGroup(children: [
          SettingsRow(
            icon: 'trash',
            label: 'Delete agent',
            sub: 'Removes its identity and notes',
            danger: true,
            onTap: agent == null
                ? null
                : () => _run(
                    (host) => runCrewAgentAction(host, 'delete',
                        client: client,
                        agent: agent,
                        onDeleted: widget.onDeleted),
                    'delete'),
          ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onAction == null) return _pageBuild();
    final client = widget.client;
    final id = widget.agentId;
    final name = widget.agentName;
    // In the desktop shell the header switcher covers Inbox and Board, and
    // naming and looks belong to the agent list, not the agent's own screen.
    final inShell = widget.onAction != null;
    final wakes = _setting('wakes', 'repeat', 'Wakes and reporting',
        'When it wakes and who it tells');
    final reach = _setting('reach', 'bell', 'How it reaches you',
        'Notifications and where each kind goes');
    final model = _setting(
        'model', 'cpu', 'Models and context', 'Desk and task models, context length');
    final nickname =
        _setting('nickname', 'edit', 'Nickname', 'What it is called here');
    final appearance = _setting('appearance', 'sparkles', 'Appearance',
        'Avatar and colour across the app');
    final delete = _setting(
        'delete', 'trash', 'Delete agent', 'Removes its identity and notes',
        danger: true);
    if (!widget.views) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroup(
              header: 'Agent',
              children: [_memory(), wakes, reach, model]),
          SettingsGroup(
              header: 'Appearance', children: [nickname, appearance, delete]),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!inShell) _header(),
        SettingsGroup(header: 'Agent', children: [
          wakes,
          reach,
          model,
          if (!inShell) ...[nickname, appearance],
          delete,
        ]),
        SettingsGroup(header: 'Work', children: [
          if (!inShell)
            _row('inbox', 'Inbox', 'Everything sent to this agent',
                onTap: () => _openRecords(
                    'inbox',
                    'Inbox',
                    () => AgentInboxView(
                        client: client, agentId: id, agentName: name))),
          if (!inShell)
            _row('kanban', 'Board', 'What it dispatched, reported and noted',
                onTap: () => _openRecords(
                    'board',
                    'Board',
                    () => AgentBoardView(
                        client: client, agentId: id, agentName: name))),
          _row('chat', 'Desk session', 'The conversation where its mail arrives',
              onTap: () => _run(
                  (host) =>
                      _openSession(host, client, 'inbox-$id', '$name desk'),
                  'desk')),
          _memory(),
        ]),
      ],
    );
  }
}

/// The 2x2 work tiles: [Grouped.gap] apart, round only at the outer corners.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final end = Radius.circular(R.of(Grouped.radiusEnd));
    final inner = Radius.circular(R.of(Grouped.radiusInner));
    BorderRadius corner(int i) => BorderRadius.only(
        topLeft: i == 0 ? end : inner,
        topRight: i == 1 ? end : inner,
        bottomLeft: i == 2 ? end : inner,
        bottomRight: i == 3 ? end : inner);
    Widget cell(int i) => Expanded(
        child: GroupedTile(radius: corner(i), child: tiles[i]));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          cell(0),
          const SizedBox(width: Grouped.gap),
          cell(1),
        ]),
      ),
      const SizedBox(height: Grouped.gap),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          cell(2),
          const SizedBox(width: Grouped.gap),
          cell(3),
        ]),
      ),
    ]);
  }
}

class _WorkTile extends StatelessWidget {
  const _WorkTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub,
    this.accent = false,
  });

  final String icon;
  final String label;
  final String? sub;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              Grouped.padX, 14, Grouped.padX, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsIcon(icon, color: accent ? AppColors.accent : null),
              const SizedBox(height: 14),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Grouped.titleStyle()),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Grouped.subStyle()),
                ),
            ],
          ),
        ),
      );
}

/// An inbox or board on its own page, under a session-style bar.
class _RecordsPage extends StatelessWidget {
  const _RecordsPage(
      {required this.title,
      required this.subtitle,
      required this.onClose,
      required this.child});

  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kMobile ? AppColors.pageCanvas : Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kMobile)
              MobileBackBar(title: title, subtitle: subtitle, onBack: onClose)
            else
              Container(
                height: 44,
                padding: EdgeInsets.only(left: S.s12, right: S.s6),
                color: AppColors.paneBg,
                child: Row(children: [
                  Text(title,
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                  SizedBox(width: S.s8),
                  Expanded(
                    child: Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ),
                  IconBtn('x',
                      size: 28, iconSize: 15, tooltip: 'Close', onTap: onClose),
                ]),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

typedef _Load<T> = Future<List<T>> Function(
    {int? before, String? query, String? filter});

/// A searchable, filterable, day-grouped history that loads older pages as it
/// scrolls. The inbox and the board differ only in their rows and their source.
class _RecordList<T> extends StatefulWidget {
  const _RecordList({
    super.key,
    required this.hint,
    required this.filters,
    required this.load,
    required this.idOf,
    required this.timeOf,
    required this.row,
    required this.empty,
    required this.client,
    required this.liveOn,
    this.groupedFilters = const {},
    this.filter,
    this.filterChips = true,
    this.card = false,
  });

  final String? filter;
  final bool filterChips;

  /// Rows in one grouped card, with the first three filters as a segmented
  /// control and the rest as outlined pills.
  final bool card;
  final DaemonClient client;
  final SwrTrigger liveOn;

  /// Filters whose rows stand for groups: a group's newest row changes, so a
  /// poll replaces the list rather than prepending to it.
  final Set<String> groupedFilters;
  final String hint;
  final List<(String, String?)> filters;
  final _Load<T> load;
  final int Function(T) idOf;
  final String Function(T) timeOf;
  final Widget Function(T) row;
  final String empty;

  @override
  State<_RecordList<T>> createState() => _RecordListState<T>();
}

class _RecordListState<T> extends State<_RecordList<T>> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  Revalidator? _live;
  List<T> _items = [];
  String? _filter;
  String? _error;
  bool _loading = true;
  bool _more = false;
  bool _loadingMore = false;
  int _generation = 0;

  String? get _query {
    final q = _search.text.trim();
    return q.isEmpty ? null : q;
  }

  @override
  void initState() {
    super.initState();
    if (!widget.filterChips) _filter = widget.filter;
    _scroll.addListener(_nearEnd);
    _reload();
    _live = Revalidator(
        client: widget.client,
        on: widget.liveOn,
        debounce: const Duration(seconds: 1),
        onRevalidate: ({required bool force}) => _pollHead());
  }

  @override
  void didUpdateWidget(_RecordList<T> old) {
    super.didUpdateWidget(old);
    if (!widget.filterChips && widget.filter != _filter) {
      _pickFilter(widget.filter);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _live?.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final page = await widget.load(query: _query, filter: _filter);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page;
        _more = page.length >= _pageSize;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pollHead() async {
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        _loading ||
        _items.isEmpty) {
      return;
    }
    final generation = _generation;
    try {
      final page = await widget.load(query: _query, filter: _filter);
      if (!mounted || generation != _generation) return;
      final newest = widget.idOf(_items.first);
      final fresh = page.where((e) => widget.idOf(e) > newest).toList();
      if (fresh.isEmpty) return;
      setState(() {
        if (widget.groupedFilters.contains(_filter)) {
          _items = page;
          _more = page.length >= _pageSize;
        } else {
          _items = [...fresh, ..._items];
        }
      });
    } catch (_) {
      // The next poll or a pull retries; a blip shouldn't replace the list.
    }
  }

  void _nearEnd() {
    if (_scroll.position.extentAfter < 400) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more || _items.isEmpty) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.load(
          before: widget.idOf(_items.last), query: _query, filter: _filter);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [..._items, ...page];
        _more = page.length >= _pageSize;
      });
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _reload);
  }

  void _pickFilter(String? value) {
    setState(() {
      _filter = value;
      _loading = true;
    });
    _reload();
  }

  /// The rows with a day heading wherever the day changes.
  List<Object> _rows() {
    final rows = <Object>[];
    String? day;
    for (final item in _items) {
      final t = _time(widget.timeOf(item));
      final label = t == null ? '' : _dayLabel(t);
      if (label != day && label.isNotEmpty) rows.add(label);
      day = label;
      rows.add(item as Object);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(_gutter, kMobile ? S.s12 : S.of(10), _gutter, S.s8),
        child: ListSearchField(
          controller: _search,
          hint: widget.hint,
          onChanged: _searchChanged,
        ),
      ),
      if (widget.filterChips && widget.card) _cardFilters(),
      if (widget.filterChips && !widget.card)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, S.s6),
          child: Row(children: [
            for (final (label, value) in widget.filters)
              _FilterChip(
                label: label,
                selected: value == _filter,
                onTap: () => _pickFilter(value),
              ),
          ]),
        ),
      Expanded(child: _list()),
    ]);
    if (kMobile) return content;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720), child: content),
    );
  }

  Widget _cardFilters() {
    final segs = widget.filters.take(3).toList();
    final pills = widget.filters.skip(3).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, S.s8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _SegBar(
            labels: [for (final (l, _) in segs) l],
            selected: segs.indexWhere((f) => f.$2 == _filter),
            onTap: (i) => _pickFilter(segs[i].$2),
          ),
        ),
        SizedBox(height: S.of(10)),
        Wrap(spacing: S.s6, runSpacing: S.s6, children: [
          for (final (label, value) in pills)
            _PillChip(
              label: label,
              selected: value == _filter,
              onTap: () => _pickFilter(value == _filter ? null : value),
            ),
        ]),
      ]),
    );
  }

  Widget _cardRows(List<Object> rows) {
    final entries = [for (final r in rows) if (r is! String) r as T];
    return Padding(
      padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(kMobile ? R.lg : R.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) Container(height: 1, color: AppColors.line),
              widget.row(entries[i]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: AppColors.fg3),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _Notice(
        text: "Couldn't load this. $_error",
        action: 'Try again',
        onAction: () {
          setState(() => _loading = true);
          _reload();
        },
      );
    }
    if (_items.isEmpty) {
      final q = _query;
      return _Notice(text: q != null ? 'Nothing matches "$q".' : widget.empty);
    }
    final rows = _rows();
    return PullToRefresh(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: S.s32),
        itemCount: (widget.card ? 1 : rows.length) + (_more ? 1 : 0),
        itemBuilder: (context, i) {
          if (widget.card && i == 0) return _cardRows(rows);
          if (i == (widget.card ? 1 : rows.length)) {
            return Padding(
              padding: EdgeInsets.all(S.s16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.fg3),
                ),
              ),
            );
          }
          final row = rows[i];
          if (row is String) return _DayHeading(row, first: i == 0);
          return widget.row(row as T);
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: S.s4),
      child: Material(
        color: selected
            ? (kMobile ? AppColors.surface3 : AppColors.tint2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(kMobile ? 18 : 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobile ? 18 : 6),
          onTap: onTap,
          child: Container(
            height: kMobile ? 34 : 26,
            padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s12 : S.s8),
            alignment: Alignment.center,
            child: Text(label,
                style: sans(kMobile ? 13 : 12,
                    weight: W.label,
                    color: selected ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      ),
    );
  }
}

/// The segmented control of the mockup: a rounded track with the chosen
/// segment raised.
class _SegBar extends StatelessWidget {
  const _SegBar(
      {required this.labels, required this.selected, required this.onTap});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final h = kMobile ? 32.0 : 24.0;
    final radius = BorderRadius.circular(kMobile ? R.md : R.sm);
    return Container(
      padding: EdgeInsets.all(S.of(3)),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(kMobile ? R.lg : R.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Material(
              color: i == selected ? AppColors.surface3 : Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                borderRadius: radius,
                onTap: () => onTap(i),
                child: SizedBox(
                  height: h,
                  child: Center(
                    child: Text(labels[i],
                        maxLines: 1,
                        style: sans(kMobile ? 13 : 12,
                            weight: i == selected ? W.label : W.body,
                            color: i == selected
                                ? AppColors.fg1
                                : AppColors.fg3)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.surface3 : AppColors.surface1,
        shape: StadiumBorder(
            side: BorderSide(
                color: selected ? AppColors.accent : AppColors.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: kMobile ? 30 : 26,
            padding: EdgeInsets.symmetric(horizontal: S.of(10)),
            child: Center(
              widthFactor: 1,
              child: Text(label,
                  style: sans(12,
                      color: selected ? AppColors.fg1 : AppColors.fg2)),
            ),
          ),
        ),
      );
}

class _DayHeading extends StatelessWidget {
  const _DayHeading(this.label, {required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(_gutter, first ? S.s8 : S.s20, _gutter, S.s4),
        child: Text(label,
            style: sans(_meta, weight: W.label, color: AppColors.fg3)),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(S.of(28)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text,
                textAlign: TextAlign.center,
                style: sans(_body, color: AppColors.fg3, height: 1.45)),
            if (action != null)
              TextButton(
                onPressed: onAction,
                child:
                    Text(action!, style: sans(_body, color: AppColors.accent)),
              ),
          ]),
        ),
      );
}

class _StateTag extends StatelessWidget {
  const _StateTag(this.label, this.color, {this.neutral = false});

  final String label;
  final Color color;

  /// A raised-surface background instead of the colour's 13% tint.
  final bool neutral;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: S.s6, vertical: S.s2),
        decoration: BoxDecoration(
          color: neutral
              ? AppColors.surface3
              : color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(R.xs),
        ),
        child: Text(label,
            maxLines: 1, style: sans(_meta, weight: W.label, color: color)),
      );
}

/// One tappable record: a heading line with its time beside it, then the
/// content. An unread row gets a dot and a stronger title.
class _RecordRow extends StatelessWidget {
  const _RecordRow(
      {required this.leading,
      required this.time,
      required this.child,
      required this.onTap,
      this.unread = false,
      this.selected = false});

  final Widget leading;
  final String time;
  final Widget child;
  final VoidCallback onTap;
  final bool unread;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = _time(time);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: kMobile ? 0 : S.s6),
      child: Material(
        color: selected ? AppColors.tint2 : Colors.transparent,
        borderRadius: BorderRadius.circular(kMobile ? 0 : R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: kMobile ? AppColors.surface1 : AppColors.tint3,
          child: Stack(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(_gutter + (kMobile ? S.s12 : S.s12),
                  kMobile ? S.of(10) : S.s8, _gutter, kMobile ? S.of(10) : S.s8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Flexible(child: leading),
                      if (t != null) ...[
                        SizedBox(width: S.s8),
                        Text(_clock(t),
                            style: TS.meta(AppColors.fg3).copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ],
                    ]),
                    SizedBox(height: S.s2),
                    child,
                  ]),
            ),
            if (unread)
              Positioned(
                left: _gutter - (kMobile ? 0 : 2),
                top: kMobile ? 17 : 14,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// One board row: a lead (kind pill or group title), the text, and its time.
class _BoardRow extends StatelessWidget {
  const _BoardRow(
      {required this.lead,
      required this.child,
      required this.time,
      required this.onTap,
      });

  final Widget lead;
  final Widget child;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = _time(time);
    final grouped = lead is Row;
    return InkWell(
      onTap: onTap,
      hoverColor: AppColors.tint3,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: S.of(12), vertical: kMobile ? S.of(10) : S.s8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!grouped) ...[lead, SizedBox(width: S.of(10))],
          Expanded(
            child: grouped
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [lead, SizedBox(height: S.s2), child])
                : child,
          ),
          if (t != null) ...[
            SizedBox(width: S.of(10)),
            Text(_short(t),
                style: TS.meta(AppColors.fg3).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ]),
      ),
    );
  }
}

/// The clock for today, else the weekday within a week, else the date.
String _short(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  if (days == 0) return _clock(t);
  if (days < 7) return _weekdays[t.weekday - 1];
  return '${t.day} ${_months[t.month - 1]}';
}

Future<void> _showRecord(
  BuildContext context, {
  required String title,
  required String meta,
  required String text,
  String? heading,
  List<Widget> extra = const [],
  List<(String, VoidCallback)> actions = const [],
}) {
  Widget body(VoidCallback dismiss) => _recordBody(
      meta: meta,
      text: text,
      heading: heading,
      extra: extra,
      actions: actions,
      dismiss: dismiss);
  if (!kMobile) {
    // Already in the right panel: a page of the panel's own navigator.
    if (ShellPanelRoot.inPanel(context)) {
      return Navigator.of(context).push<void>(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (page, _, __) => _RecordDetailPage(
            title: title, child: body(() => Navigator.of(page).pop())),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: child),
      ));
    }
    final host = ShellPanelScope.maybeOf(context);
    if (host != null) {
      return host
          .open(ShellPanelRequest(
            purpose: ShellPanelPurpose.generic,
            id: 'record:$title:$meta',
            client: DaemonScope.maybeOf(context) ?? host.client,
            sessionId: host.sessionId,
            title: title,
            builder: (_, close) => SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(S.of(14), S.of(10), S.of(14), S.s16),
                child: body(close)),
          ))
          .then((_) {});
    }
  }
  return showAppSheet<void>(context,
      title: title,
      maxWidth: 620,
      maxHeight: 680,
      child: body(() => Navigator.of(context).pop()));
}

Widget _recordBody({
  required String meta,
  required String text,
  String? heading,
  List<Widget> extra = const [],
  List<(String, VoidCallback)> actions = const [],
  required VoidCallback dismiss,
}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(meta, style: sans(_meta, color: AppColors.fg3)),
        SizedBox(height: S.of(10)),
        if (heading != null && heading.isNotEmpty) ...[
          Text(heading,
              style: sans(_title,
                  weight: W.label, color: AppColors.fg1, height: 1.35)),
          SizedBox(height: S.s8),
        ],
        if (text.trim().isNotEmpty)
          CardMarkdownBody(body: text, collapsible: false),
        ...extra,
        if (actions.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: S.s8),
            child: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              for (final (label, run) in actions)
                TextButton(
                  onPressed: () {
                    dismiss();
                    run();
                  },
                  child:
                      Text(label, style: sans(_body, color: AppColors.accent)),
                ),
            ]),
          ),
      ],
    );

class _RecordDetailPage extends StatelessWidget {
  const _RecordDetailPage({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.paneBg,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: S.s6),
            child: Row(children: [
              IconBtn('arrow-left',
                  size: 28,
                  iconSize: 15,
                  tooltip: 'Back',
                  onTap: () => Navigator.of(context).maybePop()),
              SizedBox(width: S.s4),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, weight: W.label, color: AppColors.fg1)),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(S.of(14), S.s4, S.of(14), S.s16),
                child: child),
          ),
        ]),
      );
}

String _fullTime(String raw) {
  final t = _time(raw);
  return t == null ? '' : '${_dayLabel(t)}, ${_clock(t)}';
}

void _openSession(
    BuildContext context, DaemonClient client, String id, String title) {
  final tab = openSessionInTab;
  if (!kMobile && tab != null) {
    tab(client, id, title);
    return;
  }
  presentScreen(context,
      builder: (_, close) => SessionScreen(
          client: client, sessionId: id, title: title, onMenu: close));
}

/// Everything that has reached an agent: task offers, direct messages from
/// people and other agents, and task room posts that name it.
class AgentInboxView extends StatefulWidget {
  const AgentInboxView(
      {super.key,
      required this.client,
      required this.agentId,
      required this.agentName,
      this.filter,
      this.filterChips = true});

  final String? filter;
  final bool filterChips;
  final DaemonClient client;
  final String agentId;
  final String agentName;

  @override
  State<AgentInboxView> createState() => _AgentInboxViewState();
}

class _AgentInboxViewState extends State<AgentInboxView> {
  Map<String, String> _names = const {};
  int? _seenUpTo;
  int _newest = 0;
  int? _selectedId;
  final _opened = <int>{};

  String get _seenKey => 'inbox_seen_${widget.agentId}';

  @override
  void dispose() {
    if (_newest > 0) {
      SharedPreferences.getInstance()
          .then((p) => p.setInt(_seenKey, _newest))
          .catchError((_) => false);
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _seenUpTo = p.getInt(_seenKey) ?? 0);
    }).catchError((_) {});
    widget.client.coordinationAgents().then((agents) {
      if (!mounted) return;
      setState(() => _names = {
            for (final a in agents)
              if (a.displayName.trim().isNotEmpty) a.id: a.displayName.trim(),
          });
    }).catchError((_) {});
  }

  String _sender(InboxEntry e) {
    if (e.fromKind == 'human') return 'You';
    if (e.fromId == widget.agentId) {
      final to = e.toId;
      return to == null || to == widget.agentId
          ? 'Its own session'
          : 'Sent to ${_names[to] ?? to}';
    }
    return _names[e.fromId] ?? e.fromId;
  }

  (String, Color)? _tag(InboxEntry e) {
    if (e.postKind == 'blocker' || e.postKind == 'interrupt') {
      return (e.postKind == 'blocker' ? 'Blocker' : 'Urgent', AppColors.danger);
    }
    if (e.postKind == 'question') return ('Question', AppColors.accent);
    if (e.source == 'offer') return ('Task offer', AppColors.accent);
    if (e.source == 'room') return ('Task room', AppColors.fg3);
    final envelope = e.envelope;
    if (envelope == null) return null;
    final words = envelope.replaceAll('_', ' ');
    return (words[0].toUpperCase() + words.substring(1), AppColors.fg3);
  }

  bool _unread(InboxEntry e) =>
      _seenUpTo != null &&
      _seenUpTo! > 0 &&
      e.id > _seenUpTo! &&
      !_opened.contains(e.id) &&
      e.fromKind != 'human';

  Future<void> _open(InboxEntry e) async {
    final task = e.taskId;
    setState(() {
      _opened.add(e.id);
      _selectedId = e.id;
    });
    await _showRecord(
      context,
      title: _sender(e),
      meta: [_tag(e)?.$1, _fullTime(e.createdAt)].nonNulls.join(' · '),
      heading: e.title,
      text: e.text,
      actions: [
        if (task != null && task.isNotEmpty)
          ('Open task', () => openTaskDetail(context, widget.client, task)),
      ],
    );
    if (mounted) setState(() => _selectedId = null);
  }

  Widget _row(InboxEntry e) {
    final tag = _tag(e);
    final title = e.title;
    final preview = _plain(e.text);
    if (e.id > _newest) _newest = e.id;
    final unread = _unread(e);
    return _RecordRow(
      time: e.createdAt,
      unread: unread,
      selected: _selectedId == e.id,
      onTap: () => _open(e),
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(_sender(e),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: unread
                  ? TS.rowTitle(AppColors.fg1)
                  : TS.rowTitle(AppColors.fg2).copyWith(fontWeight: W.body)),
        ),
        if (tag != null) ...[
          SizedBox(width: S.s8),
          _StateTag(tag.$1, tag.$2),
        ],
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null && title.isNotEmpty)
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TS.ui(AppColors.fg2)),
        if (preview.isNotEmpty)
          Text(preview,
              maxLines: title == null || title.isEmpty ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: TS.ui(AppColors.fg3)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RecordList<InboxEntry>(
      client: widget.client,
      liveOn: Swr.coordination,
      hint: 'Search everything sent to ${widget.agentName}',
      filters: agentInboxFilters,
      filter: widget.filter,
      filterChips: widget.filterChips,
      load: ({before, query, filter}) => widget.client.agentInbox(
        widget.agentId,
        before: before,
        contains: query,
        kind: filter,
        limit: _pageSize,
      ),
      idOf: (e) => e.id,
      timeOf: (e) => e.createdAt,
      row: _row,
      empty: 'Nothing has reached ${widget.agentName} yet.',
    );
  }
}

/// An agent's work log: what it dispatched, what came back, its notes and the
/// progress its sessions reported.
class AgentBoardView extends StatefulWidget {
  const AgentBoardView(
      {super.key,
      required this.client,
      required this.agentId,
      required this.agentName,
      this.filter,
      this.filterChips = true});

  final String? filter;
  final bool filterChips;
  final DaemonClient client;
  final String agentId;
  final String agentName;

  @override
  State<AgentBoardView> createState() => _AgentBoardViewState();
}

class _AgentBoardViewState extends State<AgentBoardView> {
  static const _automatic = 'Automatic, the session wrote no report: ';

  Set<String> _awaiting = const {};
  final Map<String, BoardEntry> _reports = {};
  bool _groupedByFolder = false;

  Future<List<BoardEntry>> _load(
      {int? before, String? query, String? filter}) async {
    _groupedByFolder = filter == 'by-folder';
    final group = switch (filter) {
      'by-task' => 'task',
      'by-folder' => 'folder',
      _ => null,
    };
    final page = await widget.client.agentBoardPage(
      widget.agentId,
      before: before,
      contains: query,
      kind: filter == 'waiting' || group != null ? null : filter,
      outstanding: filter == 'waiting',
      limit: _pageSize,
      group: group,
    );
    if (mounted) {
      setState(() {
        _awaiting = page.awaiting.toSet();
        for (final e in page.entries) {
          final id = e.correlationId;
          if (e.kind == 'reported' && id != null) _reports[id] = e;
        }
      });
    }
    return page.entries;
  }

  (String, String, Color, bool) _look(BoardEntry e) => switch (e.kind) {
        'dispatched' => ('send', 'Dispatched', AppColors.fg2, true),
        'reported' => ('check-circle', 'Reported', AppColors.ok, false),
        'progress' => (
            'activity',
            e.summary.startsWith(_automatic)
                ? 'Progress, automatic'
                : 'Progress',
            AppColors.accent,
            false
          ),
        'noted' => ('file-text', 'Noted', AppColors.fg2, true),
        _ => ('file-text', e.kind, AppColors.fg2, true),
      };

  /// The summary without what the row already says: the automatic prefix, and
  /// the task id that dispatch and report rows lead with.
  String _summary(BoardEntry e) {
    var text = e.summary.startsWith(_automatic)
        ? e.summary.substring(_automatic.length)
        : e.summary;
    final id = e.correlationId;
    if (id != null && text.startsWith(id)) {
      text =
          text.substring(id.length).replaceFirst(RegExp(r'^\s*[—:-]\s*'), '');
      if (text.isNotEmpty) text = text[0].toUpperCase() + text.substring(1);
    }
    return text;
  }

  bool _waiting(BoardEntry e) =>
      e.kind == 'dispatched' && _awaiting.contains(e.correlationId);

  void _open(BoardEntry e) {
    final look = _look(e);
    final session = e.sessionId;
    final folder = e.workspace;
    final report = e.kind == 'dispatched' ? _reports[e.correlationId] : null;
    _showRecord(
      context,
      title: look.$2,
      meta: [
        _fullTime(e.createdAt),
        if (folder != null) _folder(folder),
      ].join(' · '),
      text: _summary(e),
      extra: [
        if (report != null) ...[
          SizedBox(height: S.s16),
          Text('Reported back, ${_fullTime(report.createdAt)}',
              style: sans(_meta, weight: W.label, color: AppColors.ok)),
          SizedBox(height: S.s4),
          CardMarkdownBody(body: report.summary, collapsible: false),
        ],
        if (_waiting(e)) ...[
          SizedBox(height: S.s12),
          Text('No report has come back yet.',
              style: sans(_body, color: AppColors.run)),
        ],
      ],
      actions: [
        if (session != null)
          (
            'Open session',
            () =>
                _openSession(context, widget.client, session, widget.agentName)
          ),
      ],
    );
  }

  void _openGroup(BoardEntry e, {required bool byFolder}) {
    final folder = e.folder ?? e.workspace;
    final task = e.correlationId;
    final Future<List<BoardEntry>>? rows = byFolder
        ? (folder == null
            ? null
            : widget.client
                .agentBoardPage(widget.agentId, workspace: folder, limit: 100)
                .then((p) => p.entries))
        : (task == null
            ? null
            : widget.client
                .agentBoardPage(widget.agentId, correlationId: task, limit: 100)
                .then((p) => p.entries));
    if (rows == null) {
      _open(e);
      return;
    }
    _showRecord(
      context,
      title: byFolder ? _folder(folder!) : (e.taskTitle ?? 'Task'),
      meta: '${e.groupCount} entries'
          '${e.taskStatus == null ? '' : ' · ${e.taskStatus!.replaceAll('_', ' ')}'}',
      text: '',
      extra: [
        FutureBuilder<List<BoardEntry>>(
          future: rows,
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) {
              return Text(
                  snap.hasError ? 'Could not load this log.' : 'Loading',
                  style: sans(_body, color: AppColors.fg3));
            }
            return BoardLog(entries: data);
          },
        ),
      ],
    );
  }

  Widget _groupRow(BoardEntry e, {required bool byFolder}) {
    final folder = e.folder ?? e.workspace;
    final String title = byFolder
        ? (folder == null ? 'No folder' : _folder(folder))
        : (e.taskTitle ??
            (e.correlationId == null ? 'Not on a task' : 'Earlier work'));
    final status = e.taskStatus?.replaceAll('_', ' ');
    final count = e.groupCount ?? 1;
    return _BoardRow(
      time: e.createdAt,
      onTap: () => _openGroup(e, byFolder: byFolder),
      lead: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(byFolder ? 'folder' : 'file-text',
            size: kMobile ? 15 : 13, color: AppColors.fg2),
        SizedBox(width: S.s6),
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(_body, weight: W.label, color: AppColors.fg1)),
        ),
        SizedBox(width: S.s8),
        Text(
            [
              '$count',
              if (!byFolder && status != null) status,
            ].join(' · '),
            maxLines: 1,
            style: sans(_meta, color: AppColors.fg3)),
      ]),
      child: Text(_plain(_summary(e)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: sans(_body, color: AppColors.fg2, height: 1.4)),
    );
  }

  Widget _row(BoardEntry e) {
    if (e.groupCount != null) {
      return _groupRow(e, byFolder: _groupedByFolder);
    }
    final look = _look(e);
    final folder = e.workspace;
    return _BoardRow(
      time: e.createdAt,
      onTap: () => _open(e),
      lead: _StateTag(look.$2, look.$3, neutral: look.$4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_plain(_summary(e)),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: sans(_body, color: AppColors.fg1, height: 1.4)),
        if (folder != null)
          Padding(
            padding: EdgeInsets.only(top: S.s2),
            child: Text(_folder(folder),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(_meta, color: AppColors.fg3)),
          ),
        if (_waiting(e))
          Padding(
            padding: EdgeInsets.only(top: S.of(5)),
            child: _WaitingTag(),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RecordList<BoardEntry>(
      client: widget.client,
      liveOn: (e) => e['kind'] == 'agent_board' && e['agent'] == widget.agentId,
      hint: "Search ${widget.agentName}'s work",
      groupedFilters: const {'by-task', 'by-folder'},
      filters: agentBoardFilters,
      card: true,
      filter: widget.filter,
      filterChips: widget.filterChips,
      load: _load,
      idOf: (e) => e.id,
      timeOf: (e) => e.createdAt,
      row: _row,
      empty: 'No work recorded for ${widget.agentName} yet.',
    );
  }
}

/// A running log, newest first. Automatic entries only show when nothing was
/// written, since they say little beside what the agent recorded itself.
class BoardLog extends StatelessWidget {
  const BoardLog({super.key, required this.entries, this.showAgent = false});

  static const _automatic = 'Automatic, the session wrote no report: ';

  final List<BoardEntry> entries;
  final bool showAgent;

  String _text(BoardEntry e) {
    var text = e.summary.startsWith(_automatic)
        ? e.summary.substring(_automatic.length)
        : e.summary;
    final id = e.correlationId;
    if (id != null && text.startsWith(id)) {
      text =
          text.substring(id.length).replaceFirst(RegExp(r'^\s*[—:-]\s*'), '');
      if (text.isNotEmpty) text = text[0].toUpperCase() + text.substring(1);
    }
    return text.replaceAllMapped(
        RegExp(r'\n(Why|Learned): '), (m) => '\n\n**${m[1]}:** ');
  }

  @override
  Widget build(BuildContext context) {
    final written =
        entries.where((e) => !e.summary.startsWith(_automatic)).toList();
    final rows = written.isEmpty ? entries : written;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in rows)
          Padding(
            padding: EdgeInsets.symmetric(vertical: S.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    [
                      _fullTime(e.createdAt),
                      if (showAgent) e.agentId,
                      if (e.kind != 'progress') e.kind,
                    ].join(' · '),
                    style: sans(_meta, color: AppColors.fg3)),
                SizedBox(height: S.s2),
                CardMarkdownBody(body: _text(e), collapsible: false),
              ],
            ),
          ),
      ],
    );
  }
}

class _WaitingTag extends StatelessWidget {
  const _WaitingTag();

  @override
  Widget build(BuildContext context) =>
      _StateTag('Waiting for report', AppColors.run);
}
