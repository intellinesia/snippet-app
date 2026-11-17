import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../shell_panel.dart';
import '../theme.dart';
import '../widgets.dart';
import '../chat/chat_info.dart' show AgentInfoPanel, AgentPageButton;
import '../platform.dart';
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
      'model' => 'Models and context',
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
}) =>
    ShellPanelRequest(
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
                padding: EdgeInsets.all(S.s12),
                child: AgentWakePanel(
                    client: client, owner: agentId, name: agentName)),
          ),
        'reach' => SingleChildScrollView(
            padding: EdgeInsets.all(S.s12),
            child: AgentReachPanel(client: client, agentId: agentId)),
        'model' => _WithAgent(
            client: client,
            agentId: agentId,
            builder: (a) => SingleChildScrollView(
                padding: EdgeInsets.all(S.s12),
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
            padding: EdgeInsets.all(S.s8),
            child: Align(
              alignment: Alignment.topLeft,
              child: AgentAppearancePicker(
                  client: client, agentId: agentId, onDone: close),
            ),
          ),
      },
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
    final phone = kMobile;
    final fs = phone ? 15.0 : 13.0;
    final radius = BorderRadius.circular(R.of(phone ? 12 : 7));
    OutlineInputBorder edge(Color c) => OutlineInputBorder(
        borderRadius: radius, borderSide: BorderSide(color: c));
    return Padding(
      padding: phone
          ? EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s16)
          : EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6),
            child: Text('Nickname', style: sans(12, color: AppColors.fg3)),
          ),
          TextField(
            controller: _text,
            autofocus: true,
            style: sans(fs, color: AppColors.fg1),
            cursorColor: AppColors.accent,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: full,
              hintStyle: sans(fs, color: AppColors.fg4),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface1,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: phone ? S.of(14) : S.of(10),
                  vertical: phone ? S.of(13) : S.s8),
              border: edge(AppColors.lineStrong),
              enabledBorder: edge(AppColors.lineStrong),
              focusedBorder: edge(AppColors.accent),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(S.s4, S.s6, S.s4, 0),
            child: Text('What it is called here. Leave empty to use $full.',
                style: sans(12, color: AppColors.fg3)),
          ),
          SizedBox(height: S.s16),
          Align(
            alignment: Alignment.centerRight,
            child: AgentPageButton('Save',
                primary: true, expand: phone, onTap: _saving ? null : _save),
          ),
        ],
      ),
    );
  }
}

/// The desktop right panel of an agent tab: the iMessage-style info page, then
/// one closable tab per page opened from it ([readouts], scoped to this tab).
class AgentSidePanel extends StatelessWidget {
  const AgentSidePanel({
    super.key,
    required this.client,
    this.agent,
    this.onHide,
    required this.agentId,
    required this.agentName,
    required this.onAction,
    this.readouts = const [],
    this.activeReadout,
    this.readoutBody,
    this.onSelectReadout,
    this.onCloseReadout,
    this.onClearReadout,
    this.contextUsed = 0,
    this.contextWindow = 0,
    this.onCompact,
    this.onAutonomy,
    this.onScheduled,
  });

  final int contextUsed;
  final int contextWindow;
  final VoidCallback? onCompact;
  final VoidCallback? onAutonomy;
  final VoidCallback? onScheduled;
  final DaemonClient client;
  final CoordinationAgent? agent;
  final VoidCallback? onHide;
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
      padding: EdgeInsets.only(right: S.s2),
      child: Material(
        color: on ? AppColors.tint2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                S.of(10), 0, onClose != null ? S.s6 : S.of(10), 0),
            child: SizedBox(
              height: 28,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(text, style: TS.ui(on ? AppColors.fg1 : AppColors.fg3)),
                if (onClose != null) ...[
                  SizedBox(width: S.of(5)),
                  Tooltip(
                    message: 'Close tab',
                    child: GestureDetector(
                      onTap: onClose,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(S.s2),
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
    final reading = _reading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (readouts.isNotEmpty)
          Container(
            height: 46,
            padding: EdgeInsets.fromLTRB(S.of(10), 0, S.s8, 0),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _seg('Info', reading == null, () => onClearReadout?.call()),
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
              : AgentInfoPanel(
                  key: ValueKey('agent-info-$agentId'),
                  client: client,
                  agentId: agentId,
                  name: agentName,
                  agent: agent,
                  docked: true,
                  onOpenInbox: () => onAction('inbox'),
                  onOpenBoard: () => onAction('board'),
                  onOpenDesk: () => onAction('desk'),
                  onOpenMemory: () => onAction('memory'),
                  onClose: onHide,
                  contextUsed: contextUsed,
                  contextWindow: contextWindow,
                  onCompact: onCompact,
                  onAutonomy: onAutonomy,
                  onScheduled: onScheduled,
                ),
        ),
      ],
    );
  }
}
