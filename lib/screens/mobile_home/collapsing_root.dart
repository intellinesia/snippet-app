import 'package:flutter/material.dart';

import '../../phone_attention_bar.dart';
import '../../platform.dart';
import '../../glass.dart' show StatusInset;
import '../../theme.dart';
import '../../toast_avoid.dart';
import '../../mobile_kit.dart';

/// Scroll distance after which the large title hands over to the inline one.
const double kTitleCollapseAt = 24;

/// SH-10 D and E: a pinned bar over a list whose first row is [LargeTitle].
/// Past 24 px of scroll the bar gains surface1 and a hairline and its inline
/// 16/500 title fades in (instant with reduced motion).
class CollapsingRoot extends StatefulWidget {
  const CollapsingRoot(
      {super.key,
      required this.title,
      required this.child,
      this.actions = const [],
      this.leading});
  final String title;

  /// Optional back target before the bar title (pushed tab roots).
  final Widget? leading;
  final List<Widget> actions;
  final Widget child;

  @override
  State<CollapsingRoot> createState() => _CollapsingRootState();
}

class _CollapsingRootState extends State<CollapsingRoot> {
  bool _collapsed = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final c = n.metrics.pixels >= kTitleCollapseAt;
    if (c != _collapsed) setState(() => _collapsed = c);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final d = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final a = kAndroidLook;
    // iPhone groups header actions in one glass capsule; Android keeps bare
    // 48 icon buttons on the app bar.
    final actions = widget.actions.isEmpty
        ? const <Widget>[]
        : a
            ? widget.actions
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MkGlass(
                    radius: 22,
                    child: SizedBox(
                      height: 44,
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.actions),
                    ),
                  ),
                ),
              ];
    final bar = ToastAvoid(
      child: AnimatedContainer(
        duration: d,
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: _collapsed
              ? (a ? AppColors.surface2 : AppColors.bg)
              : (a ? AppColors.bg : Colors.transparent),
          border: Border(
              bottom: BorderSide(
                  width: 0.5,
                  color: _collapsed && !a
                      ? AppColors.fg1.withValues(alpha: 0.10)
                      : Colors.transparent)),
        ),
        padding: EdgeInsets.only(
            left: widget.leading == null ? (a ? 16 : 20) : 4, right: 4),
        child: Stack(alignment: Alignment.center, children: [
          Row(children: [
            if (widget.leading != null) widget.leading!,
            const Spacer(),
            ...actions,
          ]),
          Positioned.fill(
            left: a ? (widget.leading == null ? 0 : 52) : 96,
            right: a ? 104 : 96,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: d,
                opacity: _collapsed ? 1 : 0,
                child: ExcludeSemantics(
                  excluding: !_collapsed,
                  child: Align(
                    alignment: a ? Alignment.centerLeft : Alignment.center,
                    child: Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: a
                            ? sans(22, weight: W.label, color: AppColors.fg1)
                            : sans(16.5,
                                weight: FontWeight.w600, color: AppColors.fg1)),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
    final list = NotificationListener<ScrollNotification>(
        onNotification: _onScroll, child: widget.child);
    if (a) {
      // Board: the tonal fill runs up behind the status bar, which the host
      // SafeArea has already consumed, so paint that strip above the bar.
      final inset = StatusInset.of(context);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(clipBehavior: Clip.none, children: [
          Positioned(
            top: -inset,
            height: inset,
            left: 0,
            right: 0,
            child: AnimatedContainer(
                duration: d,
                color: _collapsed ? AppColors.surface2 : AppColors.bg),
          ),
          bar,
        ]),
        if (kMobile) const PhoneAttentionLayer(),
        Expanded(child: list),
      ]);
    }
    // iPhone at rest: no bar, the actions share the large title's row and the
    // list starts under the status bar. The bar only appears once collapsed.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (kMobile) const PhoneAttentionLayer(),
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: list),
          Positioned(top: 0, left: 0, right: 0, child: bar),
        ]),
      ),
    ]);
  }
}

/// The large title that heads a tab-root list.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.title, {super.key, this.tagline});
  final String title;
  final String? tagline;

  @override
  Widget build(BuildContext context) => Padding(
        // Board: iPhone title row centres on the 56 action row; Android sits
        // 4 under the app bar. Room on the right for the iPhone actions.
        padding: kAndroidLook
            ? const EdgeInsets.fromLTRB(20, 10, 20, 4)
            : const EdgeInsets.fromLTRB(20, 4, 120, 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text(title, style: mkLargeTitle()),
          ),
          if (tagline != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tagline!, style: sans(13, color: AppColors.fg3)),
            ),
        ]),
      );
}
