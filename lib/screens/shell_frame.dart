import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Desktop window frame (home-orca-v1). The fixed bands of the window, each a
/// slot with its height, fill and hairline owned here; the widgets that fill
/// them only lay out their content row.
///
///   +-------------------+---------------------------------------------+
///   | ShellTitleRow 40  | ShellTabStripFrame 36 (tabs | tools)        |
///   +-------------------+---------------------------------------------+
///   | sidebar body      | centre panes (bg, no card, gaps 0)          |
///   | (s1, right edge   |                                             |
///   |  hairline)        |                                             |
///   +-------------------+                                             |
///   | ShellFooterFrame  |                                             |
///   | 30, hairline top  |                                             |
///   +-------------------+---------------------------------------------+
///   | ShellStatusBarFrame 22, full width, s1, hairline top            |
///   +-----------------------------------------------------------------+
const double kShellTitleRowHeight = 40;
const double kShellTabStripHeight = 36;
const double kShellStatusBarHeight = 22;
const double kShellFooterHeight = 30;

/// Space the macOS traffic lights (10 at x16/34/52) take at the row start.
const double kShellWindowControlsWidth = 64;

/// The single hairline between frame regions.
BorderSide shellHairline() => BorderSide(color: AppColors.line, width: 1);

/// Title row, sidebar column only: window controls, app name and sidebar
/// toggle at the left, back and forward at the right.
class ShellTitleRow extends StatelessWidget {
  const ShellTitleRow({
    super.key,
    required this.onToggleSidebar,
    required this.canNavigateBack,
    required this.canNavigateForward,
    required this.onNavigateBack,
    required this.onNavigateForward,
    this.reserveWindowControls = false,
  });

  final VoidCallback onToggleSidebar;
  final bool canNavigateBack;
  final bool canNavigateForward;
  final VoidCallback onNavigateBack;
  final VoidCallback onNavigateForward;
  final bool reserveWindowControls;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      key: const ValueKey('shell-title-row'),
      height: kShellTitleRowHeight,
      decoration: BoxDecoration(border: Border(bottom: shellHairline())),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < 200
            // The 56 icon column (narrow Settings) keeps the toggle only.
            ? Center(child: _toggle())
            : _full(c.maxWidth),
      ),
    );
  }

  Widget _toggle() => ShellFrameButton(
        icon: 'sidebar',
        iconSize: 14,
        tooltip: kMacOS ? 'Hide sidebar (\u2318B)' : 'Hide sidebar (Ctrl+B)',
        onTap: onToggleSidebar,
      );

  Widget _full(double width) => Row(
        children: [
          // "Snippet" at x70, toggle at x138 (spec H1).
          SizedBox(width: reserveWindowControls ? 70 : 16),
          SizedBox(
            // Shrinks first when the column is dragged narrow.
            width: (width - (reserveWindowControls ? 70 : 16) - 3 * 28 - 6)
                .clamp(0.0, reserveWindowControls ? 68.0 : 122.0),
            child: Text(
              'Snippet',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: sans(12, weight: FontWeight.w500, color: AppColors.fg2),
            ),
          ),
          _toggle(),
          const Spacer(),
          ShellFrameButton(
            icon: 'chevron-left',
            tooltip: 'Back',
            onTap: canNavigateBack ? onNavigateBack : null,
          ),
          ShellFrameButton(
            icon: 'chevron-right',
            tooltip: 'Forward',
            onTap: canNavigateForward ? onNavigateForward : null,
          ),
          const SizedBox(width: 6),
        ],
      );
}

/// The cluster that replaces the title row over the strip's left edge while
/// the sidebar is hidden (ho-topbar band 5): tabs then start at x232.
class ShellCollapsedNavCluster extends StatelessWidget {
  const ShellCollapsedNavCluster({
    super.key,
    required this.onToggleSidebar,
    required this.canNavigateBack,
    required this.canNavigateForward,
    required this.onNavigateBack,
    required this.onNavigateForward,
    this.reserveWindowControls = false,
  });

  final VoidCallback onToggleSidebar;
  final bool canNavigateBack;
  final bool canNavigateForward;
  final VoidCallback onNavigateBack;
  final VoidCallback onNavigateForward;
  final bool reserveWindowControls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 232,
      child: Row(
        children: [
          SizedBox(width: reserveWindowControls ? 132 : 8),
          ShellFrameButton(
            icon: 'sidebar',
            iconSize: 14,
            tooltip:
                kMacOS ? 'Show sidebar (\u2318B)' : 'Show sidebar (Ctrl+B)',
            onTap: onToggleSidebar,
          ),
          if (!reserveWindowControls) const Spacer(),
          ShellFrameButton(
            icon: 'chevron-left',
            tooltip: 'Back',
            onTap: canNavigateBack ? onNavigateBack : null,
          ),
          ShellFrameButton(
            icon: 'chevron-right',
            tooltip: 'Forward',
            onTap: canNavigateForward ? onNavigateForward : null,
          ),
          if (reserveWindowControls) const Spacer(),
        ],
      ),
    );
  }
}

/// Centre-column tab strip band: 36 high, hairline at the bottom. [tabs]
/// fills the space between [leading] (collapsed-sidebar cluster) and
/// [trailing] (per-tab tools).
class ShellTabStripFrame extends StatelessWidget {
  const ShellTabStripFrame({
    super.key,
    required this.tabs,
    this.leading,
    this.trailing = const [],
  });

  final Widget tabs;
  final Widget? leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      key: const ValueKey('shell-tab-strip'),
      height: kShellTabStripHeight,
      decoration: BoxDecoration(border: Border(bottom: shellHairline())),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (leading != null) leading!,
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: tabs),
          ),
          if (trailing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in trailing) ...[t, const SizedBox(width: 2)],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sidebar footer band: 30 high, hairline top. Content is one row.
class ShellFooterFrame extends StatelessWidget {
  const ShellFooterFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      key: const ValueKey('shell-sidebar-footer'),
      constraints: const BoxConstraints(minHeight: kShellFooterHeight),
      decoration: BoxDecoration(border: Border(top: shellHairline())),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

/// Status bar band: 22 high, full window width, s1, hairline top.
class ShellStatusBarFrame extends StatelessWidget {
  const ShellStatusBarFrame({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DefaultTextStyle.merge(
      style: sans(11, color: AppColors.fg2),
      child: _StatusBarHitFrame(
        key: const ValueKey('shell-status-bar'),
        fill: AppColors.windowChrome,
        line: shellHairline().color,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// Hit/layout box behind [ShellStatusBarFrame]. The visible band is 22 high,
/// while the content row is 24 high and bottom-aligned so its targets reach 2pt
/// above the band; the frame still owns the band's fill, hairline and padding.
class _StatusBarHitFrame extends SingleChildRenderObjectWidget {
  const _StatusBarHitFrame({
    super.key,
    required this.fill,
    required this.line,
    required super.child,
  });

  final Color fill;
  final Color line;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStatusBarHitFrame(fill: fill, line: line);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStatusBarHitFrame renderObject,
  ) {
    renderObject
      ..fill = fill
      ..line = line;
  }
}

class _RenderStatusBarHitFrame extends RenderAligningShiftedBox {
  _RenderStatusBarHitFrame({required Color fill, required Color line})
      : _fill = fill,
        _line = line,
        super(
          alignment: Alignment.bottomCenter,
          textDirection: TextDirection.ltr,
        );

  static const double _targetHeight = 24;
  static const double _horizontalPadding = 12;

  Color get fill => _fill;
  Color _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  Color get line => _line;
  Color _line;
  set line(Color value) {
    if (value == _line) return;
    _line = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
        Size(constraints.maxWidth, kShellStatusBarHeight),
      );

  @override
  void performLayout() {
    final width = size.width > _horizontalPadding * 2
        ? size.width - _horizontalPadding * 2
        : 0.0;
    child?.layout(
      BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: _targetHeight,
        maxHeight: _targetHeight,
      ),
      parentUsesSize: true,
    );
    alignChild();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final bar = offset & size;
    context.canvas.drawRect(bar, Paint()..color = fill);
    super.paint(context, offset);
    context.canvas.drawRect(
      Rect.fromLTWH(offset.dx, offset.dy, size.width, 1),
      Paint()..color = line,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position)) return true;
    return size.contains(position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final childParentData = child.parentData! as BoxParentData;
    return result.addWithPaintOffset(
      offset: childParentData.offset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }
}

/// Compact frame icon button: 28 target, s2 plate r6 on hover, fg2 icon,
/// fg3 when disabled.
class ShellFrameButton extends StatefulWidget {
  const ShellFrameButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.size = 28,
    this.iconSize = 13,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  State<ShellFrameButton> createState() => _ShellFrameButtonState();
}

class _ShellFrameButtonState extends State<ShellFrameButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          enabled: enabled,
          label: widget.tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    enabled && _hover ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: AppIcon(
                widget.icon,
                size: widget.iconSize,
                color: enabled ? AppColors.fg2 : AppColors.fg3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
