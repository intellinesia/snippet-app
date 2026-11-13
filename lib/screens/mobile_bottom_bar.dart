import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';
import 'session_list_row.dart';
import 'shell_models.dart';

/// Phone bottom bar: the primary-action pill, the three-home tab capsule and
/// the search circle. One shared instance sits above the PageView so it stays
/// put across tabs; pages clear it with [onHeightChanged]-driven padding.
class MobileBottomBar extends StatefulWidget {
  const MobileBottomBar({
    super.key,
    required this.home,
    required this.onHome,
    required this.onNewSession,
    this.onNewAgentOrGroup,
    this.showNewSession = true,
    this.workingCount = 0,
    this.onSearch,
    this.onHeightChanged,
  });

  final MobileHome home;
  final ValueChanged<MobileHome> onHome;
  final VoidCallback onNewSession;
  final void Function(BuildContext anchor)? onNewAgentOrGroup;
  final bool showNewSession;

  /// Non-settled, non-waiting sessions in a running state; shown on the pill.
  final int workingCount;

  /// Non-null on Chats and Agents: shows the search circle, which opens the
  /// host's search page.
  final VoidCallback? onSearch;

  /// Reports the rendered height so pages can pad their scroll views clear of
  /// the glass. Called from a post-frame callback after each build.
  final ValueChanged<double>? onHeightChanged;

  @override
  State<MobileBottomBar> createState() => _MobileBottomBarState();
}

class _MobileBottomBarState extends State<MobileBottomBar> {
  double _reported = -1;

  bool get _primaryShown =>
      widget.home == MobileHome.chats && widget.showNewSession;

  void _reportHeight() {
    if (!mounted) return;
    final h = context.size?.height;
    if (h != null && h != _reported) {
      _reported = h;
      widget.onHeightChanged?.call(h);
    }
  }

  void _openSearch() {
    HapticFeedback.selectionClick();
    widget.onSearch?.call();
  }

  void _primary() {
    HapticFeedback.lightImpact();
    widget.onNewSession();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());
    final bottom =
        12.0 + MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_primaryShown) ...[
            _pill(),
            const SizedBox(height: 8),
          ],
          _tabsRow(),
        ],
      ),
    );
  }

  Widget _pill() {
    const label = 'New session';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _primary,
          child: Glass(
            radius: BorderRadius.circular(20),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.accentFill,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        'plus',
                        size: 15,
                        color: AppColors.accentFg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(label, style: TS.ui(AppColors.fg1)),
                  if (widget.workingCount > 0) ...[
                    const Spacer(),
                    const WorkingDots(),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.workingCount} working',
                      style: TS.caption(AppColors.fg3),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabsRow() {
    return Row(
      children: [
        Expanded(child: _tabCapsule()),
        if (widget.onSearch != null) ...[
          const SizedBox(width: 8),
          _searchButton(),
        ],
      ],
    );
  }

  static const _tabs = [
    MobileHome.chats,
    MobileHome.agents,
    MobileHome.settings,
  ];

  Widget _tabCapsule() {
    return Glass(
      radius: BorderRadius.circular(24),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(3),
        child: Row(children: [for (final h in _tabs) _tab(h)]),
      ),
    );
  }

  Widget _tab(MobileHome h) {
    final on = h == widget.home;
    final color = on ? AppColors.fg1 : AppColors.fg3;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        label: h.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onHome(h);
          },
          child: Container(
            decoration: BoxDecoration(
              color: on ? AppColors.surface3 : Colors.transparent,
              borderRadius: BorderRadius.circular(21),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(h.icon, size: 18, color: color),
                const SizedBox(height: 2),
                Text(
                  h.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.caption(color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchButton() {
    return Tooltip(
      message: 'Search',
      child: Semantics(
        button: true,
        label: 'Search',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openSearch,
          child: Glass(
            radius: null,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: AppIcon('search', size: 18, color: AppColors.fg2),
            ),
          ),
        ),
      ),
    );
  }

}
