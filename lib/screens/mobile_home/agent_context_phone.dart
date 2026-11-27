import 'package:flutter/material.dart';

import '../../api.dart';
import '../../tap_detector.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../phone_agent_page.dart' show sessionStateWord, shortPath;
import '../shell_nav.dart' show sessionBusy;
import 'agents_home.dart';

// Cards and segments sit 16 in from the screen edge on the board.
const double _inset = 16;

/// Agent context (HM-06): Overview, Files, Tasks and Memory under a pinned
/// tab row. Files are the folders the agent's sessions work in.
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
        setState(() => _memory = [for (final x in m) if (x.key.contains(id)) x]);
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

  Widget _card(String title, String sub, {VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, 8),
        child: Semantics(
          button: onTap != null,
          label: '$title, $sub',
          excludeSemantics: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              key: const ValueKey('ctx-card'),
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14, weight: FontWeight.w500, color: AppColors.fg1)),
                    if (sub.isNotEmpty)
                      Text(sub, style: sans(12, color: AppColors.fg3)),
                  ]),
            ),
          ),
        ),
      );

  Widget _row(String icon, String name, String meta) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.only(left: 26, right: _inset),
        child: Row(children: [
          AppIcon(icon, size: 20, color: AppColors.fg2),
          const SizedBox(width: 16),
          Expanded(
              child: Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, color: AppColors.fg1))),
          if (meta.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(meta, style: sans(12, color: AppColors.fg3)),
          ],
        ]),
      );

  List<Widget> _overview() {
    final a = widget.agent;
    final active = [for (final s in _mine) if (!s.settled && sessionBusy(s)) s];
    final folders = {
      for (final s in _mine)
        if (s.projectFolder.trim().isNotEmpty) s.projectFolder.trim()
    }.take(4).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(_inset, 14, _inset, 8),
        child: Row(children: [
          agentFace(a.id, 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(18, weight: FontWeight.w500, color: AppColors.fg1)),
              if (a.role.isNotEmpty)
                Text(a.role, style: sans(13, color: AppColors.fg3)),
            ]),
          ),
        ]),
      ),
      if (active.isNotEmpty) ...[
        const HomeLabel('In progress'),
        for (final s in active)
          _card(s.title.isEmpty ? 'Untitled session' : s.title,
              '${sessionStateWord(s)} · ${relativeTime(s.lastActive)}',
              onTap: () => widget.onOpenSession?.call(s)),
      ],
      if (folders.isNotEmpty) ...[
        const HomeLabel('Files'),
        for (final f in folders) _row('folder', shortPath(f), ''),
      ],
      if (_wakes.isNotEmpty) ...[
        const HomeLabel('Wakes'),
        for (final w in _wakes) _row('clock', w, ''),
      ],
    ];
  }

  List<Widget> _body() {
    switch (_tab) {
      case 1:
        final folders = {
          for (final s in _mine)
            if (s.projectFolder.trim().isNotEmpty) s.projectFolder.trim()
        };
        return [
          const SizedBox(height: 8),
          if (folders.isEmpty) const _Note('No files yet'),
          for (final f in folders) _row('folder', shortPath(f), ''),
        ];
      case 2:
        final t = _tasks;
        return [
          const SizedBox(height: 12),
          if (t == null || t.isEmpty) _Note(t == null ? 'Loading' : 'No tasks'),
          if (t != null)
            for (final x in t) _card(x.title, x.status.label),
        ];
      case 3:
        return [
          const SizedBox(height: 8),
          if (_memory.isEmpty) const _Note('No memory yet'),
          for (final m in _memory)
            _row('book', m.label.isEmpty ? m.key : m.label,
                '${m.entries} ${m.entries == 1 ? 'entry' : 'entries'}'),
        ];
      default:
        return _overview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.agent;
    final live = _mine.where((s) => !s.settled && sessionBusy(s)).firstOrNull;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          PushedBar(
            title: a.shortName,
            subtitle: live == null
                ? 'Idle'
                : 'Working · ${live.title.isEmpty ? 'Untitled session' : live.title}',
          ),
          SpecTabs(
              labels: const ['Overview', 'Files', 'Tasks', 'Memory'],
              index: _tab,
              onTap: (i) => setState(() => _tab = i)),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.only(bottom: 24), children: _body())),
        ]),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(_inset * 2),
      child: Center(child: Text(text, style: sans(14, color: AppColors.fg3))));
}
