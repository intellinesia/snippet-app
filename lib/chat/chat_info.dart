import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../glass.dart';
import '../models.dart';
import '../mochi.dart';
import '../platform.dart';
import '../motion_routes.dart';
import '../theme.dart';
import '../widgets.dart';
import '../screens/agent_appearance.dart' show showAgentAppearance;
import '../screens/agent_reach_panel.dart' show showAgentReachSettings;
import '../screens/agent_wake_panel.dart' show showAgentWakeSettings;
import '../screens/group_messaging.dart' show confirmDeleteGroup;
import 'agent_cluster.dart';
import '../screens/group_panel.dart';
import '../screens/agent_profile_panel.dart' show showAgentProfileSettings;
import '../desktop_layout.dart' show SettingsHeader;
import '../screens/memory_screen.dart' show MemoryScreen;
import '../screens/agent_panel.dart'
    show
        PanelBar,
        PanelBarButton,
        PanelCard,
        PanelFootnote,
        PanelGroup,
        PanelRadio,
        PanelRow,
        pr;
import '../crew_widgets.dart' show showCrewAgentMenu;
import '../shell_panel.dart' show ShellRequestScope;
import '../screens/tasks/tasks_panel.dart' show TasksPanel, openTaskCountFor;
import '../screens/tasks/task_common.dart' show openTaskDetail;
import 'agent_panel_body.dart';
import '../settings_form.dart'
    show Grouped, SettingsGroup, SettingsHero, SettingsRow;
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Lets rows inside a docked [AgentInfoPanel] push a nested page instead of
/// opening a popover or sheet. Absent everywhere else, so the same rows keep
/// their old behaviour.
class DockedInfoNav extends InheritedWidget {
  const DockedInfoNav({
    super.key,
    required this.push,
    required this.pop,
    this.close,
    required super.child,
  });

  /// Opens [body] as a page titled [title]; [actions] sit at the right of its
  /// header, and [scroll] false hands the body the page height.
  final void Function(String title, WidgetBuilder body,
      {List<Widget> actions, bool scroll}) push;
  final VoidCallback pop;

  /// Closes the whole panel, when it can be closed.
  final VoidCallback? close;

  static DockedInfoNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DockedInfoNav>();

  @override
  bool updateShouldNotify(DockedInfoNav oldWidget) =>
      push != oldWidget.push ||
      pop != oldWidget.pop ||
      close != oldWidget.close;
}

Future<String?> dockedPromptText(BuildContext context,
    {required String title,
    String initial = '',
    String? hint,
    bool anchored = false}) {
  final nav = DockedInfoNav.maybeOf(context);
  if (nav == null) {
    return promptText(context,
        title: title, initial: initial, hint: hint, anchored: anchored);
  }
  final done = Completer<String?>();
  nav.push(
      title,
      (_) => _CompleteOnDispose(
            done: done,
            child: _DockedPrompt(
              initial: initial,
              hint: hint,
              onDone: (v) {
                if (!done.isCompleted) done.complete(v);
                nav.pop();
              },
            ),
          ));
  return done.future;
}

Future<T?> dockedPick<T>(BuildContext context,
    {required String title,
    required List<(T value, String label, String? icon)> options,
    T? selected,
    required Future<T?> Function() fallback}) async {
  final nav = DockedInfoNav.maybeOf(context);
  if (nav == null) return fallback();
  final done = Completer<T?>();
  nav.push(
      title,
      (_) => _CompleteOnDispose(
            done: done,
            child: kMobile
                ? SettingsGroup(children: [
                    for (final (value, label, icon) in options)
                      AgentPageRow(
                        label: label,
                        icon: icon,
                        checked: value == selected,
                        chevron: false,
                        onTap: () {
                          if (!done.isCompleted) done.complete(value);
                          nav.pop();
                        },
                      ),
                  ])
                : PanelGroup(children: [
                    for (final (value, label, icon) in options)
                      PanelRow(
                        label: label,
                        icon: icon,
                        trailing: PanelRadio(on: value == selected),
                        onTap: () {
                          if (!done.isCompleted) done.complete(value);
                          nav.pop();
                        },
                      ),
                  ]),
          ));
  return done.future;
}

/// Completes [done] with null when the page goes away without an answer, so a
/// back-button dismissal never leaves the caller waiting.
class _CompleteOnDispose<T> extends StatefulWidget {
  const _CompleteOnDispose({required this.done, required this.child});

  final Completer<T?> done;
  final Widget child;

  @override
  State<_CompleteOnDispose<T>> createState() => _CompleteOnDisposeState<T>();
}

class _CompleteOnDisposeState<T> extends State<_CompleteOnDispose<T>> {
  @override
  void dispose() {
    if (!widget.done.isCompleted) widget.done.complete(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DockedPrompt extends StatefulWidget {
  const _DockedPrompt(
      {required this.initial, required this.hint, required this.onDone});

  final String initial;
  final String? hint;
  final ValueChanged<String> onDone;

  @override
  State<_DockedPrompt> createState() => _DockedPromptState();
}

class _DockedPromptState extends State<_DockedPrompt> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.sm),
        borderSide: BorderSide(color: AppColors.border));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          style: TS.body(AppColors.fg1),
          onSubmitted: (_) => widget.onDone(_text.text),
          decoration: InputDecoration(
            helperText: widget.hint,
            helperMaxLines: 3,
            helperStyle: sans(12, color: AppColors.fg3),
            isDense: true,
            filled: true,
            fillColor: AppColors.surface2,
            border: border,
            enabledBorder: border,
          ),
        ),
        SizedBox(height: S.s12),
        Align(
          alignment: Alignment.centerRight,
          child:
              Btn('Save', small: true, onTap: () => widget.onDone(_text.text)),
        ),
      ],
    );
  }
}

/// iMessage-style contact/info screen for a direct agent chat.
///
/// On phones this is a full-height frosted route over the chat; on desktop the
/// panels dock at the right of the chat pane (340px) and [showAgentInfo] falls
/// back to a right-side dialog of the same width.
Future<void> showAgentInfo(
  BuildContext context, {
  required DaemonClient client,
  required String agentId,
  required String name,
  CoordinationAgent? agent,
  VoidCallback? onOpenInbox,
  VoidCallback? onOpenBoard,
  VoidCallback? onOpenDesk,
  VoidCallback? onChanged,
}) {
  Widget panel(VoidCallback close) => AgentInfoPanel(
        client: client,
        agentId: agentId,
        name: name,
        agent: agent,
        onOpenInbox: onOpenInbox,
        onOpenBoard: onOpenBoard,
        onOpenDesk: onOpenDesk,
        onChanged: onChanged,
        onClose: close,
      );
  if (kMobile) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      AppPageRoute(
          builder: (ctx) =>
              panel(() => Navigator.of(ctx, rootNavigator: true).pop())),
    );
  }
  return _showDesktopInfo(context, panel);
}

/// iMessage-style info screen for a group chat. Same presentation rules as
/// [showAgentInfo].
Future<void> showGroupInfo(
  BuildContext context, {
  required DaemonClient client,
  required GroupSummary group,
  VoidCallback? onOpenTasks,
  VoidCallback? onChanged,
}) {
  Widget panel(VoidCallback close) => GroupInfoPanel(
        client: client,
        group: group,
        onOpenTasks: onOpenTasks,
        onChanged: onChanged,
        onClose: close,
      );
  if (kMobile) {
    // A page like the agent's info, not a sheet: same push, same back swipe.
    return Navigator.of(context, rootNavigator: true).push<void>(
      AppPageRoute(
          builder: (ctx) =>
              panel(() => Navigator.of(ctx, rootNavigator: true).pop())),
    );
  }
  return _showDesktopInfo(context, panel);
}

/// The agent info panel, for desktop docking (right of the chat pane, 340px)
/// or inside the phone sheet. [onClose] dismisses it.
class AgentInfoPanel extends StatefulWidget {
  const AgentInfoPanel({
    super.key,
    required this.client,
    required this.agentId,
    required this.name,
    this.agent,
    this.onOpenInbox,
    this.onOpenBoard,
    this.onOpenDesk,
    this.onOpenMemory,
    this.onChanged,
    this.onClose,
    this.docked = false,
    this.contextUsed = 0,
    this.contextWindow = 0,
    this.onCompact,
    this.onAutonomy,
    this.onScheduled,
  });

  final DaemonClient client;
  final String agentId;
  final String name;
  final CoordinationAgent? agent;
  final int contextUsed;
  final int contextWindow;
  final VoidCallback? onCompact;
  final VoidCallback? onAutonomy;
  final VoidCallback? onScheduled;
  final VoidCallback? onOpenInbox;
  final VoidCallback? onOpenBoard;
  final VoidCallback? onOpenDesk;
  final VoidCallback? onOpenMemory;
  final VoidCallback? onChanged;
  final VoidCallback? onClose;

  /// Docked in the desktop agent panel: actions open beside it, so they leave
  /// the panel up.
  final bool docked;

  @override
  State<AgentInfoPanel> createState() => _AgentInfoPanelState();
}

class _AgentInfoPanelState extends State<AgentInfoPanel> {
  final _navKey = GlobalKey<NavigatorState>();
  InferenceProfile? _profileInfo;

  @override
  void initState() {
    super.initState();
    if (!kMobile) _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final cfg = await widget.client.getConfig();
      final name = (widget.agent?.profile ?? '').trim();
      final hit = cfg.profiles.where((p) => p.name == name).firstOrNull;
      if (mounted && hit != null) setState(() => _profileInfo = hit);
    } catch (_) {}
  }

  void _pushNested(String title, WidgetBuilder body,
      {List<Widget> actions = const [], bool scroll = true}) {
    _navKey.currentState?.push(_NestedPageRoute(
        title: title, builder: body, actions: actions, scroll: scroll));
  }

  void _popNested() => _navKey.currentState?.maybePop();

  void _close() {
    final close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _editNickname(BuildContext ctx) async {
    final agent = widget.agent;
    if (agent == null) return;
    final nav = DockedInfoNav.maybeOf(ctx);
    if (nav != null) {
      nav.push(
          'Nickname',
          (_) => _NicknameEditor(
                client: widget.client,
                agent: agent,
                onChanged: widget.onChanged,
                onClose: nav.pop,
              ));
      return;
    }
    final next = await promptText(ctx,
        title: 'Nickname for ${widget.name}',
        initial: agent.nickname ?? '',
        hint: 'Leave empty to use the name');
    if (next == null || next == (agent.nickname ?? '') || !mounted) return;
    try {
      await widget.client
          .setAgentNickname(agent.id, next.isEmpty ? null : next);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _deleteAgent(BuildContext ctx) async {
    final agent = widget.agent;
    if (agent == null) return;
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName.trim();
    final ok = await confirmAction(ctx,
        title: 'Delete $name?',
        body:
            'This removes the agent, its identity and its notes. Its past task history loses it too. This can\'t be undone.',
        confirmLabel: 'Delete agent');
    if (!ok || !mounted) return;
    try {
      await widget.client.deleteAgent(agent.id);
      if (!mounted) return;
      toast(context, 'Deleted $name');
      widget.onChanged?.call();
      _close();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  bool get _mc =>
      widget.agentId == 'mission-control' ||
      (widget.agent?.isMissionControl ?? false);

  // Opens on top of this page, so back returns here.
  void _go(VoidCallback open) => open();

  void _openMemory(BuildContext ctx) {
    final open = widget.onOpenMemory;
    if (open != null) return _go(open);
    DockedInfoNav.maybeOf(ctx)?.push(
        'Memory',
        (_) => MemoryScreen(
            client: widget.client,
            embedded: true,
            hideBack: true,
            initialKey: 'agent:${widget.agentId}'),
        scroll: false);
  }

  void _openAppearance(BuildContext ctx) => showAgentAppearance(
      kMobile ? context : ctx, widget.client, widget.agentId, widget.name);

  /// What the models row holds, so nobody has to open it to find out.
  static String _modelsLine(CoordinationAgent a) {
    final tasks = a.profile ?? 'default';
    final desk = a.deskModel ?? tasks;
    final ctx = a.maxContextTokens;
    final c = ctx == null ? 'model window' : '${(ctx / 1000).round()}k';
    return 'Desk $desk \u00b7 Tasks $tasks \u00b7 Context $c';
  }

  /// The agent page: who it is, then its settings, then where its work lives.
  Widget _groups(BuildContext ctx) {
    if (!kMobile) return _desktopGroups(ctx);
    final agent = widget.agent;
    final mc = _mc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mc && widget.onCompact != null)
          SettingsGroup(children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: S.s4),
              child: _ContextMeter(
                  used: widget.contextUsed,
                  window: widget.contextWindow,
                  onCompact: widget.onCompact!),
            ),
          ]),
        const AgentPageCaption('Agent'),
        SettingsGroup(
            footer:
                kMobile ? 'Long-press the avatar to copy the agent ID.' : null,
            children: [
              if (agent != null && !mc)
                AgentPageRow(
                    label: 'Models and context',
                    subtitle: _modelsLine(agent),
                    icon: 'cpu',
                    onTap: () => showAgentProfileSettings(ctx,
                        client: widget.client,
                        agent: agent,
                        name: widget.name,
                        onChanged: widget.onChanged)),
              if (mc && widget.onAutonomy != null)
                AgentPageRow(
                    label: 'Automated wakes',
                    subtitle: 'What wakes it without you',
                    icon: 'activity',
                    onTap: widget.onAutonomy),
              if (mc && widget.onScheduled != null)
                AgentPageRow(
                    label: 'Scheduled',
                    subtitle: 'Recurring goals and messages',
                    icon: 'scheduled',
                    onTap: widget.onScheduled),
              if (!mc)
                AgentPageRow(
                    label: 'Wakes and reporting',
                    subtitle: 'When it wakes and who it tells',
                    icon: 'repeat',
                    onTap: () => showAgentWakeSettings(ctx,
                        client: widget.client,
                        owner: widget.agentId,
                        name: widget.name,
                        onChanged: widget.onChanged)),
              AgentPageRow(
                  label: 'How it reaches you',
                  subtitle: 'Notifications and where each kind goes',
                  icon: 'bell',
                  onTap: () => showAgentReachSettings(ctx,
                      client: widget.client,
                      agentId: widget.agentId,
                      name: widget.name)),
              if (agent != null && !mc)
                AgentPageRow(
                    label: 'Nickname',
                    subtitle: 'What it is called here',
                    icon: 'edit',
                    onTap: () => _editNickname(ctx)),
              AgentPageRow(
                  label: 'Appearance',
                  subtitle: 'Avatar and colour across the app',
                  iconData: LucideIcons.star,
                  onTap: () => _openAppearance(ctx)),
            ]),
        const AgentPageCaption('Work'),
        SettingsGroup(children: [
          if (widget.onOpenInbox != null)
            AgentPageRow(
                label: 'Inbox',
                subtitle: 'Everything sent to this agent',
                icon: 'inbox',
                onTap: () => _go(widget.onOpenInbox!)),
          if (widget.onOpenBoard != null)
            AgentPageRow(
                label: 'Board',
                subtitle: 'What it dispatched, reported and noted',
                iconData: LucideIcons.columns3,
                onTap: () => _go(widget.onOpenBoard!)),
          if (widget.onOpenDesk != null && !mc)
            AgentPageRow(
                label: 'Desk session',
                subtitle: 'The conversation where its mail arrives',
                iconData: LucideIcons.messageCircle,
                onTap: () => _go(widget.onOpenDesk!)),
          AgentPageRow(
              label: 'Memory',
              subtitle: 'What this agent remembers',
              iconData: LucideIcons.book,
              onTap: () => _openMemory(ctx)),
        ]),
        // Destructive last, in its own group, away from everyday rows.
        if (agent != null && !mc)
          SettingsGroup(children: [
            AgentPageRow(
                label: 'Delete agent',
                subtitle: 'Removes its identity and notes',
                icon: 'trash',
                danger: true,
                onTap: () => _deleteAgent(ctx)),
          ]),
      ],
    );
  }

  static String _stateLabel(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _elapsed(DateTime since) {
    final d = DateTime.now().difference(since);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Widget? _statusRow() {
    final p = widget.agent?.presence;
    if (p == null || !p.active) return null;
    return PanelRow(
      leading: Container(
        padding: EdgeInsets.symmetric(horizontal: S.of(7), vertical: S.s2),
        decoration: BoxDecoration(
          color: AppColors.runBg,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: AppColors.run, shape: BoxShape.circle)),
          SizedBox(width: S.s4),
          Text(_stateLabel(p.state), style: sans(11.5, color: AppColors.run)),
        ]),
      ),
      label: p.detail,
      value: p.since == null ? null : _elapsed(p.since!),
    );
  }

  /// The desktop page: status, work, settings, then the destructive row.
  Widget _desktopGroups(BuildContext ctx) {
    final agent = widget.agent;
    final mc = _mc;
    final status = _statusRow();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mc && widget.onCompact != null)
          PanelGroup(children: [
            _ContextMeter(
                used: widget.contextUsed,
                window: widget.contextWindow,
                onCompact: widget.onCompact!),
          ]),
        if (status != null) PanelGroup(children: [status]),
        PanelGroup(children: [
          if (widget.onOpenInbox != null)
            PanelRow(
                label: 'Inbox',
                sub: 'Everything sent to this agent',
                icon: 'inbox',
                chevron: true,
                onTap: () => _go(widget.onOpenInbox!)),
          if (widget.onOpenBoard != null)
            PanelRow(
                label: 'Board',
                sub: 'What it dispatched, reported and noted',
                icon: 'kanban',
                chevron: true,
                onTap: () => _go(widget.onOpenBoard!)),
          PanelRow(
              label: 'Memory',
              sub: 'What this agent remembers',
              icon: 'book',
              chevron: true,
              onTap: () => _openMemory(ctx)),
        ]),
        PanelGroup(children: [
          if (agent != null && !mc)
            PanelRow(
                label: 'Models and context',
                sub: _modelsLine(agent),
                icon: 'cpu',
                chevron: true,
                onTap: () => showAgentProfileSettings(ctx,
                    client: widget.client,
                    agent: agent,
                    name: widget.name,
                    onChanged: widget.onChanged)),
          if (mc && widget.onAutonomy != null)
            PanelRow(
                label: 'Automated wakes',
                sub: 'What wakes it without you',
                icon: 'activity',
                chevron: true,
                onTap: widget.onAutonomy),
          if (mc && widget.onScheduled != null)
            PanelRow(
                label: 'Scheduled',
                sub: 'Recurring goals and messages',
                icon: 'scheduled',
                chevron: true,
                onTap: widget.onScheduled),
          if (!mc)
            PanelRow(
                label: 'Wakes and reporting',
                sub: 'When it wakes and who it tells',
                icon: 'repeat',
                chevron: true,
                onTap: () => showAgentWakeSettings(ctx,
                    client: widget.client,
                    owner: widget.agentId,
                    name: widget.name,
                    onChanged: widget.onChanged)),
          PanelRow(
              label: 'How it reaches you',
              sub: 'Notifications and where each kind goes',
              icon: 'bell',
              chevron: true,
              onTap: () => showAgentReachSettings(ctx,
                  client: widget.client,
                  agentId: widget.agentId,
                  name: widget.name)),
          PanelRow(
              label: 'Appearance',
              sub: 'Avatar and colour across the app',
              icon: 'sparkles',
              chevron: true,
              onTap: () => _openAppearance(ctx)),
          if (agent != null && !mc)
            PanelRow(
                label: 'Nickname',
                sub: 'What it is called here',
                icon: 'edit',
                chevron: true,
                onTap: () => _editNickname(ctx)),
        ]),
        if (agent != null && !mc)
          PanelGroup(children: [
            PanelRow(
                label: 'Delete agent',
                icon: 'trash',
                danger: true,
                onTap: () => _deleteAgent(ctx)),
          ]),
      ],
    );
  }

  void _openTasks(BuildContext ctx) {
    DockedInfoNav.maybeOf(ctx)?.push(
        'Tasks',
        (c) => TasksPanel(
              client: widget.client,
              agentIds: {widget.agentId},
              phoneHeader: false,
              onOpenTask: (t) => openTaskDetail(c, widget.client, t.id),
            ),
        scroll: false);
  }

  /// The docked desktop page: identity, presence, quick links, accordions.
  Widget _dockedBody(BuildContext ctx) {
    final agent = widget.agent;
    final mc = _mc;
    final profile = (agent?.profile ?? '').trim();
    final role = _mc
        ? 'Coordinator'
        : (agent?.capabilities.isNotEmpty ?? false)
            ? agent!.capabilities.first
            : '';
    final sub = [
      if (role.isNotEmpty) role,
      profile.isNotEmpty ? profile : 'Routing default',
    ].join(' \u00b7 ');
    final rows = <AgentSettingRow>[
      if (agent != null && !mc)
        AgentSettingRow(
            'cpu',
            'Model and context',
            _modelsLine(agent),
            () => showAgentProfileSettings(ctx,
                client: widget.client,
                agent: agent,
                name: widget.name,
                onChanged: widget.onChanged)),
      if (mc && widget.onAutonomy != null)
        AgentSettingRow('activity', 'Automated wakes',
            'What wakes it without you', widget.onAutonomy!),
      if (mc && widget.onScheduled != null)
        AgentSettingRow('scheduled', 'Scheduled',
            'Recurring goals and messages', widget.onScheduled!),
      if (!mc)
        AgentSettingRow(
            'repeat',
            'Wakes and reporting',
            'When it wakes and who it tells',
            () => showAgentWakeSettings(ctx,
                client: widget.client,
                owner: widget.agentId,
                name: widget.name,
                onChanged: widget.onChanged)),
      AgentSettingRow(
          'bell',
          'How it reaches you',
          'Notifications and where each kind goes',
          () => showAgentReachSettings(ctx,
              client: widget.client,
              agentId: widget.agentId,
              name: widget.name)),
      AgentSettingRow('sparkles', 'Appearance',
          'Avatar and colour across the app', () => _openAppearance(ctx)),
    ];
    return AgentPanelBody(
      client: widget.client,
      agentId: widget.agentId,
      name: widget.name,
      sub: sub,
      agent: agent,
      settings: rows,
      header: mc && widget.onCompact != null
          ? _ContextMeter(
              used: widget.contextUsed,
              window: widget.contextWindow,
              onCompact: widget.onCompact!)
          : null,
      onInbox:
          widget.onOpenInbox == null ? null : () => _go(widget.onOpenInbox!),
      onBoard:
          widget.onOpenBoard == null ? null : () => _go(widget.onOpenBoard!),
      onMemory: () => _openMemory(ctx),
      onTasks: () => _openTasks(ctx),
      onDesk: widget.onOpenDesk,
      onNickname: agent != null && !mc ? () => _editNickname(ctx) : null,
      onDelete: agent != null && !mc ? () => _deleteAgent(ctx) : null,
      onHeroLongPress: () {
        Clipboard.setData(ClipboardData(text: widget.agentId));
        toast(context, 'Agent ID copied');
      },
    );
  }

  Widget _hero() {
    final agent = widget.agent;
    final profile = (agent?.profile ?? '').trim();
    final model = _profileInfo?.model ?? '';
    final sub = _mc
        ? 'Coordinator'
        : (profile.isNotEmpty
            ? (model.isNotEmpty ? '$model · $profile' : profile)
            : 'Routing default');
    void copyId() {
      Clipboard.setData(ClipboardData(text: widget.agentId));
      toast(context, 'Agent ID copied');
    }

    if (kMobile || !widget.docked) {
      return Semantics(
        label: '${widget.name}, $sub',
        excludeSemantics: true,
        child: Padding(
          padding: EdgeInsets.only(bottom: S.s16),
          child: SettingsHero(
            avatar: AgentMochi(widget.agentId, size: Grouped.avatarCharacter),
            name: widget.name,
            sub: sub,
            onLongPress: copyId,
          ),
        ),
      );
    }
    return Semantics(
      label: '${widget.name}, $sub',
      excludeSemantics: true,
      child: GestureDetector(
        // The id is still one long press away for scripts and the CLI.
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: widget.agentId));
          toast(context, 'Agent ID copied');
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(S.s12, S.s4, S.s12, S.s12),
          child: Row(children: [
            AgentMochi(widget.agentId, size: 52),
            SizedBox(width: S.s12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            sans(17, weight: W.strong, color: AppColors.fg1)),
                    SizedBox(height: S.s2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12.5, color: AppColors.fg3)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    Widget root(BuildContext ctx) => _AgentPageFrame(
          // On phones the centred hero carries the name.
          title: kMobile ? '' : 'Agent',
          onBack: widget.docked || !kMobile ? null : _close,
          onClose: widget.docked || !kMobile ? widget.onClose : null,
          closeIcon: 'panel-right',
          closeTooltip: 'Hide panel',
          bare: !kMobile && widget.docked,
          actions: kMobile || widget.docked
              ? const []
              : [
                  if (widget.onOpenDesk != null && !_mc)
                    PanelBarButton(
                        'monitor', 'Desk session', widget.onOpenDesk),
                  if (agent != null && !_mc)
                    Builder(
                        builder: (bc) => PanelBarButton(
                            'ellipsis',
                            'More',
                            () => showCrewAgentMenu(bc,
                                    client: widget.client,
                                    agent: agent, onDeleted: () {
                                  widget.onChanged?.call();
                                  _close();
                                }))),
                ],
          children: !kMobile && widget.docked
              ? [_dockedBody(ctx)]
              : [_hero(), _groups(ctx)],
        );
    final nav = DockedInfoNav(
      push: _pushNested,
      pop: _popNested,
      close: widget.onClose,
      child: NavigatorPopHandler<Object?>(
        onPopWithResult: (_) => _navKey.currentState?.maybePop(),
        child: _DockedNavigator(navKey: _navKey, root: root),
      ),
    );
    return kMobile ? nav : _DesktopPanelShell(child: nav);
  }
}

/// One page of the agent panel: the subHead on phones (back circle and title),
/// the 40px drawer bar on desktop, then a scrolling column of groups.
class _AgentPageFrame extends StatelessWidget {
  const _AgentPageFrame({
    required this.title,
    required this.children,
    this.onBack,
    this.onClose,
    this.actions = const [],
    this.scroll = true,
    this.closeIcon = 'x',
    this.closeTooltip = 'Close',
    this.bare = false,
  });

  /// Desktop only: no bar, the shell owns the panel toggle.
  final bool bare;
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final String closeIcon;
  final String closeTooltip;
  final List<Widget> actions;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    if (!kMobile) return _desktop(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final body = scroll
        ? ListView(
            physics: kMobile
                ? const BouncingScrollPhysics()
                : const ClampingScrollPhysics(),
            padding: kMobile
                ? EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s24 + bottom)
                : EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s24),
            children: children,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final c in children) Expanded(child: c)]);
    final head = Padding(
      padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s16, S.s4),
      child: SettingsHeader(
        title: title,
        compact: true,
        onBack: onBack ?? () => Navigator.of(context).maybePop(),
        actions: actions,
      ),
    );
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [head, Expanded(child: body)]),
      ),
    );
  }

  /// The docked card page: a 44px bar, then content that sizes to itself up to
  /// the panel's height.
  Widget _desktop(BuildContext context) {
    final room = (_PanelMax.of(context) - (bare ? 0 : 44)).clamp(120.0, 4000.0);
    final bar = bare
        ? const SizedBox.shrink()
        : PanelBar(
            title: title,
            onBack: onBack,
            actions: [
              ...actions,
              if (onClose != null)
                PanelBarButton(closeIcon, closeTooltip, onClose),
            ],
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        if (scroll)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: room),
            child: ListView(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(top: S.s2, bottom: S.s4),
              children: children,
            ),
          )
        else
          SizedBox(
            height: room,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final c in children) Expanded(child: c)]),
          ),
      ],
    );
  }
}

/// How tall the card may grow; pages size to their content up to this.
class _PanelMax extends InheritedWidget {
  const _PanelMax({required this.height, required super.child});
  final double height;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PanelMax>()?.height ?? 640;

  @override
  bool updateShouldNotify(_PanelMax old) => old.height != height;
}

/// The desktop card around a docked or dialog panel's navigator. The card is
/// as tall as the current page, so the navigator gets unbounded height.
class _DesktopPanelShell extends StatelessWidget {
  const _DesktopPanelShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight.isFinite ? c.maxHeight : 700.0;
          return _PanelMax(
            height: h - S.s12 * 2,
            child: PanelCard(
              child: UnconstrainedBox(
                constrainedAxis: Axis.horizontal,
                child: child,
              ),
            ),
          );
        },
      );
}

/// A group caption on the agent pages, sentence case and quiet; it sits a
/// few pixels inside the group's edge.
class AgentPageCaption extends StatelessWidget {
  const AgentPageCaption(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: kMobile
            ? EdgeInsets.fromLTRB(S.s4, S.s2, S.s4, S.s6)
            : EdgeInsets.fromLTRB(S.s2, S.s2, S.s2, S.s4),
        child: Semantics(
          header: true,
          child: Text(text,
              style: kMobile
                  ? Grouped.labelStyle()
                  : sans(12, color: AppColors.fg3)),
        ),
      );
}

/// A row of the agent pages, after the round 5 `.sitem`: a 30px icon tile,
/// 15px title over a 12px line on phones; a 22px tile with the line inline at
/// 32px on desktop.
class AgentPageRow extends StatelessWidget {
  const AgentPageRow({
    super.key,
    required this.label,
    this.subtitle,
    this.icon,
    this.iconData,
    this.value,
    this.valueMono = false,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.checked = false,
    this.selected = false,
    this.chevron,
  });

  final String label;
  final String? subtitle;
  final String? icon;
  final IconData? iconData;
  final String? value;
  final bool valueMono;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  /// The chosen row of a pick list: an accent tick instead of the chevron.
  final bool checked;

  /// The current choice of a pick list: a faint accent wash and accent tile.
  final bool selected;

  /// Defaults to showing when the row opens something, and never for danger.
  final bool? chevron;

  @override
  Widget build(BuildContext context) {
    final phone = kMobile;
    if (!checked && !selected) {
      return SettingsRow(
        label: label,
        sub: subtitle,
        subMaxLines: 1,
        icon: icon,
        iconData: iconData,
        value: value,
        trailing: trailing,
        onTap: onTap,
        danger: danger,
        chevron: trailing == null && (chevron ?? (onTap != null && !danger)),
      );
    }
    final labelColor = danger ? AppColors.danger : AppColors.fg1;
    final hasIcon = icon != null || iconData != null;
    final tileSize = phone ? 30.0 : 22.0;
    final glyph = phone ? 16.0 : 14.0;
    final glyphColor = selected ? AppColors.accent : AppColors.fg2;
    final tile = !hasIcon
        ? null
        : Container(
            width: tileSize,
            height: tileSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.14)
                    : AppColors.surface2,
                borderRadius: BorderRadius.circular(R.of(phone ? 9 : 6))),
            child: iconData != null
                ? Icon(iconData, size: glyph, color: glyphColor)
                : AppIcon(icon!, size: glyph, color: glyphColor),
          );
    final sub = subtitle != null && subtitle!.isNotEmpty ? subtitle : null;
    final title = Text(label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: sans(phone ? 15 : 13, weight: W.label, color: labelColor));
    final Widget text = phone
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              if (sub != null)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg3)),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
                Flexible(flex: 0, child: title),
                if (sub != null) ...[
                  SizedBox(width: S.s8),
                  Flexible(
                    child: Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ),
                ],
              ]);
    final v = value;
    final showChevron =
        !checked && trailing == null && (chevron ?? (onTap != null && !danger));
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: phone ? 52 : 32),
      child: Padding(
        padding: phone
            ? EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.s8)
            : EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.s4),
        child: Row(children: [
          if (tile != null) ...[tile, SizedBox(width: phone ? S.s12 : S.s8)],
          Expanded(child: text),
          if (v != null && v.isNotEmpty) ...[
            SizedBox(width: S.s8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: phone ? 150 : 220),
              child: Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: valueMono
                      ? mono(12, color: AppColors.fg3)
                      : sans(phone ? 12.5 : 12, color: AppColors.fg3)),
            ),
          ],
          if (trailing != null) ...[SizedBox(width: S.s8), trailing!],
          if (checked) ...[
            SizedBox(width: S.s8),
            AppIcon('check', size: phone ? 16 : 14, color: AppColors.accent),
          ],
          if (showChevron) ...[
            SizedBox(width: S.s6),
            AppIcon('chevron-right', size: 14, color: AppColors.fg4),
          ],
        ]),
      ),
    );
    final shown = selected
        ? ColoredBox(
            color: AppColors.accent.withValues(alpha: 0.07), child: row)
        : row;
    if (onTap == null) return shown;
    return Semantics(
      button: true,
      selected: selected || checked,
      child: InkWell(onTap: onTap, child: shown),
    );
  }
}

/// The group info panel. Same presentation rules as [AgentInfoPanel].
class GroupInfoPanel extends StatefulWidget {
  const GroupInfoPanel({
    super.key,
    required this.client,
    required this.group,
    this.onOpenTasks,
    this.onChanged,
    this.onClose,
    this.docked = false,
  });

  /// Docked beside the chat: no close button, and actions keep it open.
  /// [onClose] then closes the conversation (after Delete group).
  final bool docked;
  final DaemonClient client;
  final GroupSummary group;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onChanged;
  final VoidCallback? onClose;

  @override
  State<GroupInfoPanel> createState() => _GroupInfoPanelState();
}

class _PickItem {
  const _PickItem(this.id, this.title, this.sub, this.selected);
  final String id;
  final String title;
  final String? sub;
  final bool selected;
}

class _GroupInfoPanelState extends State<GroupInfoPanel> {
  late GroupSummary _group = widget.group;
  List<CoordinationAgent> _agents = const [];
  Map<String, CoordinationAgent> _byId = const {};
  bool _busy = false;
  int? _openTasks;
  final _navKey = GlobalKey<NavigatorState>();

  void _pushNested(String title, WidgetBuilder body,
      {List<Widget> actions = const [], bool scroll = true}) {
    _navKey.currentState?.push(_NestedPageRoute(
        title: title, builder: body, actions: actions, scroll: scroll));
  }

  void _popNested() => _navKey.currentState?.maybePop();

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  /// Desktop: a nested page in the panel. Phone: a sheet.
  Future<String?> _pickFrom(String title, List<_PickItem> items, bool radios) {
    if (!kMobile && _navKey.currentState != null) {
      final done = Completer<String?>();
      void pick(String id) {
        if (!done.isCompleted) done.complete(id);
        _navKey.currentState?.maybePop();
      }

      _navKey.currentState!
          .push(_NestedPageRoute(
              title: title,
              builder: (_) => PanelGroup(children: [
                    for (final it in items)
                      PanelRow(
                        label: it.title,
                        sub: it.sub,
                        leading: AgentMochi(it.id, size: 24),
                        trailing: radios ? PanelRadio(on: it.selected) : null,
                        onTap: () => pick(it.id),
                      ),
                  ])))
          .then((_) {
        if (!done.isCompleted) done.complete(null);
      });
      return done.future;
    }
    return showAppSheet<String>(
      context,
      title: title,
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final it in items)
              ListRow(
                title: it.title,
                subtitle: it.sub,
                leading: AgentMochi(it.id, size: 20),
                trailing: it.selected && radios
                    ? AppIcon('check', size: 14, color: AppColors.fg1)
                    : null,
                onTap: () => Navigator.pop(ctx, it.id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadAgents() async {
    try {
      final all = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
        _agents = all
            .where((a) => !a.isMissionControl && a.status != 'archived')
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
        _byId = {for (final a in _agents) a.id: a};
      });
    } catch (_) {}
    if (kMobile) return;
    try {
      final n = await openTaskCountFor(widget.client, _group.agentIds);
      if (mounted) setState(() => _openTasks = n);
    } catch (_) {}
  }

  void _close() {
    final close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _update(Future<GroupSummary> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final g = await call();
      if (!mounted) return;
      setState(() => _group = g);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(String id, String kind) {
    if (kind == 'human') return 'You';
    if (id == 'mission-control') return 'Mission Control';
    final a = _byId[id];
    if (a == null) return id;
    final n = a.displayName.trim();
    return n.isEmpty ? id : n;
  }

  String? _leadName() {
    final lead = _group.lead;
    if (lead == null || lead.isEmpty) return null;
    return _name(lead, 'agent');
  }

  Future<void> _rename() async {
    final text = await dockedPromptText(_navKey.currentContext ?? context,
        title: 'Rename group', initial: _group.title);
    if (text == null || !mounted) return;
    final title = text.trim();
    if (title.isEmpty || title == _group.title) return;
    await _update(() => widget.client.updateGroup(_group.id, title: title));
  }

  Future<void> _pickLead() async {
    final members = [
      for (final m in _group.members)
        if (m.isAgent) m,
    ];
    if (members.isEmpty) return;
    final picked = await _pickFrom(
      'Group lead',
      [
        for (final m in members)
          _PickItem(m.id, _name(m.id, m.kind), null, m.id == _group.lead),
      ],
      true,
    );
    if (picked == null || picked == _group.lead || !mounted) return;
    await _update(() => widget.client.updateGroup(_group.id, lead: picked));
  }

  List<CoordinationAgent> get _addable => [
        for (final a in _agents)
          if (!_group.agentIds.contains(a.id)) a,
      ];

  Future<void> _pickAdd() async {
    final addable = _addable;
    if (addable.isEmpty) {
      toast(context, 'Every agent is already in this group');
      return;
    }
    final picked = await _pickFrom(
      'Add member',
      [
        for (final a in addable)
          _PickItem(a.id, a.displayName.trim().isEmpty ? a.id : a.displayName,
              a.id, false),
      ],
      !kMobile,
    );
    if (picked == null || !mounted) return;
    await _update(
        () => widget.client.updateGroup(_group.id, addMembers: [picked]));
  }

  Future<void> _deleteGroup() async {
    if (await confirmDeleteGroup(context, widget.client, _group)) {
      widget.onChanged?.call();
      _close();
    }
  }

  /// Desktop: tasks, then members with Lead and Add member, then Delete.
  Widget _desktopInfo() {
    final tasks = widget.onOpenTasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tasks != null)
          PanelGroup(children: [
            PanelRow(
              label: 'Tasks',
              icon: 'task',
              value: _openTasks == null ? null : '$_openTasks open',
              chevron: true,
              onTap: () {
                if (!widget.docked) _close();
                tasks();
              },
            ),
          ]),
        PanelGroup(children: [
          for (final m in _group.members) _memberRow(m),
          PanelRow(
            label: 'Lead',
            icon: 'crown',
            value: _leadName() ?? 'None',
            chevron: true,
            onTap: _busy ? null : _pickLead,
          ),
          PanelRow(
            label: 'Add member',
            icon: 'user-plus',
            chevron: true,
            onTap: _busy ? null : _pickAdd,
          ),
        ]),
        const PanelFootnote(
            'A lead answers first. Remove a member with the cross on its row.'),
        PanelGroup(children: [
          PanelRow(
              label: 'Delete group',
              icon: 'trash',
              danger: true,
              onTap: _deleteGroup),
        ]),
      ],
    );
  }

  Widget _memberRow(GroupMember m) {
    final lead = m.id == _group.lead;
    return _MemberRow(
      avatar: m.isAgent
          ? AgentMochi(m.id, size: 24)
          : AppIcon('user', size: 16, color: AppColors.fg3),
      name: _name(m.id, m.kind),
      role: m.isHuman ? 'Owner' : (lead ? 'Lead' : 'Member'),
      status: GroupMemberStatus(client: widget.client, member: m),
      onRemove: _busy || m.isHuman
          ? null
          : () => _update(() =>
              widget.client.updateGroup(_group.id, removeMembers: [m.id])),
    );
  }

  /// Phones: language A, the grouped rows of the settings pages.
  Widget _phoneInfo() {
    final tasks = widget.onOpenTasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tasks != null)
          SettingsGroup(children: [
            SettingsRow(
                label: 'Tasks', icon: 'task', chevron: true, onTap: tasks),
          ]),
        SettingsGroup(
          header: 'Members',
          footer: 'Long-press a member to remove them from the group.',
          children: [
            for (final m in _group.members)
              SettingsRow(
                label: _name(m.id, m.kind),
                sub: m.isHuman
                    ? null
                    : (m.id == _group.lead ? 'Lead' : 'Member'),
                leading: m.isAgent
                    // Icon-wide slot so names line up with the icon rows.
                    ? SizedBox.square(
                        dimension: Grouped.icon,
                        child: OverflowBox(
                            maxWidth: Grouped.icon + 10,
                            maxHeight: Grouped.icon + 10,
                            child: AgentMochi(m.id, size: Grouped.icon + 10)))
                    : null,
                icon: m.isHuman ? 'user' : null,
                onLongPress: _busy || m.isHuman
                    ? null
                    : () => _update(() => widget.client
                        .updateGroup(_group.id, removeMembers: [m.id])),
              ),
            SettingsRow(
              label: 'Lead',
              icon: 'crown',
              value: _leadName() ?? 'None',
              chevron: true,
              onTap: _busy ? null : _pickLead,
            ),
            SettingsRow(
              label: 'Add member',
              icon: 'user-plus',
              accent: true,
              onTap: _busy ? null : _pickAdd,
            ),
          ],
        ),
        SettingsGroup(children: [
          SettingsRow(
              label: 'Delete group',
              icon: 'trash',
              danger: true,
              onTap: _deleteGroup),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kMobile) return _frame();
    final nav = DockedInfoNav(
      push: _pushNested,
      pop: _popNested,
      child: _DockedNavigator(navKey: _navKey, root: (_) => _frame()),
    );
    return _DesktopPanelShell(child: nav);
  }

  Widget _frame() {
    final title = _group.title.trim().isEmpty ? 'Group' : _group.title.trim();
    final count = '${_group.members.length} '
        '${_group.members.length == 1 ? 'member' : 'members'}';
    if (kMobile && !widget.docked) {
      // Same page as an agent's: back circle, plate hero, grouped rows.
      return _AgentPageFrame(
        title: '',
        onBack: _close,
        actions: [_EditPill(onTap: _busy ? null : _rename)],
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: S.s16),
            child: SettingsHero(
              avatar: AgentCluster(
                  ids: _group.agentIds, size: Grouped.avatarCharacter),
              name: title,
              sub: count,
            ),
          ),
          _phoneInfo(),
        ],
      );
    }
    final hide =
        widget.docked ? ShellRequestScope.maybeOf(context)?.toggleSide : _close;
    return _AgentPageFrame(
      title: 'Group',
      onClose: hide,
      closeIcon: 'panel-right',
      closeTooltip: 'Hide panel',
      children: [
        GroupPanelHero(
          group: _group,
          title: title,
          trailing: _RenameButton(onTap: _busy ? null : _rename),
        ),
        _desktopInfo(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

class _RenameButton extends StatelessWidget {
  const _RenameButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(pr(8)),
        child: Container(
          height: 26,
          padding: EdgeInsets.symmetric(horizontal: S.of(10)),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(pr(8)),
            border: Border.all(color: AppColors.lineStrong),
          ),
          child: Text('Rename', style: sans(12, color: AppColors.fg1)),
        ),
      );
}

/// A member row: 24px avatar, name over its role, and a cross on hover.
class _MemberRow extends StatefulWidget {
  const _MemberRow(
      {required this.avatar,
      required this.name,
      this.role,
      this.status,
      this.onRemove});
  final Widget avatar;
  final String name;
  final String? role;
  final Widget? status;
  final VoidCallback? onRemove;

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: PanelRow(
          minHeight: 44,
          leading: SizedBox.square(
              dimension: 24, child: Center(child: widget.avatar)),
          label: widget.name,
          sub: widget.role,
          trailing: _hover && widget.onRemove != null
              ? PanelBarButton('x', 'Remove from group', widget.onRemove)
              : widget.status,
        ),
      );
}

class _EditPill extends StatelessWidget {
  const _EditPill({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Glass(
          radius: BorderRadius.circular(R.pill),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s6),
            child: Text('Edit',
                style: sans(13, weight: W.label, color: AppColors.fg1)),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Cards and rows
// ---------------------------------------------------------------------------

class _ContextMeter extends StatelessWidget {
  const _ContextMeter(
      {required this.used, required this.window, required this.onCompact});

  final int used;
  final int window;
  final VoidCallback onCompact;

  static String _k(int v) => v >= 1000 ? '${(v / 1000).round()}k' : '$v';

  @override
  Widget build(BuildContext context) {
    final known = window > 0 && used > 0;
    final frac = known ? (used / window).clamp(0.0, 1.0) : 0.0;
    final lit = (frac * 24).round();
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s16, S.of(14), S.s16, S.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            AppIcon('gauge', size: kMobile ? 18 : 16, color: AppColors.fg3),
            SizedBox(width: S.s12),
            Expanded(
                child: Text('Context',
                    style: sans(kMobile ? 15 : 13, color: AppColors.fg1))),
            Text(known ? '${_k(used)} / ${_k(window)}' : 'Not measured yet',
                style: mono(12, color: AppColors.fg3)),
          ]),
          SizedBox(height: S.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 24; i++)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < lit
                        ? (frac > 0.8 ? AppColors.danger : AppColors.fg2)
                        : AppColors.line,
                  ),
                ),
            ],
          ),
          SizedBox(height: S.of(14)),
          Btn('Compact now',
              full: true,
              small: !kMobile,
              variant: BtnVariant.secondary,
              onTap: onCompact),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Docked nested pages
// ---------------------------------------------------------------------------

/// A page pushed inside the docked panel's own [Navigator]: 52px chrome with a
/// back circle and centred title, then a scrolling body. Paints nothing, so
/// the see-through panel background shows through.
class _NestedPage extends StatelessWidget {
  const _NestedPage({
    required this.title,
    required this.builder,
    this.actions = const [],
    this.scroll = true,
  });

  final String title;
  final WidgetBuilder builder;
  final List<Widget> actions;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final nav = DockedInfoNav.maybeOf(context);
    // The transparent colour is only hit absorption: empty areas must not
    // fall through to the page underneath.
    return ColoredBox(
      color: Colors.transparent,
      child: _AgentPageFrame(
        title: title,
        onBack: nav?.pop ?? () => Navigator.of(context).maybePop(),
        actions: actions,
        scroll: scroll,
        children: [Builder(builder: builder)],
      ),
    );
  }
}

/// Slide-from-right route for [_NestedPage]; the first route (no title) is the
/// info page itself. Nothing is painted, so the panel stays see-through.
/// The docked panel's own navigator. Its root route is built once, so the
/// latest [root] is handed to it on every rebuild or the info page goes stale.
class _DockedNavigator extends StatefulWidget {
  const _DockedNavigator({required this.navKey, required this.root});
  final GlobalKey<NavigatorState> navKey;
  final WidgetBuilder root;

  @override
  State<_DockedNavigator> createState() => _DockedNavigatorState();
}

class _DockedNavigatorState extends State<_DockedNavigator> {
  late final _root = ValueNotifier<WidgetBuilder>(widget.root);

  @override
  void didUpdateWidget(_DockedNavigator old) {
    super.didUpdateWidget(old);
    _root.value = widget.root;
  }

  @override
  void dispose() {
    _root.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Navigator(
        key: widget.navKey,
        onGenerateRoute: (_) => _NestedPageRoute(
            builder: (_) => ValueListenableBuilder<WidgetBuilder>(
                valueListenable: _root, builder: (ctx, root, _) => root(ctx))),
      );
}

class _NestedPageRoute extends PageRoute<void> {
  _NestedPageRoute(
      {this.title,
      required this.builder,
      this.actions = const [],
      this.scroll = true});

  final String? title;
  final WidgetBuilder builder;
  final List<Widget> actions;
  final bool scroll;

  // The desktop card sizes to its page, which the overlay only allows from an
  // opaque route.
  @override
  bool get opaque => !kMobile;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Motion.base;

  @override
  Duration get reverseTransitionDuration => Motion.base;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      _fit(title == null
          ? builder(context)
          : _NestedPage(
              title: title!,
              builder: builder,
              actions: actions,
              scroll: scroll));

  // A covered page keeps its own height instead of overflowing the shorter one.
  static Widget _fit(Widget page) => kMobile
      ? page
      : UnconstrainedBox(
          constrainedAxis: Axis.horizontal,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: page);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
        parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    // The panel is see-through, so a covered page must fade or it shows under the new one.
    final covered = FadeTransition(
        opacity: ReverseAnimation(secondaryAnimation), child: child);
    if (reduceMotion(context)) {
      return FadeTransition(opacity: curved, child: covered);
    }
    return SlideTransition(
      position:
          Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
      child: covered,
    );
  }
}

/// The docked 'Nickname' page: same save as the old prompt, minus the dialog.
class _NicknameEditor extends StatefulWidget {
  const _NicknameEditor({
    required this.client,
    required this.agent,
    required this.onChanged,
    required this.onClose,
  });

  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback? onChanged;
  final VoidCallback onClose;

  @override
  State<_NicknameEditor> createState() => _NicknameEditorState();
}

class _NicknameEditorState extends State<_NicknameEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.agent.nickname ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = _text.text.trim();
    if (next == (widget.agent.nickname ?? '')) return widget.onClose();
    setState(() => _saving = true);
    try {
      await widget.client
          .setAgentNickname(widget.agent.id, next.isEmpty ? null : next);
      if (!mounted) return;
      widget.onChanged?.call();
      widget.onClose();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = kMobile;
    final full = widget.agent.fullName.trim().isEmpty
        ? widget.agent.id
        : widget.agent.fullName.trim();
    final radius = BorderRadius.circular(R.of(phone ? 12 : 8));
    OutlineInputBorder edge(Color c) => OutlineInputBorder(
        borderRadius: radius, borderSide: BorderSide(color: c));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: S.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: S.s4),
            child: Text('Nickname', style: sans(12, color: AppColors.fg3)),
          ),
          TextField(
            controller: _text,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: sans(phone ? 15 : 13, color: AppColors.fg1),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: full,
              hintStyle: sans(phone ? 15 : 13, color: AppColors.fg4),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface1,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: S.s12, vertical: phone ? S.s12 : S.s8),
              border: edge(AppColors.lineStrong),
              enabledBorder: edge(AppColors.lineStrong),
              focusedBorder: edge(AppColors.accent),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: S.s6),
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

/// The round 5 page button: 44px with 12px corners on phones, 28px on
/// desktop. [expand] fills the row, as the phone sheets do.
class AgentPageButton extends StatelessWidget {
  const AgentPageButton(this.label,
      {super.key,
      this.primary = false,
      this.expand = false,
      this.icon,
      this.iconData,
      this.onTap});

  final String label;
  final bool primary;
  final bool expand;
  final String? icon;
  final IconData? iconData;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final phone = kMobile;
    final fg = primary ? AppColors.accentFg : AppColors.fg1;
    final radius = BorderRadius.circular(R.of(phone ? 12 : 7));
    final glyph = phone ? 16.0 : 13.0;
    final body = Container(
      height: phone ? 44 : 28,
      padding: EdgeInsets.symmetric(horizontal: phone ? S.s16 : S.of(10)),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (iconData != null || icon != null) ...[
            iconData != null
                ? Icon(iconData, size: glyph, color: fg)
                : AppIcon(icon!, size: glyph, color: fg),
            SizedBox(width: S.s6),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(phone ? 14 : 12.5, weight: W.label, color: fg)),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: primary ? AppColors.accentFill : AppColors.surface2,
          borderRadius: radius,
          child: InkWell(borderRadius: radius, onTap: onTap, child: body),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop dialog
// ---------------------------------------------------------------------------

Future<void> _showDesktopInfo(
    BuildContext context, Widget Function(VoidCallback) panel) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: AppColors.modalScrim,
    transitionDuration: Motion.base,
    pageBuilder: (ctx, _, __) => Stack(children: [
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: 320,
        child: Material(
          type: MaterialType.transparency,
          child: panel(() => Navigator.of(ctx).pop()),
        ),
      ),
    ]),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
      if (reduceMotion(context)) {
        return FadeTransition(opacity: curved, child: child);
      }
      return SlideTransition(
        position: Tween(begin: const Offset(0.35, 0), end: Offset.zero)
            .animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}
