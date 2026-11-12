import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/agent_details.dart';
import '../models.dart';
import '../shell_panel.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_appearance.dart';
import 'agent_profile_panel.dart';
import 'agent_reach_panel.dart';
import 'agent_records.dart';
import 'agent_wake_panel.dart';
import 'memory_screen.dart';
import 'shell_models.dart' show RightTab;

/// The agent actions that open as right-panel tabs. `desk` opens a session tab
/// and `delete` a confirm.
const agentPanelPages = ['inbox', 'board', 'memory', 'wakes', 'reach', 'model'];

String _pageTitle(String action) => switch (action) {
      'inbox' => 'Inbox',
      'board' => 'Board',
      'memory' => 'Memory',
      'wakes' => 'Wakes',
      'reach' => 'How it reaches you',
      'model' => 'Inference profile',
      'nickname' => 'Nickname',
      _ => 'Appearance',
    };

/// One agent action as a right-panel page. Each page loads the agent record
/// itself, so it is never stale when reopened.
ShellPanelRequest agentPanelRequest(
  String action, {
  required DaemonClient client,
  required String agentId,
  required String agentName,
  AgentDetailsTab initialTab = AgentDetailsTab.info,
  VoidCallback? onCall,
  VoidCallback? onDeleted,
}) {
  if (action == 'details') {
    return ShellPanelRequest(
      purpose: ShellPanelPurpose.agent,
      id: agentId,
      client: client,
      title: agentName,
      builder: (_, close) => AgentDetails(
        client: client,
        agentId: agentId,
        agentName: agentName,
        initialTab: initialTab,
        onCall: onCall,
        onClose: close,
        onDeleted: onDeleted,
      ),
    );
  }
  return ShellPanelRequest(
      purpose: ShellPanelPurpose.agent,
      id: '$agentId:$action',
      client: client,
      title: _pageTitle(action),
      builder: (_, close) => switch (action) {
        'inbox' => agentRecordsBody(client, agentId, agentName, board: false),
        'board' => agentRecordsBody(client, agentId, agentName, board: true),
        'memory' => MemoryScreen(
            client: client,
            embedded: true,
            onBack: close,
            hideBack: true,
            initialKey: 'agent:$agentId'),
        'wakes' => _WithAgent(
            client: client,
            agentId: agentId,
            builder: (a) => SingleChildScrollView(
                padding: const EdgeInsets.all(S.s12),
                child: AgentWakePanel(
                    client: client, owner: agentId, name: agentName)),
          ),
        'reach' => SingleChildScrollView(
            padding: const EdgeInsets.all(S.s12),
            child: AgentReachPanel(client: client, agentId: agentId)),
        'model' => _WithAgent(
            client: client,
            agentId: agentId,
            builder: (a) => SingleChildScrollView(
                padding: const EdgeInsets.all(S.s12),
                child: AgentProfilePanel(
                    client: client, agent: a, name: agentName)),
          ),
        'nickname' => _WithAgent(
            client: client,
            agentId: agentId,
            builder: (a) =>
                _NicknamePage(client: client, agent: a, onDone: close),
          ),
        _ => SingleChildScrollView(
            padding: const EdgeInsets.all(S.s8),
            child: Align(
              alignment: Alignment.topLeft,
              child: AgentAppearancePicker(
                  client: client, agentId: agentId, onDone: close),
            ),
          ),
      },
    );
}

ShellPanelRequest groupDetailsPanelRequest({
  required DaemonClient client,
  required GroupSummary group,
  ValueChanged<GroupSummary>? onChanged,
  VoidCallback? onDeleted,
}) =>
    ShellPanelRequest(
      purpose: ShellPanelPurpose.agent,
      id: 'group:${group.id}',
      client: client,
      title: group.title.trim().isEmpty ? 'Group' : group.title.trim(),
      builder: (_, close) => AgentDetails(
        client: client,
        group: group,
        onClose: close,
        onGroupChanged: onChanged,
        onGroupDeleted: onDeleted,
      ),
    );

class _WithAgent extends StatefulWidget {
  const _WithAgent(
      {required this.client, required this.agentId, required this.builder});
  final DaemonClient client;
  final String agentId;
  final Widget Function(CoordinationAgent agent) builder;

  @override
  State<_WithAgent> createState() => _WithAgentState();
}

class _WithAgentState extends State<_WithAgent> {
  CoordinationAgent? _agent;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((all) {
      if (!mounted) return;
      final a = all.where((x) => x.id == widget.agentId).firstOrNull;
      setState(() {
        _agent = a;
        _failed = a == null;
      });
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _agent;
    if (a != null) return widget.builder(a);
    if (_failed) {
      return Center(
          child: Text("Couldn't load this agent", style: TS.ui(AppColors.fg3)));
    }
    return Center(child: DelayedSpinner(size: 16));
  }
}

class _NicknamePage extends StatefulWidget {
  const _NicknamePage(
      {required this.client, required this.agent, required this.onDone});
  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback onDone;

  @override
  State<_NicknamePage> createState() => _NicknamePageState();
}

class _NicknamePageState extends State<_NicknamePage> {
  late final _text = TextEditingController(text: widget.agent.nickname ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = _text.text.trim();
    if (next == (widget.agent.nickname ?? '')) return widget.onDone();
    setState(() => _saving = true);
    try {
      await widget.client
          .setAgentNickname(widget.agent.id, next.isEmpty ? null : next);
      if (mounted) widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.agent.fullName.trim().isEmpty
        ? widget.agent.id
        : widget.agent.fullName.trim();
    return Padding(
      padding: const EdgeInsets.all(S.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nickname for $full',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TS.ui(AppColors.fg2)),
          const SizedBox(height: S.s8),
          TextField(
            controller: _text,
            autofocus: true,
            style: TS.body(AppColors.fg1),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: 'Leave empty to use the name',
              hintStyle: TS.body(AppColors.fg4),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border)),
            ),
          ),
          const SizedBox(height: S.s12),
          Align(
            alignment: Alignment.centerRight,
            child: Btn('Save', small: true, disabled: _saving, onTap: _save),
          ),
        ],
      ),
    );
  }
}

/// The desktop right panel of an agent tab: one closable tab per page opened
/// from the agent's Actions menu ([readouts], scoped to this tab).
class AgentSidePanel extends StatelessWidget {
  const AgentSidePanel({
    super.key,
    required this.client,
    required this.agentId,
    required this.agentName,
    required this.onAction,
    this.readouts = const [],
    this.activeReadout,
    this.readoutBody,
    this.onSelectReadout,
    this.onCloseReadout,
    this.onClearReadout,
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;
  final ValueChanged<String> onAction;
  final List<RightTab> readouts;
  final String? activeReadout;
  final Widget Function(RightTab readout)? readoutBody;
  final ValueChanged<RightTab>? onSelectReadout;
  final ValueChanged<RightTab>? onCloseReadout;
  final VoidCallback? onClearReadout;

  RightTab? get _reading =>
      readouts.where((r) => r.key == activeReadout).firstOrNull;

  Widget _seg(String text, bool on, VoidCallback onTap,
      {VoidCallback? onClose}) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: on ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 0, onClose != null ? 6 : 10, 0),
            child: SizedBox(
              height: 28,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(text, style: TS.ui(on ? AppColors.fg1 : AppColors.fg3)),
                if (onClose != null) ...[
                  const SizedBox(width: 5),
                  Tooltip(
                    message: 'Close tab',
                    child: GestureDetector(
                      onTap: onClose,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: AppIcon('x', size: 11, color: AppColors.fg3),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading ?? readouts.lastOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final r in readouts)
                _seg(r.label, r.key == reading?.key,
                    () => onSelectReadout?.call(r),
                    onClose: () => onCloseReadout?.call(r)),
            ]),
          ),
        ),
        Expanded(
          child: reading != null && readoutBody != null
              ? readoutBody!(reading)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
