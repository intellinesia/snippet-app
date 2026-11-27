import 'package:flutter/material.dart';

import '../../api.dart';
import '../../mobile_kit.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../phone_agent_page.dart' show shortPath;
import '../shell_nav.dart' show sessionBusy;
import '../tasks/task_phone_list.dart' show PhoneTaskCard;
import 'sessions_list_phone.dart' show SessionRowPhone;

/// Agent context (HM-06): Overview, Files, Tasks and Memory behind the kit's
/// filter group. Files are the folders the agent's sessions work in.
class AgentContextPage extends StatefulWidget {
  const AgentContextPage({
    super.key,
    required this.client,
    required this.agent,
    required this.sessions,
    this.initialTab = 0,
    this.onOpenSession,
  });
  final DaemonClient client;
  final CoordinationAgent agent;
  final List<SessionInfo> sessions;
  final int initialTab;
  final void Function(SessionInfo s)? onOpenSession;

  @override
  State<AgentContextPage> createState() => _AgentContextPageState();
}

class _AgentContextPageState extends State<AgentContextPage> {
  late int _tab = widget.initialTab;
  List<TaskItem>? _tasks;
  List<MemoryScope> _memory = const [];
  List<String> _wakes = const [];

  @override
  void initState() {
    super.initState();
    final c = widget.client, id = widget.agent.id;
    c.tasks(agentId: id).then((t) {
      if (mounted) setState(() => _tasks = t);
    }).catchError((_) {});
    c.memoryScopes().then((m) {
      if (mounted) {
        setState(() => _memory = [
              for (final x in m)
                if (x.key.contains(id)) x
            ]);
      }
    }).catchError((_) {});
    c.wakes().then((l) {
      if (mounted) {
        setState(() => _wakes = [
              for (final w in l.wakes)
                if (w.owner == id && w.enabled) w.scheduleText
            ]);
      }
    }).catchError((_) {});
  }

  List<SessionInfo> get _mine => [
        for (final s in widget.sessions)
          if (s.displayAgentId == widget.agent.id) s
      ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));

  Set<String> get _folders => {
        for (final s in _mine)
          if (s.projectFolder.trim().isNotEmpty) s.projectFolder.trim()
      };

  Widget _sessionRows(List<SessionInfo> l) => MkList(children: [
        for (var i = 0; i < l.length; i++)
          SessionRowPhone(
              session: l[i],
              last: i == l.length - 1,
              onTap: () => widget.onOpenSession?.call(l[i])),
      ]);

  Widget _folderRows(Iterable<String> l) => MkList(children: [
        for (final f in l)
          MkRow(
              title: shortPath(f),
              leading: AppIcon('folder', size: 22, color: AppColors.fg2),
              divider: f != l.last),
      ]);

  Widget _note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Text(text, style: sans(14, color: AppColors.fg3)));

  List<Widget> _overview() {
    final active = [
      for (final s in _mine)
        if (!s.settled && sessionBusy(s)) s
    ];
    final folders = _folders.take(4);
    return [
      if (active.isNotEmpty) ...[
        const MkSection('In progress'),
        _sessionRows(active),
      ],
      if (folders.isNotEmpty) ...[
        const MkSection('Files'),
        _folderRows(folders),
      ],
      if (_wakes.isNotEmpty) ...[
        const MkSection('Wakes'),
        MkList(children: [
          for (final w in _wakes)
            MkRow(
                title: w,
                leading: AppIcon('clock', size: 22, color: AppColors.fg2),
                divider: w != _wakes.last),
        ]),
      ],
      if (active.isEmpty && folders.isEmpty && _wakes.isEmpty)
        _note('Nothing happening'),
    ];
  }

  List<Widget> _body() {
    switch (_tab) {
      case 1:
        final f = _folders;
        return [f.isEmpty ? _note('No files yet') : _folderRows(f)];
      case 2:
        final t = _tasks;
        if (t == null || t.isEmpty) {
          return [_note(t == null ? 'Loading' : 'No tasks yet')];
        }
        return [
          MkList(children: [
            for (var i = 0; i < t.length; i++)
              PhoneTaskCard(
                  task: t[i],
                  owner: null,
                  last: i == t.length - 1,
                  onTap: () {}),
          ]),
        ];
      case 3:
        if (_memory.isEmpty) return [_note('No memory yet')];
        return [
          MkList(children: [
            for (final m in _memory)
              MkRow(
                  title: m.label.isEmpty ? m.key : m.label,
                  leading: AppIcon('book', size: 22, color: AppColors.fg2),
                  subtitle:
                      '${m.entries} ${m.entries == 1 ? 'entry' : 'entries'}',
                  divider: m != _memory.last),
          ]),
        ];
      default:
        return _overview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _tasks
            ?.where((x) =>
                x.status != TaskStatus.done && x.status != TaskStatus.cancelled)
            .length ??
        0;
    return Material(
      color: AppColors.bg,
      child: MkPage(
        title: widget.agent.shortName,
        onBack: () => Navigator.of(context).pop(),
        bottomClearance: false,
        filters: MkFilterGroup<int>(
          selected: _tab,
          onSelect: (i) => setState(() => _tab = i),
          options: [
            const MkFilter(0, 'Overview'),
            const MkFilter(1, 'Files'),
            MkFilter(2, 'Tasks', count: open > 0 ? open : null),
            MkFilter(3, 'Memory',
                count: _memory.isNotEmpty ? _memory.length : null),
          ],
        ),
        slivers: [
          SliverList(delegate: SliverChildListDelegate(_body())),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
