import 'dart:async';

import '../desktop_look.dart';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../glass.dart';
import '../models.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../screens/agent_appearance.dart' show showAgentAppearance;
import '../screens/agent_reach_panel.dart' show showAgentReachSettings;
import '../screens/agent_wake_panel.dart' show showAgentWakeSettings;
import '../screens/group_messaging.dart' show confirmDeleteGroup;
import 'agent_cluster.dart';
import '../screens/agent_profile_panel.dart' show showAgentProfileSettings;
import '../desktop_layout.dart' show SettingsHeader;
import '../screens/memory_screen.dart' show MemoryScreen;
import '../settings_form.dart' show SettingsGroup;
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
            child: SettingsGroup(children: [
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
      MaterialPageRoute(
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
    return Navigator.of(context, rootNavigator: true).push<void>(
      _InfoSheetRoute(
          builder: (ctx) => _PhoneSheet(
              child:
                  panel(() => Navigator.of(ctx, rootNavigator: true).pop()))),
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

  void _go(VoidCallback open) {
    // On the phone the page covers the thread, so it leaves before the view changes.
    if (!widget.docked && kMobile) _close();
    open();
  }

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

  /// The agent page: who it is, then its settings, then where its work lives.
  Widget _groups(BuildContext ctx) {
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
        SettingsGroup(children: [
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
                label: 'Inference profile',
                subtitle: 'The model it runs on',
                icon: 'cpu',
                onTap: () => showAgentProfileSettings(ctx,
                    client: widget.client,
                    agent: agent,
                    name: widget.name,
                    onChanged: widget.onChanged)),
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
          if (agent != null && !mc)
            AgentPageRow(
                label: 'Delete agent',
                subtitle: 'Removes its identity and notes',
                icon: 'trash',
                danger: true,
                onTap: () => _deleteAgent(ctx)),
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
      ],
    );
  }

  Widget _hero() {
    final agent = widget.agent;
    final sub = _mc
        ? 'Coordinator'
        : ((agent?.profile ?? '').trim().isNotEmpty
            ? agent!.profile!.trim()
            : 'Routing default');
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
          padding: kMobile
              ? EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, S.s16)
              : EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, S.s12),
          child: Row(children: [
            AgentMochi(widget.agentId, size: 64),
            SizedBox(width: S.s16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            sans(20, weight: W.strong, color: AppColors.fg1)),
                    SizedBox(height: S.s2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg3)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget root(BuildContext ctx) => _AgentPageFrame(
          title: widget.name,
          onBack: widget.docked || !kMobile ? null : _close,
          onClose: widget.docked || !kMobile ? widget.onClose : null,
          children: [_hero(), _groups(ctx)],
        );
    return DockedInfoNav(
      push: _pushNested,
      pop: _popNested,
      close: widget.onClose,
      child: NavigatorPopHandler<Object?>(
        onPopWithResult: (_) => _navKey.currentState?.maybePop(),
        child: _DockedNavigator(navKey: _navKey, root: root),
      ),
    );
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
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final List<Widget> actions;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
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
    final Widget head;
    if (kMobile) {
      head = Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s16, S.s4),
        child: SettingsHeader(
          title: title,
          compact: true,
          onBack: onBack ?? () => Navigator.of(context).maybePop(),
          actions: actions,
        ),
      );
    } else {
      head = Container(
        height: 40,
        padding: EdgeInsets.fromLTRB(onBack != null ? S.s6 : S.s16, 0, S.s8, 0),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(children: [
          if (onBack != null) ...[
            IconBtn('chevron-left',
                size: 28, iconSize: 15, tooltip: 'Back', onTap: onBack),
            SizedBox(width: S.s2),
          ],
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: W.strong, color: AppColors.fg1)),
          ),
          for (final a in actions) ...[a, SizedBox(width: S.s4)],
          if (onClose != null)
            IconBtn('x',
                size: 28, iconSize: 14, tooltip: 'Close', onTap: onClose),
        ]),
      );
    }
    return Material(
      color: kMobile ? AppColors.bg : Colors.transparent,
      child: SafeArea(
        bottom: false,
        top: kMobile,
        child: Column(children: [head, Expanded(child: body)]),
      ),
    );
  }
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
          child:
              Text(text, style: sans(kMobile ? 13 : 12, color: AppColors.fg3)),
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

class _GroupInfoPanelState extends State<GroupInfoPanel> {
  late GroupSummary _group = widget.group;
  List<CoordinationAgent> _agents = const [];
  Map<String, CoordinationAgent> _byId = const {};
  bool _busy = false;
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

  /// Docked: a nested page in the panel. Elsewhere: a sheet.
  Future<String?> _pickFrom(
      String title, List<Widget> Function(void Function(String)) rows) {
    if (widget.docked && _navKey.currentState != null) {
      final done = Completer<String?>();
      _navKey.currentState!
          .push(_NestedPageRoute(
              title: title,
              builder: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InfoCard(children: rows((id) {
                        if (!done.isCompleted) done.complete(id);
                        _navKey.currentState?.maybePop();
                      })),
                    ],
                  )))
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
          children: rows((id) => Navigator.pop(ctx, id)),
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
      (pick) => [
        for (final m in members)
          ListRow(
            title: _name(m.id, m.kind),
            leading: AgentMochi(m.id, size: 20),
            trailing: m.id == _group.lead
                ? AppIcon('check', size: 14, color: AppColors.fg1)
                : null,
            onTap: () => pick(m.id),
          ),
      ],
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
      (pick) => [
        for (final a in addable)
          ListRow(
            title: a.displayName.trim().isEmpty ? a.id : a.displayName,
            subtitle: a.id,
            leading: AgentMochi(a.id, size: 20),
            onTap: () => pick(a.id),
          ),
      ],
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

  Widget _membersSection() => _InfoCard(children: [
        for (final m in _group.members) _memberRow(m),
        _InfoRow(
          label: 'Lead',
          icon: 'crown',
          value: _leadName() ?? 'None',
          onTap: _busy ? null : _pickLead,
        ),
        _InfoRow(
          label: 'Add member',
          icon: 'user-plus',
          accent: true,
          onTap: _busy ? null : _pickAdd,
        ),
      ]);

  Widget _memberRow(GroupMember m) {
    final lead = m.id == _group.lead;
    final role = m.isHuman ? null : (lead ? 'Lead' : 'Member');
    return _LongPressRow(
      onLongPress: _busy || m.isHuman
          ? null
          : () => _update(() =>
              widget.client.updateGroup(_group.id, removeMembers: [m.id])),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s4),
          child: Row(children: [
            SizedBox.square(
              dimension: 26,
              child: Center(
                child: m.isAgent
                    ? AgentMochi(m.id, size: 26)
                    : AppIcon('user', size: 20, color: AppColors.fg3),
              ),
            ),
            SizedBox(width: S.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_name(m.id, m.kind),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15, color: AppColors.fg1)),
                  if (role != null)
                    Text(role,
                        style: sans(12,
                            color: lead ? AppColors.accent : AppColors.fg3)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _infoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _membersSection(),
        _InfoCard(children: [
          _DangerRow(label: 'Delete group', onTap: _deleteGroup),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.docked) return _frame();
    return DockedInfoNav(
      push: _pushNested,
      pop: _popNested,
      child: _DockedNavigator(navKey: _navKey, root: (_) => _frame()),
    );
  }

  Widget _frame() {
    final title = _group.title.trim().isEmpty ? 'Group' : _group.title.trim();
    final actions = <_CircleAction>[
      if (widget.onOpenTasks != null && !widget.docked)
        _CircleAction('task', 'Tasks', () {
          if (!widget.docked) _close();
          widget.onOpenTasks!();
        }),
    ];
    return _InfoFrame(
      onClose: widget.docked ? null : _close,
      edit: _EditPill(onTap: _busy ? null : _rename),
      avatar: AgentCluster(ids: _group.agentIds, size: kMobile ? 88 : 64),
      name: title,
      status: Text(
          '${_group.members.length} '
          '${_group.members.length == 1 ? 'member' : 'members'}',
          style: sans(13, color: AppColors.fg3)),
      actions: actions,
      tabs: const [],
      tab: 0,
      onTab: (_) {},
      body: _infoTab(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

class _CircleAction {
  const _CircleAction(this.icon, this.label, this.onTap);
  final String icon;
  final String label;
  final VoidCallback onTap;
}

class _InfoFrame extends StatelessWidget {
  const _InfoFrame({
    required this.onClose,
    required this.avatar,
    required this.name,
    required this.status,
    required this.actions,
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.body,
    this.edit,
  });

  final VoidCallback? onClose;
  final Widget? edit;
  final Widget avatar;
  final String name;
  final Widget status;
  final List<_CircleAction> actions;
  final List<String> tabs;
  final int tab;
  final ValueChanged<int> onTab;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(children: [
        SizedBox(
          height: 52,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s16),
            child: Row(children: [
              if (onClose != null)
                _GlassCircle(onTap: onClose!, icon: 'x', label: 'Close'),
              const Spacer(),
              if (edit != null) edit!,
            ]),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, 0),
          child: Column(children: [
            avatar,
            SizedBox(height: S.s12),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: sans(kMobile ? 26 : 20,
                    weight: W.strong, color: AppColors.fg1)),
            SizedBox(height: S.s4),
            status,
            if (actions.isNotEmpty) ...[
              SizedBox(height: S.s16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final a in actions) ...[
                    Flexible(child: _ActionCircle(action: a)),
                    if (a != actions.last) SizedBox(width: S.s12),
                  ],
                ],
              ),
            ],
            SizedBox(height: S.s20),
            if (tabs.length > 1) ...[
              _Segmented(labels: tabs, index: tab, onSelect: onTab),
              SizedBox(height: S.s16),
            ],
          ]),
        ),
        Expanded(
          child: ListView(
            physics: kMobile
                ? const BouncingScrollPhysics()
                : const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                S.s16, 0, S.s16, S.s24 + MediaQuery.paddingOf(context).bottom),
            children: [
              AnimatedSwitcher(
                duration:
                    reduced ? Motion.fast : const Duration(milliseconds: 180),
                switchInCurve: Motion.enter,
                switchOutCurve: Motion.exit,
                transitionBuilder: (child, anim) {
                  final curved =
                      CurvedAnimation(parent: anim, curve: Motion.enter);
                  if (reduced) {
                    return FadeTransition(opacity: curved, child: child);
                  }
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position:
                          Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                              .animate(curved),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(key: ValueKey(tab), child: body),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.onTap, required this.icon, this.label});

  final VoidCallback onTap;
  final String icon;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Glass(
            child: SizedBox.square(
              dimension: 36,
              child:
                  Center(child: AppIcon(icon, size: 16, color: AppColors.fg1)),
            ),
          ),
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

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({required this.action});

  final _CircleAction action;

  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: action.onTap,
          child: SizedBox(
            width: kMobile ? 64 : 56,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Glass(
                child: SizedBox.square(
                  dimension: kMobile ? 48 : 40,
                  child: Center(
                      child: AppIcon(action.icon,
                          size: kMobile ? 20 : 17, color: AppColors.fg1)),
                ),
              ),
              SizedBox(height: S.s6),
              Text(action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(11, color: AppColors.fg3)),
            ]),
          )));
}

class _Segmented extends StatelessWidget {
  const _Segmented(
      {required this.labels, required this.index, required this.onSelect});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    return Glass(
      radius: BorderRadius.circular(R.pill),
      child: Container(
        padding: EdgeInsets.all(S.of(3)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: i == index ? null : () => onSelect(i),
              child: AnimatedContainer(
                duration: reduced ? Duration.zero : Motion.fast,
                padding:
                    EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s6),
                decoration: BoxDecoration(
                  color: i == index
                      ? AppColors.fg1.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Text(labels[i],
                    style: sans(13,
                        weight: i == index ? W.label : W.body,
                        color: i == index ? AppColors.fg1 : AppColors.fg3)),
              ),
            ),
        ]),
      ),
    );
  }
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  // A Material of its own so row hover ink is clipped to the rounded card.
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: S.s12),
        child: Tactile(
          radius: BorderRadius.circular(R.of(16)),
          child: Material(
            color: kMobile
                ? AppColors.surface2.withValues(alpha: 0.6)
                : AppColors.surface1,
            shape: kMobile
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.of(16)))
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.of(12)),
                    side: BorderSide(color: AppColors.line)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1,
                        thickness: 1,
                        indent: kMobile ? S.s16 : 0,
                        endIndent: 0),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    this.value,
    this.onTap,
    this.icon,
    this.accent = false,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final String? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final labelColor = accent ? AppColors.accent : AppColors.fg1;
    final hasValue = value != null && value!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 48 : 34),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s16 : S.s8),
          child: Row(children: [
            if (icon != null && !kMobile) ...[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.tint2,
                    borderRadius: BorderRadius.circular(R.of(6))),
                child: AppIcon(icon!,
                    size: 13, color: accent ? AppColors.accent : AppColors.fg3),
              ),
              SizedBox(width: S.s8),
            ] else if (icon != null) ...[
              AppIcon(icon!,
                  size: 18, color: accent ? AppColors.accent : AppColors.fg3),
              SizedBox(width: S.s12),
            ],
            if (hasValue)
              // Not Flexible: a loose flex share would strand the value mid-row.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 13, color: labelColor)),
              )
            else
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 13, color: labelColor)),
              ),
            if (hasValue)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: S.s8),
                  child: Text(value!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: sans(13, color: AppColors.fg3)),
                ),
              ),
            if (onTap != null)
              AppIcon('chevron-right', size: 14, color: AppColors.fg4),
          ]),
        ),
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  const _DangerRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 48 : 34),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: S.s12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('trash', size: 16, color: AppColors.danger),
                SizedBox(width: S.s8),
                Text(label,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.label, color: AppColors.danger)),
              ]),
            ),
          ),
        ),
      );
}

class _LongPressRow extends StatelessWidget {
  const _LongPressRow({required this.child, this.onLongPress});

  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: child,
      );
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
        onClose: kMobile ? null : nav?.close,
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

  @override
  bool get opaque => false;

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
      title == null
          ? builder(context)
          : _NestedPage(
              title: title!,
              builder: builder,
              actions: actions,
              scroll: scroll);

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
// Phone sheet route and desktop dialog
// ---------------------------------------------------------------------------

/// A non-opaque full-height route: the chat stays visible under a 30px blur
/// and a dark tint, and the sheet slides up on [sheetMotion].
class _InfoSheetRoute extends PageRoute<void> {
  _InfoSheetRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      sheetMotion.duration ?? const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration =>
      sheetMotion.reverseDuration ?? const Duration(milliseconds: 220);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
        parent: animation,
        curve: sheetMotion.curve ?? Curves.easeOutCubic,
        reverseCurve: sheetMotion.reverseCurve ?? Curves.easeOutCubic.flipped);
    if (reduceMotion(context)) {
      return FadeTransition(opacity: curved, child: child);
    }
    return SlideTransition(
      position:
          Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
      child: child,
    );
  }
}

/// Frosted chat backdrop plus drag-down dismissal for the phone sheet.
class _PhoneSheet extends StatefulWidget {
  const _PhoneSheet({required this.child});

  final Widget child;

  @override
  State<_PhoneSheet> createState() => _PhoneSheetState();
}

class _PhoneSheetState extends State<_PhoneSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle =
      AnimationController(vsync: this, duration: Motion.base);
  Animation<double>? _settleAnim;
  double _drag = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _settle.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() {
          _settleAnim = null;
          _drag = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _settleBack() {
    if (_drag <= 0) return;
    final from = _drag;
    _settleAnim = Tween(begin: from, end: 0.0)
        .animate(CurvedAnimation(parent: _settle, curve: Motion.exit));
    _settle.forward(from: 0);
  }

  void _dragUpdate(double dy) {
    if (_settle.isAnimating) _settle.stop();
    setState(() {
      _settleAnim = null;
      _dragging = true;
      _drag = (_drag + dy).clamp(0.0, 400.0);
    });
  }

  void _dragEnd(double velocity) {
    setState(() => _dragging = false);
    if (_drag > 96 || velocity > 650) {
      Navigator.of(context).maybePop();
      return;
    }
    _settleBack();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is OverscrollNotification) {
      // Pulling down past the top edge drags the sheet with the finger.
      final pull = -n.overscroll;
      if (pull > 0 && n.metrics.pixels <= 0) {
        _dragUpdate(pull);
        if (_drag > 120) Navigator.of(context).maybePop();
      }
    } else if (n is ScrollEndNotification && !_dragging && _drag > 0) {
      _settleBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final offset = _dragging ? _drag : (_settleAnim?.value ?? 0.0);
    return Stack(children: [
      Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(color: Colors.black.withValues(alpha: 0.3)),
        ),
      ),
      Positioned.fill(
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => setState(() => _dragging = true),
            onVerticalDragUpdate: (d) => _dragUpdate(d.delta.dy),
            onVerticalDragEnd: (d) => _dragEnd(d.primaryVelocity ?? 0),
            onVerticalDragCancel: () {
              setState(() => _dragging = false);
              _settleBack();
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: Transform.translate(
                offset: Offset(0, offset),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

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
        width: 340,
        child: _DesktopPanelSurface(
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

/// Frosted surface2 right panel for desktop use.
class _DesktopPanelSurface extends StatelessWidget {
  const _DesktopPanelSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2.withValues(alpha: 0.88),
              border: Border(left: BorderSide(color: AppColors.border)),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      );
}
