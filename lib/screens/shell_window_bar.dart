import 'package:flutter/gestures.dart';
import '../desktop_look.dart';
import 'package:flutter/material.dart';

import '../chat/agent_cluster.dart';
import '../mochi.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_models.dart';
import 'shell_nav.dart';
import '../tap_detector.dart';

/// Top-level workspace tab chip that appears when dragging a tab.
class TabDragFeedback extends StatelessWidget {
  final ShellTab tab;

  const TabDragFeedback({super.key, required this.tab});

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
          AppIcon(tabIconKind(tab), size: 13, color: AppColors.accent),
          SizedBox(width: S.of(7)),
          Text(
            tab.title.isEmpty ? '(untitled)' : tab.title,
            style: sans(13, color: AppColors.fg1),
          ),
        ]),
      ),
    );
  }
}

/// A top-level workspace tab: fixed width, close button on hover or when active.
class TopWorkspaceTabChip extends StatefulWidget {
  final ShellTab tab;
  final bool isActive;
  final String? status;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final GlobalKey? chipKey;
  final String? provider;
  final String? agentId;
  final String? folder;
  final int attentionCount;

  /// Width of a regular tab; Mission Control is always its compact form.
  final double width;

  const TopWorkspaceTabChip({
    super.key,
    required this.tab,
    required this.isActive,
    required this.status,
    required this.canClose,
    required this.onTap,
    this.onClose,
    this.chipKey,
    this.provider,
    this.agentId,
    this.folder,
    this.attentionCount = 0,
    this.width = 168,
  });

  @override
  State<TopWorkspaceTabChip> createState() => _TopWorkspaceTabChipState();
}

class _TopWorkspaceTabChipState extends State<TopWorkspaceTabChip> {
  bool _hover = false;

  Widget _icon(String? status, bool working) {
    final t = widget.tab;
    final active = widget.isActive;
    final groupIds = tabGroupAgentIds(t);
    final hasProvider =
        widget.provider != null && providerLogoAsset(widget.provider) != null;
    if (t.isPrs) return AppIcon('pull-request', size: 13, color: AppColors.ok);
    if (t.isBoard) {
      return AppIcon('list',
          size: 14, color: active ? AppColors.fg2 : AppColors.fg4);
    }
    if (groupIds != null) return AgentCluster(ids: groupIds, size: 17);
    if (widget.agentId != null && widget.agentId!.isNotEmpty) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(R.of(4)),
          child: AgentMochi(widget.agentId!, size: 16));
    }
    if (hasProvider) return ProviderLogo(widget.provider, size: 13);
    return SessionStateIcon(
      status: working ? null : status,
      icon: tabIconKind(t),
      size: 13,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tab;
    final active = widget.isActive;
    final title = t.title.isEmpty ? '(untitled)' : t.title;
    final status = widget.status;
    final needsInput = status == 'waiting_for_input' || status == 'in_review';
    final working = status == 'running' || needsInput;
    final closable = widget.canClose && widget.onClose != null;
    final bg = active
        ? AppColors.surface3
        : (_hover ? AppColors.fg1.withValues(alpha: 0.07) : Colors.transparent);

    Widget cell(Widget child, {required double width}) => MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: TapDetector(
            onTap: widget.onTap,
            child: Tactile(
              radius: BorderRadius.circular(R.of(6)),
              enabled: widget.isActive,
              child: AnimatedContainer(
                key: widget.chipKey,
                duration: Motion.quick,
                curve: const Cubic(.23, 1, .32, 1),
                height: 28,
                width: width,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(R.of(6)),
                ),
                child: child,
              ),
            ),
          ),
        );

    if (t.isMissionControl) {
      return Tooltip(
        message: title,
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: TapDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              key: widget.chipKey,
              duration: Motion.quick,
              curve: const Cubic(.23, 1, .32, 1),
              height: 28,
              padding: EdgeInsets.symmetric(horizontal: S.s8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(R.of(6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AgentMochi('mission-control', size: 18),
                if (widget.attentionCount > 0) ...[
                  SizedBox(width: S.s6),
                  Text('${widget.attentionCount}',
                      style: mono(10.5, color: AppColors.run)),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    final f = widget.folder?.trim();
    final tip = f != null && f.isNotEmpty ? '$title\n$f' : title;
    final showClose = closable && (active || _hover);
    final chip = cell(
      Stack(children: [
        if (working)
          Positioned(
            left: 4,
            top: 11,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: needsInput ? AppColors.accent : AppColors.run,
                  shape: BoxShape.circle),
            ),
          ),
        // Fill the cell so the row centres vertically.
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(S.of(working ? 13 : 10), 0, S.s8, 0),
            child: Row(children: [
              _icon(status, working),
              SizedBox(width: S.of(7)),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5,
                      color: active
                          ? AppColors.fg1
                          : (_hover ? AppColors.fg2 : AppColors.fg3)),
                ),
              ),
              if (closable)
                Opacity(
                  opacity: showClose ? 1 : 0,
                  child: TapDetector(
                    onTap: showClose ? widget.onClose : null,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Center(
                          child: AppIcon('x', size: 11, color: AppColors.fg4)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]),
      width: widget.width,
    );
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 600),
      child: closable
          ? Listener(
              onPointerDown: (e) {
                if ((e.buttons & kMiddleMouseButton) != 0) widget.onClose!();
              },
              child: chip,
            )
          : chip,
    );
  }
}

/// Strip of top-level workspace tabs. Tabs keep a fixed width; the ones that do
/// not fit move into a "+N" menu, with the active tab always kept in view.
class MainTabsStrip extends StatefulWidget {
  final ScrollController? controller;
  final List<ShellTab> tabs;
  final ShellTab? activeTab;
  final String? Function(ShellTab) statusForTab;
  final bool Function(ShellTab) canCloseTab;
  final void Function(ShellTab) onActivateTab;
  final void Function(ShellTab) onCloseTab;
  final VoidCallback onNewSession;
  final GlobalKey Function(String key) chipKeyFor;
  final String? Function(ShellTab)? providerFor;
  final String? Function(ShellTab)? agentFor;
  final String? Function(ShellTab)? folderFor;
  final int mcAttentionCount;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseAll;

  const MainTabsStrip({
    super.key,
    this.controller,
    required this.tabs,
    required this.activeTab,
    required this.statusForTab,
    required this.canCloseTab,
    required this.onActivateTab,
    required this.onCloseTab,
    required this.onNewSession,
    required this.chipKeyFor,
    this.providerFor,
    this.agentFor,
    this.folderFor,
    this.mcAttentionCount = 0,
    this.onCloseOthers,
    this.onCloseAll,
  });

  @override
  State<MainTabsStrip> createState() => _MainTabsStripState();
}

class _MainTabsStripState extends State<MainTabsStrip> {
  static const _maxTab = 180.0;
  static const _minTab = 140.0;
  static const _gap = 2.0;
  final _moreKey = GlobalKey();

  Future<void> _openMore(List<ShellTab> hidden) async {
    final box = _moreKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = MediaQuery.of(context).size;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'tabs',
      barrierColor: Colors.transparent,
      transitionDuration: Motion.press,
      pageBuilder: (ctx, _, __) => Stack(children: [
        Positioned(
          right: (size.width - origin.dx - box.size.width).clamp(10.0, 900.0),
          top: origin.dy + box.size.height + 6,
          width: 320,
          child: _TabOverflowMenu(
            tabs: hidden,
            statusForTab: widget.statusForTab,
            agentFor: widget.agentFor,
            providerFor: widget.providerFor,
            canClose: widget.canCloseTab,
            onActivate: (t) {
              Navigator.of(ctx).pop();
              widget.onActivateTab(t);
            },
            onClose: widget.onCloseTab,
            onCloseOthers: widget.onCloseOthers == null
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    widget.onCloseOthers!();
                  },
            onCloseAll: widget.onCloseAll == null
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    widget.onCloseAll!();
                  },
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mc = widget.tabs.where((t) => t.isMissionControl).toList();
    final rest = widget.tabs.where((t) => !t.isMissionControl).toList();
    return LayoutBuilder(builder: (context, box) {
      const plusW = 28.0 + _gap;
      const moreW = 64.0 + _gap;
      // The MC chip grows with its attention count; budget for it, plus a
      // little slack, so the strip never overruns the bar.
      final count = widget.mcAttentionCount;
      final mcChip = 46.0 + (count > 0 ? 8.0 + 7.0 * '$count'.length : 0);
      final mcW = mc.length * (mcChip + _gap);
      final room = box.maxWidth - mcW - plusW - 6;
      var visibleCount = rest.length;
      var overflow = false;
      if (rest.length * (_minTab + _gap) > room) {
        overflow = true;
        visibleCount = ((room - moreW) / (_minTab + _gap)).floor();
        if (visibleCount < 1) visibleCount = rest.isEmpty ? 0 : 1;
        if (visibleCount > rest.length) visibleCount = rest.length;
      }
      var visible = rest.take(visibleCount).toList();
      var hidden = rest.skip(visibleCount).toList();
      final active = widget.activeTab;
      if (overflow &&
          active != null &&
          hidden.contains(active) &&
          visible.isNotEmpty) {
        final swapped = visible.removeLast();
        visible.add(active);
        hidden = [swapped, ...hidden.where((t) => t != active)];
      }
      final avail = room - (overflow ? moreW : 0);
      final tabW = visible.isEmpty
          ? _maxTab
          : (avail / visible.length - _gap).clamp(_minTab, _maxTab);

      Widget chip(ShellTab t) => Padding(
            padding: const EdgeInsets.only(right: _gap),
            child: Center(
              child: TopWorkspaceTabChip(
                tab: t,
                width: tabW,
                provider: widget.providerFor?.call(t),
                agentId: widget.agentFor?.call(t),
                folder: widget.folderFor?.call(t),
                isActive: t == active,
                status: widget.statusForTab(t),
                canClose: widget.canCloseTab(t),
                onTap: () => widget.onActivateTab(t),
                onClose: () => widget.onCloseTab(t),
                chipKey: widget.chipKeyFor(t.key),
                attentionCount:
                    t.isMissionControl ? widget.mcAttentionCount : 0,
              ),
            ),
          );

      // Widths above are estimates; the tabs clip rather than overrun the bar,
      // and + always stays visible.
      return Row(children: [
        ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: (box.maxWidth - plusW).clamp(0.0, double.infinity)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(children: [
              for (final t in mc) chip(t),
              for (final t in visible) chip(t),
              if (overflow)
                Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: _MoreButton(
                    key: _moreKey,
                    count: hidden.length,
                    onTap: () => _openMore(hidden),
                  ),
                ),
            ]),
          ),
        ),
        Center(
          child: IconBtn(
            'plus',
            size: 28,
            iconSize: 14,
            tooltip: 'New session',
            onTap: widget.onNewSession,
          ),
        ),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('tab-strip-empty-space'),
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.onNewSession,
            child: const SizedBox.expand(),
          ),
        ),
      ]);
    });
  }
}

class _MoreButton extends StatefulWidget {
  const _MoreButton({super.key, required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  State<_MoreButton> createState() => _MoreButtonState();
}

class _MoreButtonState extends State<_MoreButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TapDetector(
        onTap: widget.onTap,
        child: Container(
          height: 28,
          padding: EdgeInsets.symmetric(horizontal: S.s8),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('+${widget.count}', style: sans(12, color: AppColors.fg2)),
            SizedBox(width: S.s4),
            AppIcon('chevron-down', size: 11, color: AppColors.fg3),
          ]),
        ),
      ),
    );
  }
}

class _TabOverflowMenu extends StatefulWidget {
  const _TabOverflowMenu({
    required this.tabs,
    required this.statusForTab,
    required this.agentFor,
    required this.providerFor,
    required this.canClose,
    required this.onActivate,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseAll,
  });
  final List<ShellTab> tabs;
  final String? Function(ShellTab) statusForTab;
  final String? Function(ShellTab)? agentFor;
  final String? Function(ShellTab)? providerFor;
  final bool Function(ShellTab) canClose;
  final void Function(ShellTab) onActivate;
  final void Function(ShellTab) onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseAll;

  @override
  State<_TabOverflowMenu> createState() => _TabOverflowMenuState();
}

class _TabOverflowMenuState extends State<_TabOverflowMenu> {
  final _q = TextEditingController();
  late List<ShellTab> _tabs = widget.tabs;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Widget _action(String label, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 30, right: 8),
          alignment: Alignment.centerLeft,
          child: Text(label, style: sans(12.5, color: AppColors.fg2)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final shown = [
      for (final t in _tabs)
        if (q.isEmpty || t.title.toLowerCase().contains(q)) t,
    ];
    return Material(
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.lg),
        side: BorderSide(color: AppColors.lineStrong),
      ),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .4),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: 32,
            margin: const EdgeInsets.fromLTRB(2, 2, 2, 6),
            padding: EdgeInsets.symmetric(horizontal: S.s8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(children: [
              AppIcon('search', size: 13, color: AppColors.fg4),
              SizedBox(width: S.s8),
              Expanded(
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: sans(12.5, color: AppColors.fg1),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Find a tab',
                    hintStyle: sans(12.5, color: AppColors.fg4),
                  ),
                ),
              ),
            ]),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
              child: Text(
                  '${_tabs.length} more ${_tabs.length == 1 ? 'tab' : 'tabs'}',
                  style: sans(11, weight: W.title, color: AppColors.fg4)),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final t in shown)
                  _OverflowRow(
                    tab: t,
                    status: widget.statusForTab(t),
                    agentId: widget.agentFor?.call(t),
                    provider: widget.providerFor?.call(t),
                    canClose: widget.canClose(t),
                    onTap: () => widget.onActivate(t),
                    onClose: () {
                      widget.onClose(t);
                      setState(() => _tabs = [
                            for (final o in _tabs)
                              if (o != t) o
                          ]);
                      if (_tabs.isEmpty) Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 6),
            color: AppColors.line,
          ),
          _action('Close other tabs', widget.onCloseOthers),
          _action('Close all tabs', widget.onCloseAll),
        ]),
      ),
    );
  }
}

class _OverflowRow extends StatefulWidget {
  const _OverflowRow({
    required this.tab,
    required this.status,
    required this.agentId,
    required this.provider,
    required this.canClose,
    required this.onTap,
    required this.onClose,
  });
  final ShellTab tab;
  final String? status;
  final String? agentId;
  final String? provider;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback onClose;
  @override
  State<_OverflowRow> createState() => _OverflowRowState();
}

class _OverflowRowState extends State<_OverflowRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tab;
    final s = widget.status;
    final asks = s == 'waiting_for_input';
    final working = s == 'running';
    final groupIds = tabGroupAgentIds(t);
    final Widget icon = groupIds != null
        ? AgentCluster(ids: groupIds, size: 16)
        : (widget.agentId != null && widget.agentId!.isNotEmpty)
            ? AgentMochi(widget.agentId!, size: 15)
            : (widget.provider != null &&
                    providerLogoAsset(widget.provider) != null)
                ? ProviderLogo(widget.provider, size: 13)
                : AppIcon(tabIconKind(t), size: 14, color: AppColors.fg3);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TapDetector(
        onTap: widget.onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(children: [
            SizedBox(width: 16, child: Center(child: icon)),
            SizedBox(width: S.of(10)),
            Expanded(
              child: Text(t.title.isEmpty ? '(untitled)' : t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, color: AppColors.fg1)),
            ),
            if (asks)
              Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(R.xs),
                ),
                child:
                    Text('Question', style: sans(11, color: AppColors.accent)),
              )
            else if (working)
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
              ),
            if (widget.canClose && _hover)
              TapDetector(
                onTap: widget.onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: AppIcon('x', size: 12, color: AppColors.fg3),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The complete macOS window title bar with navigation buttons, tabs strip, and utility actions.
class MacWindowBar extends StatelessWidget {
  final bool sidebarHidden;
  final VoidCallback? onToggleSidebar;
  final bool canNavigateBack;
  final bool canNavigateForward;
  final VoidCallback onNavigateBack;
  final VoidCallback onNavigateForward;
  final Widget tabsRow;
  final VoidCallback onOpenSettings;
  final List<Widget> tools;
  final bool reserveWindowControls;

  const MacWindowBar({
    super.key,
    this.sidebarHidden = false,
    this.onToggleSidebar,
    required this.canNavigateBack,
    required this.canNavigateForward,
    required this.onNavigateBack,
    required this.onNavigateForward,
    required this.tabsRow,
    required this.onOpenSettings,
    this.tools = const [],
    this.reserveWindowControls = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 36 under the card's 8 px top inset centres it at 26, with the sidebar.
      height: kMobile ? 44 : 36,
      padding: EdgeInsets.fromLTRB(S.s8, 0, S.of(10), 0),
      decoration: kMobile
          ? BoxDecoration(
              color: AppColors.windowBg,
              border: Border(
                  bottom: BorderSide(
                      color: AppColors.line.withValues(alpha: 0.65))),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (sidebarHidden) ...[
                if (reserveWindowControls) const SizedBox(width: 80),
                if (onToggleSidebar != null)
                  IconBtn('sidebar',
                      size: 28,
                      iconSize: 15,
                      tooltip: kMacOS
                          ? 'Show sidebar (⌘B)'
                          : 'Show sidebar (Ctrl+B)',
                      onTap: onToggleSidebar),
              ],
              IconBtn('chevron-left',
                  size: 28,
                  iconSize: 15,
                  tooltip: 'Back',
                  onTap: canNavigateBack ? onNavigateBack : null),
              IconBtn('chevron-right',
                  size: 28,
                  iconSize: 15,
                  tooltip: 'Forward',
                  onTap: canNavigateForward ? onNavigateForward : null),
              SizedBox(width: S.s4),
            ]),
          ),
          Expanded(
              child: Align(alignment: Alignment.centerLeft, child: tabsRow)),
          SizedBox(width: S.s8),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tool in tools) ...[
                  tool,
                  SizedBox(width: S.s2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

