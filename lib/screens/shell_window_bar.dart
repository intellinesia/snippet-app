import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../chat/agent_cluster.dart';
import '../mochi.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_models.dart';
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
  final bool unread;
  final int attentionCount;

  /// Width of a regular tab; Lead is always its compact form.
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
    this.unread = false,
    this.attentionCount = 0,
    this.width = 168,
  });

  @override
  State<TopWorkspaceTabChip> createState() => _TopWorkspaceTabChipState();
}

class _TopWorkspaceTabChipState extends State<TopWorkspaceTabChip> {
  bool _hover = false;
  bool _focus = false;

  String get _label {
    final t = widget.tab;
    if (t.isHome) return 'Home';
    if (t.isLead) return 'Lead';
    return t.title.isEmpty ? '(untitled)' : t.title;
  }

  Widget _icon() {
    final t = widget.tab;
    final active = widget.isActive;
    final color = active ? AppColors.fg1 : AppColors.fg2;
    final groupIds = tabGroupAgentIds(t);
    final hasProvider =
        widget.provider != null && providerLogoAsset(widget.provider) != null;
    if (t.isHome) return AppIcon('home', size: 12, color: color);
    if (t.isLead) return AgentMochi('lead', size: 16);
    if (t.isPrs) return AppIcon('pull-request', size: 12, color: color);
    if (t.isBoard) return AppIcon('kanban', size: 12, color: color);
    if (groupIds != null) return AgentCluster(ids: groupIds, size: 16);
    if (widget.agentId != null && widget.agentId!.isNotEmpty) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(R.of(3)),
          child: AgentMochi(widget.agentId!, size: 14));
    }
    if (hasProvider) return ProviderLogo(widget.provider, size: 12);
    return AppIcon(tabIconKind(t), size: 12, color: color);
  }

  Widget? _marker() {
    final status = widget.status;
    final needsInput = status == 'waiting_for_input' ||
        status == 'in_review' ||
        (widget.tab.isLead && widget.attentionCount > 0);
    if (needsInput) {
      return Tooltip(
        message: 'Needs you',
        child: Container(
          width: 6,
          height: 6,
          decoration:
              BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
        ),
      );
    }
    if (widget.unread) {
      return Tooltip(
        message: 'Unread',
        child: Container(
          width: 6,
          height: 6,
          decoration:
              BoxDecoration(color: AppColors.fg1, shape: BoxShape.circle),
        ),
      );
    }
    if (status == 'running') {
      return Tooltip(
        message: 'Running',
        child: const Spinner(size: 11),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tab;
    final active = widget.isActive;
    final marker = _marker();
    final closable = widget.canClose && widget.onClose != null;
    final showClose = closable && (active || _hover);
    final folder = widget.folder?.trim();
    final tip = folder != null && folder.isNotEmpty && !t.isHome && !t.isLead
        ? '$_label\n$folder'
        : _label;

    final chip = FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            key: widget.chipKey,
            height: 32,
            width: widget.width,
            child: Stack(children: [
              if ((_hover && !active) || (_focus && !active))
                Positioned(
                  left: 0,
                  right: 0,
                  top: 4,
                  height: 28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _focus ? AppColors.surface3 : AppColors.surface2,
                      borderRadius: BorderRadius.circular(R.of(6)),
                    ),
                  ),
                ),
              if (_focus)
                Positioned(
                  left: 0,
                  top: 2,
                  bottom: 2,
                  width: 2,
                  child: ColoredBox(color: AppColors.fg1),
                ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                  child: Row(children: [
                    SizedBox(width: 12, child: Center(child: _icon())),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12,
                            weight: active ? W.label : W.body,
                            color: active ? AppColors.fg1 : AppColors.fg2),
                      ),
                    ),
                    if (marker != null) ...[
                      const SizedBox(width: 2),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(child: marker),
                      ),
                    ],
                    if (closable)
                      Opacity(
                        opacity: showClose ? 1 : 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: showClose ? widget.onClose : null,
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: Center(
                              child:
                                  AppIcon('x', size: 10, color: AppColors.fg3),
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 6),
                  ]),
                ),
              ),
              if (active)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 2,
                  child: ColoredBox(color: AppColors.fg1),
                ),
            ]),
          ),
        ),
      ),
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
  final bool Function(ShellTab)? unreadFor;
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
    this.unreadFor,
    this.folderFor,
    this.mcAttentionCount = 0,
    this.onCloseOthers,
    this.onCloseAll,
  });

  @override
  State<MainTabsStrip> createState() => _MainTabsStripState();
}

class _MainTabsStripState extends State<MainTabsStrip> {
  static const _gap = 2.0;
  final _moreKey = GlobalKey();
  // Tabs closed but still shrinking out, with the slot they held.
  final _leaving = <String, (ShellTab, int)>{};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ready = true);
  }

  @override
  void didUpdateWidget(MainTabsStrip old) {
    super.didUpdateWidget(old);
    final now = {for (final t in widget.tabs) t.key};
    final before = old.tabs.where((t) => !t.isLead).toList();
    for (var i = 0; i < before.length; i++) {
      final t = before[i];
      if (!now.contains(t.key)) _leaving[t.key] = (t, i);
    }
    _leaving.removeWhere((k, _) => now.contains(k));
  }

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

  double _tabWidth(BuildContext context, ShellTab t) {
    final title = t.isHome
        ? 'Home'
        : t.isLead
            ? 'Lead'
            : (t.title.isEmpty ? '(untitled)' : t.title);
    final painter = TextPainter(
      text: TextSpan(text: title, style: sans(12, weight: W.label)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return (painter.width + 62).clamp(112.0, 210.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    int fixedRank(ShellTab t) => t.isHome ? 0 : 1;
    final fixed = widget.tabs.where((t) => t.isLead || t.isHome).toList()
      ..sort((a, b) => fixedRank(a).compareTo(fixedRank(b)));
    final rest = widget.tabs.where((t) => !t.isLead && !t.isHome).toList();
    return LayoutBuilder(builder: (context, box) {
      const plusW = 28.0 + _gap;
      const moreW = 40.0 + _gap;
      final naturalWidths = <String, double>{
        for (final t in widget.tabs) t.key: _tabWidth(context, t),
      };
      final fixedW = fixed.fold<double>(
          0, (sum, t) => sum + (naturalWidths[t.key] ?? 168) + _gap);
      final room = box.maxWidth - fixedW - plusW - 6;

      double naturalTotal() => rest.fold<double>(
          0, (sum, t) => sum + (naturalWidths[t.key] ?? 168) + _gap);

      Map<String, double> widthsFor(double available) {
        final natural = naturalTotal();
        if (rest.isEmpty || natural <= available) return naturalWidths;
        final widthSum = rest.fold<double>(
            0, (sum, t) => sum + (naturalWidths[t.key] ?? 168));
        final gapSum = rest.length * _gap;
        final scale = ((available - gapSum) / widthSum).clamp(0.0, 1.0);
        return {
          ...naturalWidths,
          for (final t in rest)
            t.key: ((naturalWidths[t.key] ?? 168) * scale)
                .clamp(112.0, naturalWidths[t.key] ?? 168)
                .toDouble(),
        };
      }

      var displayWidths = widthsFor(room);
      var displayTotal = rest.fold<double>(
          0, (sum, t) => sum + (displayWidths[t.key] ?? 168) + _gap);
      final reserveOverflow = displayTotal > room;
      if (reserveOverflow) {
        displayWidths = widthsFor(room - moreW);
        displayTotal = rest.fold<double>(
            0, (sum, t) => sum + (displayWidths[t.key] ?? 168) + _gap);
      }
      double widthOf(ShellTab t) => displayWidths[t.key] ?? 168;

      List<ShellTab> visible = [];
      List<ShellTab> hidden = [];
      void pack(double available) {
        visible = [];
        hidden = [];
        var used = 0.0;
        for (final t in rest) {
          final need = widthOf(t) + _gap;
          if (visible.isEmpty || used + need <= available) {
            visible.add(t);
            used += need;
          } else {
            hidden.add(t);
          }
        }
      }

      pack(reserveOverflow ? room - moreW : room);
      final overflow = hidden.isNotEmpty;
      final active = widget.activeTab;
      if (overflow &&
          active != null &&
          hidden.contains(active) &&
          visible.isNotEmpty) {
        final swapped = visible.removeLast();
        visible.add(active);
        hidden = [swapped, ...hidden.where((t) => t != active)];
      }

      Widget chip(ShellTab t, {bool leaving = false}) => _TabSlot(
          key: ValueKey('slot-${t.key}'),
          animate: _ready,
          leaving: leaving,
          onGone: () {
            if (mounted) setState(() => _leaving.remove(t.key));
          },
          child: Padding(
            padding: const EdgeInsets.only(right: _gap),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TopWorkspaceTabChip(
                tab: t,
                width: widthOf(t),
                provider: widget.providerFor?.call(t),
                agentId: widget.agentFor?.call(t),
                folder: widget.folderFor?.call(t),
                unread: widget.unreadFor?.call(t) ?? false,
                isActive: t == active,
                status: widget.statusForTab(t),
                canClose: widget.canCloseTab(t),
                onTap: () => widget.onActivateTab(t),
                onClose: () => widget.onCloseTab(t),
                chipKey: widget.chipKeyFor(t.key),
                attentionCount: t.isLead ? widget.mcAttentionCount : 0,
              ),
            ),
          ));
      final shown = <Widget>[for (final t in visible) chip(t)];
      if (!overflow) {
        final gone = _leaving.values.toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
        for (final (t, i) in gone) {
          shown.insert(i.clamp(0, shown.length), chip(t, leaving: true));
        }
      }

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
              for (final t in fixed) chip(t),
              ...shown,
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
            iconSize: 13,
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

/// A tab's slot: grows in when opened, shrinks out when closed.
class _TabSlot extends StatefulWidget {
  const _TabSlot({
    super.key,
    required this.child,
    required this.animate,
    required this.leaving,
    required this.onGone,
  });

  final Widget child;
  final bool animate;
  final bool leaving;
  final VoidCallback onGone;

  @override
  State<_TabSlot> createState() => _TabSlotState();
}

class _TabSlotState extends State<_TabSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: Motion.fast, value: widget.animate ? 0 : 1);
  late final CurvedAnimation _curve = CurvedAnimation(
      parent: _c, curve: Motion.enter, reverseCurve: Motion.exit);

  @override
  void initState() {
    super.initState();
    if (widget.leaving) {
      _leave();
    } else if (_c.value < 1) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(_TabSlot old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) _leave();
    if (!widget.leaving && old.leaving) _c.forward();
  }

  void _leave() {
    _c.value = _c.value == 0 ? 1 : _c.value;
    _c.reverseDuration = Motion.quick;
    _c.reverse().whenComplete(() {
      if (mounted && widget.leaving) widget.onGone();
    });
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child =
        widget.leaving ? IgnorePointer(child: widget.child) : widget.child;
    return AnimatedBuilder(
      animation: _curve,
      builder: (_, c) => ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: _curve.value,
          child: Opacity(opacity: _curve.value.clamp(0.0, 1.0), child: c),
        ),
      ),
      child: child,
    );
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
          width: 40,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(R.of(6)),
          ),
          child: Text('+${widget.count}',
              style: sans(12, weight: W.label, color: AppColors.fg1)),
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
    this.tools = const [],
    this.reserveWindowControls = true,
  });

  @override
  Widget build(BuildContext context) {
    if (kMobile) {
      return Container(
        height: 44,
        padding: EdgeInsets.fromLTRB(S.s8, 0, S.of(10), 0),
        decoration: BoxDecoration(
          color: AppColors.windowBg,
          border: Border(
              bottom:
                  BorderSide(color: AppColors.line.withValues(alpha: 0.65))),
        ),
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

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.windowBg,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(children: [
        if (sidebarHidden)
          SizedBox(
            width: 232,
            child: Row(children: [
              if (reserveWindowControls) const SizedBox(width: 70),
              if (onToggleSidebar != null)
                IconBtn('sidebar',
                    size: 28,
                    iconSize: 14,
                    tooltip:
                        kMacOS ? 'Show sidebar (⌘B)' : 'Show sidebar (Ctrl+B)',
                    onTap: onToggleSidebar),
              IconBtn('chevron-left',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Back',
                  onTap: canNavigateBack ? onNavigateBack : null),
              IconBtn('chevron-right',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Forward',
                  onTap: canNavigateForward ? onNavigateForward : null),
            ]),
          )
        else
          const SizedBox(width: 8),
        Expanded(child: tabsRow),
      ]),
    );
  }
}
