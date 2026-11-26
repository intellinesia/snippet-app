import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chat_scene.dart' show ChatScene;
import '../platform.dart';
import '../theme.dart';
import 'shell_models.dart';
import 'shell_nav.dart' show kPaneMinWidth, kPaneSplitHandleWidth;
import 'shell_pane_view.dart';
import 'shell_rail.dart' show kSidebarWidth;
import '../motion.dart';
import 'session_rail.dart'
    show sessionRailCollapsed, sessionRailFraction;

/// The two-pane desktop body row with drag-and-drop between split panes.
class ShellSplitView extends StatefulWidget {
  const ShellSplitView({
    super.key,
    required this.sidebar,
    this.sidebarHidden = false,
    this.sidebarWidth = kSidebarWidth,
    this.onSidebarResize,
    this.onSidebarResizeEnd,
    this.onSidebarReset,
    this.sidebarHeader,
    this.sidebarTop,
    this.mainHeader,
    this.sidebarFooter,
    this.tabOwnsStrip,
    this.statusBar,
    this.leftTakeover,
    this.leftStripAfter,
    this.leftStripTrailing,
    required this.paneWidth,
    required this.leftCollapsed,
    required this.rightCollapsed,
    required this.leftTabs,
    required this.rightTabs,
    required this.readouts,
    required this.activeKey,
    required this.focusedPane,
    required this.statusForTab,
    required this.canCloseTab,
    required this.tabBodyBuilder,
    required this.readoutBodyBuilder,
    required this.fallbackBuilder,
    this.rightPanel,
    this.panelHostsReadouts = false,
    this.hideRight = false,
    required this.onPaneResize,
    required this.onExpandPane,
    required this.onMoveTab,
    required this.onMoveReadout,
    required this.onActivateTab,
    required this.onActivateReadout,
    required this.onDismissTab,
    required this.onCloseReadout,
    this.onFocusPane,
    this.hostFor,
    this.hostInset,
  });

  final Widget sidebar;
  final bool sidebarHidden;
  final double sidebarWidth;
  final ValueChanged<double>? onSidebarResize;
  final VoidCallback? onSidebarResizeEnd;
  final VoidCallback? onSidebarReset;
  final Widget? sidebarHeader;
  final Widget? sidebarTop;
  final Widget? mainHeader;

  /// Pinned below the sidebar body (the 30 pt footer band).
  final Widget? sidebarFooter;

  /// A left-pane tab whose own header row lists the pane's tabs; with it
  /// shown the separate strip stays hidden.
  final bool Function(ShellTab tab)? tabOwnsStrip;

  /// Full-width band under the sidebar and centre columns (desktop only).
  final Widget? statusBar;

  /// Shown over the left pane's body (its tabs stay alive underneath).
  final Widget? leftTakeover;

  /// A session's pane row: the "+" after the chips and the tools at the right.
  /// Setting the trailing tools keeps the strip up even for the chat alone.
  final Widget? leftStripAfter;
  final Widget Function(double width)? leftStripTrailing;
  final double paneWidth;
  final bool leftCollapsed;
  final bool rightCollapsed;
  final List<ShellTab> leftTabs;
  final List<ShellTab> rightTabs;
  final List<RightTab> readouts;
  final Map<ShellPane, String> activeKey;
  final ShellPane focusedPane;
  final String? Function(ShellTab tab) statusForTab;
  final bool Function(ShellTab tab) canCloseTab;
  final Widget Function(ShellTab tab, bool primary, bool visible)
      tabBodyBuilder;
  final Widget Function(RightTab readout) readoutBodyBuilder;
  final Widget Function(ShellPane pane) fallbackBuilder;
  final Widget? rightPanel;
  final bool panelHostsReadouts;
  final bool hideRight;
  final ValueChanged<double> onPaneResize;
  final ValueChanged<ShellPane> onExpandPane;
  final void Function(ShellPane pane, ShellTab tab) onMoveTab;
  final void Function(ShellPane pane, RightTab readout) onMoveReadout;
  final void Function(ShellPane pane, ShellTab tab) onActivateTab;
  final void Function(ShellPane pane, RightTab readout) onActivateReadout;
  final void Function(ShellPane pane, ShellTab tab) onDismissTab;
  final ValueChanged<RightTab> onCloseReadout;
  final ValueChanged<ShellPane>? onFocusPane;

  /// Desktop: the session tab kept showing under an inner tab, so its panel stays.
  final ShellTab? Function(ShellTab tab)? hostFor;

  /// Width of the host's panel at a pane width; the inner tab stops at its edge.
  final double Function(ShellTab host, double width)? hostInset;

  @override
  State<ShellSplitView> createState() => _ShellSplitViewState();
}

class _ShellSplitViewState extends State<ShellSplitView>
    with SingleTickerProviderStateMixin {
  // Reveals the right pane; it stays mounted while sliding shut.
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: Motion.base);
  late final CurvedAnimation _revealCurve = CurvedAnimation(
      parent: _reveal, curve: Motion.enter, reverseCurve: Motion.exit);
  bool _revealInit = false;
  Widget? _lastRight;

  @override
  void initState() {
    super.initState();
    ChatScene.instance.addListener(_onScene);
  }

  void _onScene() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ChatScene.instance.removeListener(_onScene);
    _revealCurve.dispose();
    _reveal.dispose();
    super.dispose();
  }

  Widget _rightReveal(bool show, Widget Function() build) {
    if (!_revealInit) {
      _revealInit = true;
      _reveal.value = show ? 1 : 0;
    }
    if (show) {
      _lastRight = build();
      if (_reveal.status != AnimationStatus.completed &&
          _reveal.status != AnimationStatus.forward) {
        _reveal.duration = Motion.base;
        _reveal.forward();
      }
    } else if (_reveal.value > 0 && _reveal.status != AnimationStatus.reverse) {
      _reveal.reverseDuration = Motion.close;
      _reveal.reverse().whenComplete(() {
        if (mounted && _reveal.value == 0) setState(() => _lastRight = null);
      });
    }
    final child = _lastRight;
    if (child == null || (!show && _reveal.value == 0)) {
      return const SizedBox.shrink();
    }
    if (reduceMotion(context)) return show ? child : const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _revealCurve,
      builder: (_, c) => ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: _revealCurve.value,
          child: Opacity(opacity: _revealCurve.value.clamp(0.0, 1.0), child: c),
        ),
      ),
      child: child,
    );
  }

  final _filesTab = RightTab.panel(RightPanel.files);

  ShellPane? _dragOverPane;
  bool _dragActive = false;

  ShellPane? _dragOriginOf(Object? data) {
    if (data is ShellTab) return data.pane;
    if (data is RightTab) return data.pane;
    return null;
  }

  Widget _dropOn(ShellPane p, Widget child) => DragTarget<Object>(
        onWillAcceptWithDetails: (d) => _dragOriginOf(d.data) != p,
        onAcceptWithDetails: (d) {
          setState(() => _dragOverPane = null);
          final data = d.data;
          if (data is ShellTab) {
            widget.onMoveTab(p, data);
          } else if (data is RightTab) {
            widget.onMoveReadout(p, data);
          }
        },
        onLeave: (_) {
          if (_dragOverPane == p) setState(() => _dragOverPane = null);
        },
        onMove: (d) {
          if (_dragOriginOf(d.data) != p && _dragOverPane != p) {
            setState(() => _dragOverPane = p);
          }
        },
        builder: (_, __, ___) => child,
      );

  Widget _paneView(ShellPane p, {bool roundRight = false}) {
    final list = p == ShellPane.left ? widget.leftTabs : widget.rightTabs;
    final pinned = p == ShellPane.right && widget.rightPanel != null;
    final hosted = pinned && widget.panelHostsReadouts;
    final readouts = [
      if (pinned) _filesTab,
      if (!hosted)
        for (final r in widget.readouts)
          if (r.pane == p) r
    ];
    var key = widget.activeKey[p];
    if (hosted && !list.any((t) => t.key == key)) key = _filesTab.key;

    final selectedTab = list.where((t) => t.key == key).firstOrNull;
    RightTab? selectedReadout;
    for (final r in readouts) {
      if (r.key == key) selectedReadout = r;
    }
    final shownTab = selectedTab ??
        (selectedReadout == null && list.isNotEmpty ? list.first : null);
    final shownReadout = selectedReadout ??
        (shownTab == null && readouts.isNotEmpty ? readouts.first : null);

    Widget content;
    if (list.isEmpty && readouts.isEmpty) {
      content = widget.fallbackBuilder(p);
    } else {
      final host = shownTab == null ? null : widget.hostFor?.call(shownTab);
      Widget body(ShellTab t) {
        final hosted = host != null && t == shownTab;
        final b = Offstage(
          offstage: t != shownTab && t != host,
          child: TabEnter(
            active: t == shownTab || t == host,
            child: widget.tabBodyBuilder(
              t,
              t == shownTab && widget.focusedPane == p,
              t == shownTab || t == host,
            ),
          ),
        );
        // Same tree shape hosted or not, so a tab keeps its state.
        return ListenableBuilder(
          key: ValueKey('tab-${t.key}'),
          listenable:
              Listenable.merge([sessionRailCollapsed, sessionRailFraction]),
          builder: (_, __) => LayoutBuilder(
            builder: (_, box) => Padding(
              padding: EdgeInsets.only(
                  right: hosted
                      ? widget.hostInset?.call(host, box.maxWidth) ?? 0
                      : 0),
              child: ColoredBox(
                  color: hosted ? AppColors.panelBg : Colors.transparent,
                  child: b),
            ),
          ),
        );
      }

      content = Stack(children: [
        // The host paints first so the inner tab sits over its chat column.
        if (host != null && list.contains(host)) body(host),
        for (final t in list)
          if (t != host) body(t),
        for (final readout in readouts)
          Offstage(
            key: ValueKey(readout.key),
            offstage: readout != shownReadout,
            child: TabEnter(
              active: readout == shownReadout,
              child: readout == _filesTab
                  ? widget.rightPanel!
                  : widget.readoutBodyBuilder(readout),
            ),
          ),
      ]);
    }

    if (p == ShellPane.left && widget.leftTakeover != null) {
      content = Stack(children: [
        Offstage(child: content),
        Positioned.fill(child: widget.leftTakeover!),
      ]);
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onFocusPane?.call(p),
      child: PaneSurface(
        pane: p,
        roundRight: roundRight,
        droppable: _dragOverPane == p,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A lone chat has no inner strip (C3): its header carries + and
            // the session panel toggle.
            if (list.length + readouts.length > 1 &&
                !(p == ShellPane.left &&
                    shownTab != null &&
                    (widget.tabOwnsStrip?.call(shownTab) ?? false)) &&
                (p == ShellPane.right
                    ? list.isNotEmpty || readouts.any((r) => r != _filesTab)
                    : true))
              PaneStrip(
                afterTabs: p == ShellPane.left ? widget.leftStripAfter : null,
                trailing: p == ShellPane.left ? widget.leftStripTrailing : null,
                pane: p,
                tabs: list,
                readouts: readouts,
                activeKey: shownTab?.key ?? shownReadout?.key,
                statusForTab: widget.statusForTab,
                canDismissTab: (t) => widget.canCloseTab(t) || t.isTerminal,
                onActivateTab: (t) => widget.onActivateTab(p, t),
                onDismissTab: (t) => widget.onDismissTab(p, t),
                onActivateReadout: (r) => widget.onActivateReadout(p, r),
                onCloseReadout: widget.onCloseReadout,
                onDragStarted: () => setState(() => _dragActive = true),
                onDragEnd: (_) {
                  if (_dragActive || _dragOverPane != null) {
                    setState(() {
                      _dragActive = false;
                      _dragOverPane = null;
                    });
                  }
                },
              ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final showRight = !widget.hideRight &&
        (_dragActive ||
            widget.rightPanel != null ||
            (!widget.rightCollapsed &&
                (widget.rightTabs.isNotEmpty ||
                    (!widget.panelHostsReadouts &&
                        widget.readouts
                            .any((r) => r.pane == ShellPane.right)))));
    final showLeft = !(widget.leftCollapsed && widget.leftTabs.isNotEmpty);
    final centreWidth = MediaQuery.sizeOf(context).width -
        (widget.sidebarHidden ? 0 : widget.sidebarWidth);
    // Both panes need their minimum width; the fixed right pane must not eat the left.
    final maxPaneWidth = math.max(kPaneMinWidth,
        centreWidth - kPaneMinWidth - kPaneSplitHandleWidth);

    final body = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!widget.sidebarHidden)
          SizedBox(
            width: widget.sidebarWidth,
            child: Stack(children: [
              DecoratedBox(
                key: const ValueKey('shell-sidebar-column'),
                // One hairline on the right edge separates it from the pane.
                decoration: BoxDecoration(color: AppColors.windowChrome),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.sidebarTop != null) widget.sidebarTop!,
                    if (widget.sidebarHeader != null) widget.sidebarHeader!,
                    // Capy: the footer tools share the sidebar's icon row,
                    // pinned to its right end.
                    Expanded(
                      child: widget.sidebarFooter == null
                          ? widget.sidebar
                          : Stack(children: [
                              Positioned.fill(child: widget.sidebar),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                height: 44,
                                child: widget.sidebarFooter!,
                              ),
                            ]),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 6,
                child: _SidebarResizeHandle(
                  key: const ValueKey('sidebar-resize-handle'),
                  onResize: widget.onSidebarResize,
                  onResizeEnd: widget.onSidebarResizeEnd,
                  onReset: widget.onSidebarReset,
                ),
              ),
            ]),
          ),
        Expanded(
          // The centre column is the reading surface: strip and panes on bg.
          child: ColoredBox(
              color: kMobile ? Colors.transparent : AppColors.windowChrome,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.mainHeader != null) widget.mainHeader!,
                    Expanded(
                      child: _panel(
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showLeft)
                                  Expanded(
                                    child: _dropOn(
                                      ShellPane.left,
                                      _paneView(ShellPane.left,
                                          roundRight: !showRight),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: CollapsedPaneStub(
                                      pane: ShellPane.left,
                                      onExpand: () =>
                                          widget.onExpandPane(ShellPane.left),
                                    ),
                                  ),
                                _rightReveal(
                                    showRight,
                                    () => Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              PaneResizeHandle(
                                                joinBaseline: showLeft,
                                                onResize: widget.onPaneResize,
                                              ),
                                              SizedBox(
                                                width: widget.paneWidth.clamp(
                                                    kPaneMinWidth,
                                                    maxPaneWidth),
                                                child: _dropOn(
                                                  ShellPane.right,
                                                  _paneView(ShellPane.right,
                                                      roundRight: true),
                                                ),
                                              ),
                                            ])),
                              ])),
                    ),
                  ])),
        ),
      ]);
    if (kMobile || widget.statusBar == null) return Expanded(child: body);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: body),
        widget.statusBar!,
      ]),
    );
  }

  /// Desktop panes sit in one inset panel on the chrome, rounded at the
  /// top left where it meets the sidebar and tab strip.
  Widget _panel(Widget child) {
    if (kMobile) return child;
    final radius = widget.sidebarHidden
        ? BorderRadius.zero
        : BorderRadius.only(topLeft: Radius.circular(R.of(12)));
    return DecoratedBox(
      key: const ValueKey('shell-panes'),
      decoration: BoxDecoration(
        color: AppColors.panelFill,
        borderRadius: radius,
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

class _SidebarResizeHandle extends StatefulWidget {
  const _SidebarResizeHandle({
    super.key,
    this.onResize,
    this.onResizeEnd,
    this.onReset,
  });

  final ValueChanged<double>? onResize;
  final VoidCallback? onResizeEnd;
  final VoidCallback? onReset;

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final divider = Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 1,
        height: double.infinity,
        child: ColoredBox(
          color: _hover ? AppColors.border2 : Colors.transparent,
        ),
      ),
    );
    if (widget.onResize == null && widget.onReset == null) {
      return IgnorePointer(child: divider);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: widget.onResize == null
            ? null
            : (d) => widget.onResize!(d.delta.dx),
        onHorizontalDragEnd:
            widget.onResizeEnd == null ? null : (_) => widget.onResizeEnd!(),
        onHorizontalDragCancel: widget.onResizeEnd,
        onDoubleTap: widget.onReset,
        child: divider,
      ),
    );
  }
}
