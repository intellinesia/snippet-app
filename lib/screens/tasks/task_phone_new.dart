import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../mochi.dart' show AgentMochi;
import '../../models.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../morph_sheet.dart' show SheetSize;
import '../../widgets.dart';
import '../../mobile_kit.dart';

/// TK-03: the phone New task sheet (medium). Title, briefing, Owner and
/// Priority rows and a pinned Create task. Returns true when a task was filed.
Future<bool> showNewTaskSheet(BuildContext context, DaemonClient client) async {
  final ctrl = NewTaskController(client);
  final created = await showAppSheet<bool>(
    context,
    title: 'New task',
    size: SheetSize.medium,
    child: NewTaskBody(ctrl: ctrl),
    pinned: NewTaskPinned(ctrl: ctrl, onDone: (c) => Navigator.of(c).pop(true)),
  );
  final t = ctrl.created;
  ctrl.dispose();
  if (created == true && context.mounted) {
    toast(context, ctrl.fellBack ? 'Sent to Lead' : 'Task added',
        actionLabel: t == null ? null : 'Undo',
        onAction: t == null
            ? null
            : () => unawaited(client
                .setTaskStatus(t.id, TaskStatus.cancelled)
                .then<void>((_) {}, onError: (_) {})));
  }
  return created == true;
}

class NewTaskController extends ChangeNotifier {
  NewTaskController(this.client) {
    title.addListener(notifyListeners);
    unawaited(_load());
  }
  final DaemonClient client;
  final title = TextEditingController();
  final brief = TextEditingController();
  List<CoordinationAgent> agents = const [];
  List<SessionInfo> sessions = const [];
  String? agentId;
  int priority = 1;
  bool busy = false;
  bool fellBack = false;
  String? error;
  TaskItem? created;
  bool _disposed = false;

  bool get canCreate => title.text.trim().isNotEmpty && !busy;

  String get ownerLabel {
    final a = agents.where((a) => a.id == agentId).firstOrNull;
    return a == null ? 'Lead picks' : _name(a);
  }

  static String _name(CoordinationAgent a) =>
      a.displayName.trim().isEmpty ? a.id : a.displayName.trim();

  String agentName(CoordinationAgent a) => _name(a);

  static const priorities = ['Low', 'Medium', 'High'];
  String get priorityLabel => priorities[priority];

  Future<void> _load() async {
    try {
      final all = await client.coordinationAgents();
      agents = [
        for (final a in all)
          if (!a.isLead) a
      ];
      if (!_disposed) notifyListeners();
    } catch (_) {}
    try {
      sessions = await client.sessions();
    } catch (_) {}
  }

  void setOwner(String? id) {
    agentId = id;
    notifyListeners();
  }

  void setPriority(int p) {
    priority = p;
    notifyListeners();
  }

  /// The session the chosen agent works in; Lead's for "Lead picks".
  String? _session() {
    final want = agentId ?? 'lead';
    for (final s in sessions) {
      if (s.agentId == want) return s.id;
    }
    return null;
  }

  /// Files the task; true on success.
  Future<bool> submit() async {
    final text = title.text.trim();
    if (text.isEmpty || busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final session = _session();
      if (session != null) {
        created = await client.createTask(
            title: text,
            description: brief.text.trim(),
            sessionId: session,
            priority: priority);
      } else {
        // No session to route to: Lead files it and picks one.
        final agent = agents.where((a) => a.id == agentId).firstOrNull;
        final briefing = brief.text.trim();
        await client.sendAgentMessage(
          toAgentId: 'lead',
          body: [
            'New task from the Tasks board. File it, then pick or start the '
                'session it should run in and offer it to the agent.',
            '',
            'Title: $text',
            'Agent: ${agent == null ? 'your call' : '${_name(agent)} (${agent.id})'}',
            'Priority: $priorityLabel',
            if (briefing.isNotEmpty) ...['', 'Briefing:', briefing],
          ].join('\n'),
          idempotencyKey: 'new-task-${text.hashCode}-${DateTime.now().minute}',
        );
        fellBack = true;
      }
      return true;
    } catch (_) {
      error = "Couldn't create the task. Try again.";
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    title.dispose();
    brief.dispose();
    super.dispose();
  }
}

class NewTaskBody extends StatelessWidget {
  const NewTaskBody({super.key, required this.ctrl});
  final NewTaskController ctrl;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) =>
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(16)),
            child: TextField(
              key: const ValueKey('new-task-title'),
              controller: ctrl.title,
              textInputAction: TextInputAction.next,
              cursorColor: AppColors.fg1,
              style: sans(16, weight: W.label, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Task title',
                hintStyle: sans(16, color: AppColors.fg4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(MK.groupRadius)),
            child: TextField(
              key: const ValueKey('new-task-brief'),
              controller: ctrl.brief,
              minLines: 3,
              maxLines: 6,
              cursorColor: AppColors.fg1,
              style: sans(15.5, height: 1.45, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText:
                    'Goal, what done looks like, and the context it needs.',
                hintStyle: sans(15.5, height: 1.45, color: AppColors.fg4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _OptionGroup(children: [
            Builder(
              builder: (a) => _OptionRow(
                key: const ValueKey('row-owner'),
                label: 'Owner',
                value: ctrl.ownerLabel,
                onTap: () async {
                  final picked = await showAppMenu<String>(context,
                      anchor: a,
                      below: true,
                      alignEnd: true,
                      title: 'Owner',
                      items: [
                        appMenuItem(
                            value: '',
                            label: 'Lead picks',
                            leading: const AgentMochi('lead', size: 28),
                            selected: ctrl.agentId == null),
                        for (final g in ctrl.agents)
                          appMenuItem(
                              value: g.id,
                              label: ctrl.agentName(g),
                              leading: AgentMochi(g.id, size: 28),
                              selected: ctrl.agentId == g.id),
                      ]);
                  if (picked != null) {
                    ctrl.setOwner(picked.isEmpty ? null : picked);
                  }
                },
              ),
            ),
            Builder(
              builder: (a) => _OptionRow(
                key: const ValueKey('row-priority'),
                label: 'Priority',
                value: ctrl.priorityLabel,
                onTap: () async {
                  final picked = await showAppMenu<int>(context,
                      anchor: a,
                      below: true,
                      alignEnd: true,
                      title: 'Priority',
                      items: [
                        for (var i = 0; i < 3; i++)
                          appMenuItem(
                              value: i,
                              icon: const ['arrow-down', 'minus', 'chevron-up'][i],
                              label: NewTaskController.priorities[i],
                              selected: ctrl.priority == i),
                      ]);
                  if (picked != null) ctrl.setPriority(picked);
                },
              ),
            ),
          ]),
        ]),
      );
}

/// Owner and Priority as one surface: inset group with a hairline on
/// iPhone, segmented tiles on Android.
class _OptionGroup extends StatelessWidget {
  const _OptionGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final n = children.length;
    if (kAndroidLook) {
      return Column(children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(i == 0 ? 20 : 4),
              bottom: Radius.circular(i == n - 1 ? 20 : 4),
            ),
            child: ColoredBox(color: AppColors.surface3, child: children[i]),
          ),
        ]
      ]);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(MK.groupRadius),
      child: ColoredBox(
        color: AppColors.surface3,
        child: Column(children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Container(height: 0.5, color: MK.hairline),
              ),
            children[i],
          ]
        ]),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow(
      {super.key,
      required this.label,
      required this.value,
      required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label, $value',
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text(label, style: sans(15.5, color: AppColors.fg1)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(value,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14.5, color: AppColors.fg3)),
                ),
                const SizedBox(width: 6),
                AppIcon(kAndroidLook ? 'chevron-down' : 'chevron-right',
                    size: 14, color: AppColors.fg4),
              ]),
            ),
          ),
        ),
      );
}

/// The pinned Create task button with its error line above.
class NewTaskPinned extends StatelessWidget {
  const NewTaskPinned({super.key, required this.ctrl, required this.onDone});
  final NewTaskController ctrl;
  final void Function(BuildContext context) onDone;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final on = ctrl.canCreate;
          final label = ctrl.busy ? 'Creating' : 'Create task';
          final h = MK.bigButton;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            if (ctrl.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(ctrl.error!, style: sans(12, color: AppColors.fg2)),
              ),
            Semantics(
              button: true,
              enabled: on,
              label: label,
              excludeSemantics: true,
              child: TapDetector(
                key: const ValueKey('create-task'),
                behavior: HitTestBehavior.opaque,
                onTap: !on
                    ? null
                    : () async {
                        final ok = await ctrl.submit();
                        if (ok && context.mounted) onDone(context);
                      },
                child: Container(
                  height: h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: on ? AppColors.fg1 : AppColors.surface3,
                      borderRadius: BorderRadius.circular(h / 2)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (ctrl.busy) ...[
                      MkMorph(size: 16, color: AppColors.fg2),
                      const SizedBox(width: 8),
                    ],
                    Text(label,
                        style: sans(16,
                            weight: kAndroidLook ? W.label : FontWeight.w600,
                            color: on ? AppColors.bg : AppColors.fg3)),
                  ]),
                ),
              ),
            ),
          ]);
        },
      );
}
