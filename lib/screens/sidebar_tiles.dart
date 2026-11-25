import 'package:flutter/material.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Tells section headers whether the pointer is over the sidebar, so their
/// action buttons only appear then.
class SidebarHoverScope extends StatefulWidget {
  const SidebarHoverScope({super.key, required this.child});
  final Widget child;

  static bool hovered(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HoverData>()?.hovered ??
      false;

  @override
  State<SidebarHoverScope> createState() => _SidebarHoverScopeState();
}

class _SidebarHoverScopeState extends State<SidebarHoverScope> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: _HoverData(hovered: _hovered, child: widget.child),
      );
}

class _HoverData extends InheritedWidget {
  const _HoverData({required this.hovered, required super.child});
  final bool hovered;

  @override
  bool updateShouldNotify(_HoverData old) => old.hovered != hovered;
}

class SidebarSectionAction {
  const SidebarSectionAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.enabled = true,
  });

  final String icon;
  final String tooltip;
  final void Function(BuildContext)? onTap;
  final bool enabled;
}

/// Desktop sidebar section title ("Agents", "Sessions") with quiet + and ...
/// buttons.
class SidebarSectionHeader extends StatelessWidget {
  const SidebarSectionHeader(
    this.title, {
    super.key,
    this.onAdd,
    this.addTooltip,
    this.onMore,
    this.moreTooltip,
    this.addBuilder,
    this.moreBuilder,
    this.actions = const <SidebarSectionAction>[],
    this.count,
    this.collapsed = false,
    this.onToggle,
  });

  final String title;
  final VoidCallback? onAdd;
  final String? addTooltip;
  final VoidCallback? onMore;
  final String? moreTooltip;

  /// Anchored actions (menus) need the button's own context.
  final void Function(BuildContext)? addBuilder;
  final void Function(BuildContext)? moreBuilder;
  final List<SidebarSectionAction> actions;
  final int? count;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    Widget btn(String icon, String tip, void Function(BuildContext) tap) =>
        Builder(
          builder: (ctx) =>
              _SectionBtn(icon: icon, tooltip: tip, onTap: () => tap(ctx)),
        );
    final add = addBuilder ?? (onAdd == null ? null : (_) => onAdd!());
    final more = moreBuilder ?? (onMore == null ? null : (_) => onMore!());
    final collapsible = onToggle != null || collapsed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 24,
        child: Row(children: [
          if (collapsible) ...[
            _SectionBtn(
              icon: collapsed ? 'chevron-right' : 'chevron-down',
              tooltip: collapsed ? 'Expand' : 'Collapse',
              iconSize: 10,
              enabled: onToggle != null,
              color: AppColors.fg3,
              onTap: onToggle == null ? null : () => onToggle!(),
            ),
            const SizedBox(width: 2),
          ],
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Desktop: the reference's 12px medium section label.
                    style: kMobile
                        ? sans(12,
                            weight: FontWeight.w500, color: AppColors.fg3)
                        : sans(12,
                            weight: FontWeight.w500, color: AppColors.fg2)),
              ),
              if (count != null && collapsed) ...[
                const SizedBox(width: 4),
                Text('$count', style: sans(11, color: AppColors.fg3)),
              ],
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final action in actions)
              Builder(
                builder: (ctx) => _SectionBtn(
                  icon: action.icon,
                  tooltip: action.tooltip,
                  enabled: action.enabled && action.onTap != null,
                  onTap: action.onTap == null ? null : () => action.onTap!(ctx),
                ),
              ),
            if (add != null) btn('plus', addTooltip ?? 'New', add),
            if (more != null)
              btn('more-horizontal', moreTooltip ?? 'More', more),
          ]),
        ]),
      ),
    );
  }
}

class _SectionBtn extends StatefulWidget {
  const _SectionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 12,
    this.enabled = true,
    this.color,
  });
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double iconSize;
  final bool enabled;
  final Color? color;

  @override
  State<_SectionBtn> createState() => _SectionBtnState();
}

class _SectionBtnState extends State<_SectionBtn> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onTap != null;
    final radius = BorderRadius.circular(R.of(6));
    final fill = _focus
        ? AppColors.surface3
        : _hover && enabled
            ? AppColors.hoverPlate
            : Colors.transparent;
    return Tooltip(
      message: widget.tooltip,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (v) => setState(() => _focus = v &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              onTap: enabled ? widget.onTap : null,
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(children: [
                  AnimatedContainer(
                    duration:
                        reduceMotion(context) ? Duration.zero : Motion.quick,
                    width: 24,
                    height: 24,
                    decoration:
                        BoxDecoration(color: fill, borderRadius: radius),
                    child: Center(
                      child: AppIcon(widget.icon,
                          size: widget.iconSize,
                          color: widget.color ??
                              (enabled ? AppColors.fg3 : AppColors.fg4)),
                    ),
                  ),
                  if (_focus)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: ColoredBox(color: AppColors.fg1),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app mark under the traffic lights, with optional trailing actions.
class SidebarBrand extends StatelessWidget {
  const SidebarBrand({super.key, this.trailing = const []});

  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        const AgentMochi('snippet', size: 22),
        const Spacer(),
        ...trailing,
      ]);
}
