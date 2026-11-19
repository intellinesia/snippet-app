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

/// Desktop sidebar section title ("Agents", "Sessions") with quiet + and ...
/// buttons that show while the sidebar is hovered.
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
  });

  final String title;
  final VoidCallback? onAdd;
  final String? addTooltip;
  final VoidCallback? onMore;
  final String? moreTooltip;

  /// Anchored actions (menus) need the button's own context.
  final void Function(BuildContext)? addBuilder;
  final void Function(BuildContext)? moreBuilder;

  @override
  Widget build(BuildContext context) {
    final show = SidebarHoverScope.hovered(context);
    final still = reduceMotion(context);
    Widget btn(String icon, String tip, void Function(BuildContext) tap) =>
        Builder(
          builder: (ctx) =>
              _SectionBtn(icon: icon, tooltip: tip, onTap: () => tap(ctx)),
        );
    final add = addBuilder ?? (onAdd == null ? null : (_) => onAdd!());
    final more = moreBuilder ?? (onMore == null ? null : (_) => onMore!());
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: SizedBox(
        height: 22,
        child: Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12,
                    weight: kMobile ? FontWeight.w500 : FontWeight.w600,
                    color: AppColors.fg3)),
          ),
          AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: still ? Duration.zero : const Duration(milliseconds: 150),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (add != null) btn('plus', addTooltip ?? 'New', add),
              if (more != null)
                btn('more-horizontal', moreTooltip ?? 'More', more),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SectionBtn extends StatefulWidget {
  const _SectionBtn(
      {required this.icon, required this.tooltip, required this.onTap});
  final String icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_SectionBtn> createState() => _SectionBtnState();
}

class _SectionBtnState extends State<_SectionBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _hover
                    ? AppColors.fg1.withValues(alpha: 0.07)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(R.of(6)),
              ),
              child: Center(
                  child: AppIcon(widget.icon,
                      size: 14, color: _hover ? AppColors.fg1 : AppColors.fg3)),
            ),
          ),
        ),
      );
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
