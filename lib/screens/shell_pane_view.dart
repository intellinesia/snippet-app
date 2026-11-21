import 'package:flutter/material.dart';

import '../desktop_look.dart';
import '../chat_scene.dart';
import '../api.dart';
import '../shell_panel.dart';
import '../media_views.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../tool_sheet.dart';
import '../widgets.dart';
import 'agent_view_mode.dart';
import 'mission_control/coordination_agent_detail.dart';
import 'session.dart' show SessionScreen;
import 'shell_models.dart';
import 'shell_nav.dart';
import 'shell_window_bar.dart';
import '../tap_detector.dart';

/// The container surface for a desktop split pane with corner rounding and drop highlight.
class PaneSurface extends StatelessWidget {
  final ShellPane pane;
  final Widget child;
  final bool droppable;
  final bool roundRight;

  const PaneSurface({
    super.key,
    required this.pane,
    required this.child,
    this.droppable = false,
    this.roundRight = false,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final scene = ChatScene.instance;
    return ListenableBuilder(
      listenable: scene,
      builder: (context, _) => _surface(context, scene.active && !kMobile),
    );
  }

  Widget _surface(BuildContext context, bool clear) {
    return ClipRect(
      child: ColoredBox(
        color: clear || !kMobile
            ? Colors.transparent
            : pane == ShellPane.right
                ? AppColors.windowBg
                : readingBg,
        child: Stack(fit: StackFit.expand, children: [
          if (pane != ShellPane.right && !kMobile)
            const Positioned.fill(child: ChatWallpaper()),
          pane == ShellPane.right && !kMobile
              ? Theme(
                  data: Theme.of(context)
                      .copyWith(scaffoldBackgroundColor: Colors.transparent),
                  child: child)
              : child,
          if (droppable)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.accent, width: kPaneActiveStroke),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Affordance to re-open a collapsed pane.
class CollapsedPaneStub extends StatelessWidget {
  final ShellPane pane;
  final VoidCallback onExpand;

  const CollapsedPaneStub({
    super.key,
    required this.pane,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconBtn(
        'chevron-right',
        size: 28,
        iconSize: 14,
        tooltip: 'Show pane',
        onTap: onExpand,
      ),
    );
  }
}

/// Placeholder displayed when a pane has no active tabs.
class EmptyPaneHint extends StatelessWidget {
  final String message;

  const EmptyPaneHint({
    super.key,
    this.message = 'Drag a tab here, or open a terminal from the sidebar.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(S.s24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TS.meta(),
        ),
      ),
    );
  }
}

/// The single shared draggable divider between the two panes.
class PaneResizeHandle extends StatefulWidget {
  final bool joinBaseline;
  final void Function(double deltaDx) onResize;

  const PaneResizeHandle({
    super.key,
    this.joinBaseline = false,
    required this.onResize,
  });

  @override
  State<PaneResizeHandle> createState() => _PaneResizeHandleState();
}

class _PaneResizeHandleState extends State<PaneResizeHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kPaneSplitHandleWidth,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // On a fill like the sidebar's border; bare, the wallpaper shows through.
          if (kMobile)
            Positioned.fill(child: ColoredBox(color: AppColors.windowBg)),
          Positioned.fill(
            child: ColoredBox(
              color: _hover
                  ? kPaneSeamHoverColor
                  : kMobile
                      ? AppColors.line.withValues(alpha: 0.65)
                      : AppColors.fg1.withValues(alpha: 0.07),
            ),
          ),
          // Expanded invisible hit target for effortless grab & hover
          Positioned(
            top: 0,
            bottom: 0,
            left: -4,
            right: -4,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) => widget.onResize(d.delta.dx),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drag feedback ghost for a session readout chip.
class ReadoutDragFeedback extends StatelessWidget {
  final RightTab tab;

  const ReadoutDragFeedback({super.key, required this.tab});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: S.of(10)),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(tab.icon, size: 13, color: AppColors.accent),
          SizedBox(width: S.of(7)),
          Text(tab.label, style: sans(13, color: AppColors.fg1)),
        ]),
      ),
    );
  }
}

/// One readout tab (Lanes / Checkpoints / Usage / an agent) in a pane strip.
class ReadoutChip extends StatelessWidget {
  final ShellPane pane;
  final RightTab tab;
  final bool active;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails) onDragEnd;

  bool get pinned => tab.panel == RightPanel.files;

  const ReadoutChip({
    super.key,
    required this.pane,
    required this.tab,
    required this.active,
    required this.width,
    required this.onTap,
    required this.onClose,
    required this.onDragStarted,
    required this.onDragEnd,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chip = TapDetector(
      onTap: onTap,
      child: SizedBox(
        width: compact ? null : width,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: S.s2, vertical: compact ? S.s6 : S.of(7)),
          child: Tactile(
            radius: BorderRadius.circular(compact ? R.of(7) : R.card),
            enabled: active,
            child: AnimatedContainer(
          duration: Motion.quick,
          height: compact ? 26 : 32,
          constraints: compact ? BoxConstraints(maxWidth: width) : null,
          padding: EdgeInsets.fromLTRB(
              compact ? S.of(9) : S.s12, 0, compact ? S.s6 : S.s8, 0),
          decoration: BoxDecoration(
            color: active
                ? (compact ? AppColors.surface3 : AppColors.surface2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(compact ? R.of(7) : R.card),
          ),
          child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                AppIcon(tab.icon,
                    size: compact ? 12 : 14,
                    color: active ? AppColors.fg1 : AppColors.fg3),
                SizedBox(width: compact ? S.s6 : S.s8),
                Flexible(
                  fit: compact ? FlexFit.loose : FlexFit.tight,
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(compact ? 12 : 13,
                        color: active ? AppColors.fg1 : AppColors.fg3),
                  ),
                ),
                if (pinned)
                  SizedBox(width: S.s6)
                else ...[
                  SizedBox(width: S.s6),
                  TapDetector(
                    onTap: onClose,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.all(S.of(3)),
                      child: AppIcon('x', size: 11, color: AppColors.fg4),
                    ),
                  ),
                ],
              ]),
        ),
          ),
        ),
      ),
    );

    if (pinned) return chip;
    if (kMobile) {
      return LongPressDraggable<RightTab>(
        data: tab,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: ReadoutDragFeedback(tab: tab),
        childWhenDragging: Opacity(opacity: 0.4, child: chip),
        onDragStarted: onDragStarted,
        onDragEnd: onDragEnd,
        child: chip,
      );
    }
    return Draggable<RightTab>(
      data: tab,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: ReadoutDragFeedback(tab: tab),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      child: chip,
    );
  }
}

/// One docked shell tab chip in a pane strip.
class PaneTabChip extends StatelessWidget {
  final ShellPane pane;
  final ShellTab tab;
  final bool active;
  final double width;
  final String? status;
  final bool canDismiss;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails) onDragEnd;

  const PaneTabChip({
    super.key,
    required this.pane,
    required this.tab,
    required this.active,
    required this.width,
    required this.status,
    required this.canDismiss,
    required this.onTap,
    required this.onDismiss,
    required this.onDragStarted,
    required this.onDragEnd,
    this.compact = false,
  });

  final bool compact;

  /// The window tab already names the session, so its own chip reads "Chat".
  bool get chat => !kMobile && tab.isSessionChat;

  @override
  Widget build(BuildContext context) {
    final chip = TapDetector(
      onTap: onTap,
      child: SizedBox(
        width: compact ? null : width,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: S.s2, vertical: compact ? S.s6 : S.of(7)),
          child: Tactile(
            radius: BorderRadius.circular(compact ? R.of(7) : R.card),
            enabled: active,
            child: AnimatedContainer(
          duration: Motion.quick,
          height: compact ? 26 : 32,
          constraints: compact ? BoxConstraints(maxWidth: width) : null,
          padding: EdgeInsets.fromLTRB(
              compact ? S.of(9) : S.s12, 0, compact ? S.s6 : S.s8, 0),
          decoration: BoxDecoration(
            color: active
                ? (compact ? AppColors.surface3 : AppColors.surface2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(compact ? R.of(7) : R.card),
          ),
          child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                SessionStateIcon(
                  status: status,
                  icon: chat ? 'chat' : tabIconKind(tab),
                  size: compact ? 12 : 14,
                ),
                SizedBox(width: compact ? S.s6 : S.s8),
                Flexible(
                  fit: compact ? FlexFit.loose : FlexFit.tight,
                  child: Text(
                    chat
                        ? 'Chat'
                        : tab.title.isEmpty
                            ? '(untitled)'
                            : tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(compact ? 12 : 13,
                        color: active ? AppColors.fg1 : AppColors.fg3),
                  ),
                ),
                if (canDismiss) ...[
                  SizedBox(width: S.s6),
                  TapDetector(
                    onTap: onDismiss,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.all(S.of(3)),
                      child: AppIcon('x', size: 11, color: AppColors.fg4),
                    ),
                  ),
                ],
              ]),
        ),
          ),
        ),
      ),
    );

    if (kMobile) {
      return LongPressDraggable<ShellTab>(
        data: tab,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: TabDragFeedback(tab: tab),
        childWhenDragging: Opacity(opacity: 0.4, child: chip),
        onDragStarted: onDragStarted,
        onDragEnd: onDragEnd,
        child: chip,
      );
    }
    return Draggable<ShellTab>(
      data: tab,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: TabDragFeedback(tab: tab),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      child: chip,
    );
  }
}

/// The tab strip for a pane, containing both docked ShellTabs and RightTabs.
class PaneStrip extends StatelessWidget {
  final ShellPane pane;
  final List<ShellTab> tabs;
  final List<RightTab> readouts;
  final String? activeKey;
  final String? Function(ShellTab) statusForTab;
  final bool Function(ShellTab) canDismissTab;
  final void Function(ShellTab) onActivateTab;
  final void Function(ShellTab) onDismissTab;
  final void Function(RightTab) onActivateReadout;
  final void Function(RightTab) onCloseReadout;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails) onDragEnd;

  /// Sits right after the last chip (the "+" button).
  final Widget? afterTabs;

  /// Pinned at the strip's right end (session actions, panel toggle); gets the
  /// strip's width so it can pick docked or floating.
  final Widget Function(double width)? trailing;

  const PaneStrip({
    super.key,
    required this.pane,
    required this.tabs,
    required this.readouts,
    required this.activeKey,
    required this.statusForTab,
    required this.canDismissTab,
    required this.onActivateTab,
    required this.onDismissTab,
    required this.onActivateReadout,
    required this.onCloseReadout,
    required this.onDragStarted,
    required this.onDragEnd,
    this.afterTabs,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final count = tabs.length + readouts.length;
    final compact = !kMobile;
    return Container(
      height: compact ? 38 : 46,
      // Desktop: a hairline under the tabs, as in the reference.
      decoration: BoxDecoration(
        color: kMobile ? AppColors.pageCanvas : Colors.transparent,
        border: kMobile
            ? null
            : Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: LayoutBuilder(builder: (context, outer) {
        final list = _chips(count, compact);
        final tail = trailing;
        if (tail == null) return list;
        // The trailing builder owns its end padding; the docked panel's strip runs to the edge.
        return Row(children: [
          Expanded(child: list),
          tail(outer.maxWidth),
        ]);
      }),
    );
  }

  Widget _chips(int count, bool compact) {
    final extra = afterTabs == null ? 0 : 1;
    return Stack(fit: StackFit.expand, children: [
      LayoutBuilder(builder: (context, c) {
        final fit = kPaneTabWidth(c.maxWidth - 12, count);
        final w = compact && fit > 136 ? 136.0 : fit;
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: S.s6),
          itemCount: count + extra,
          separatorBuilder: (_, __) => const SizedBox.shrink(),
          itemBuilder: (_, i) {
            if (i >= count) return Center(child: afterTabs);
            if (i < tabs.length) {
              final t = tabs[i];
              return PaneTabChip(
                pane: pane,
                tab: t,
                active: t.key == activeKey,
                width: w,
                status: statusForTab(t),
                canDismiss: canDismissTab(t),
                onTap: () => onActivateTab(t),
                onDismiss: () => onDismissTab(t),
                onDragStarted: onDragStarted,
                onDragEnd: onDragEnd,
                compact: compact,
              );
            }
            final r = readouts[i - tabs.length];
            return ReadoutChip(
              pane: pane,
              tab: r,
              active: r.key == activeKey,
              width: w,
              onTap: () => onActivateReadout(r),
              onClose: () => onCloseReadout(r),
              onDragStarted: onDragStarted,
              onDragEnd: onDragEnd,
              compact: compact,
            );
          },
        );
      }),
    ]);
  }
}

/// Renders the body content of a RightTab (Lanes, Tasks, Checkpoints, Recurring, or Agent detail).
class RightTabBody extends StatelessWidget {
  final RightTab tab;
  final HarnessState? state;
  final MacSessionControls? controls;
  final DaemonClient? client;
  final String? activeSessionId;
  final VoidCallback? onClose;
  final void Function(String path, String name)? onOpenFile;
  final Widget? deskTrailing;
  final VoidCallback? onDeskInfo;

  const RightTabBody({
    super.key,
    required this.tab,
    required this.state,
    required this.controls,
    required this.client,
    required this.activeSessionId,
    this.onClose,
    this.onOpenFile,
    this.deskTrailing,
    this.onDeskInfo,
  });

  @override
  Widget build(BuildContext context) {
    final request = tab.request;
    if (request != null) {
      return ShellPanelBody(
          key: ValueKey(request.key),
          request: request,
          onClose: onClose ?? () {});
    }
    final tools = tab.tools;
    if (tools != null) {
      final view = ToolBatchView(
        key: ObjectKey(tools),
        batch: tools,
        onClose: onClose ?? () {},
        docked: true,
      );
      final c = client;
      return c == null
          ? view
          : DaemonScope(client: c, onOpenFile: onOpenFile, child: view);
    }
    final agent = tab.agent;
    if (agent != null) {
      final chat = CoordinationAgentDetail(
        agent: agent,
        client: client,
        embedded: true,
        // Desktop: no stage; the thread opens with a scrolling agent head.
        tabHeader: kMobile,
        deskTrailing: deskTrailing,
        onDeskInfo: onDeskInfo,
      );
      final c = client;
      if (c == null) return chat;
      // Work is the agent's desk session in place: one page, two views.
      return ValueListenableBuilder<Set<String>>(
        valueListenable: agentWorkView,
        builder: (_, work, __) => work.contains(agent.id)
            ? SessionScreen(
                key: ValueKey('agent-work-${agent.id}'),
                client: c,
                sessionId: 'inbox-${agent.id}',
                title: agent.displayName,
                embedded: true,
              )
            : chat,
      );
    }
    return const SizedBox.shrink();
  }
}
