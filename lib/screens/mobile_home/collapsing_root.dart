import 'package:flutter/material.dart';

import '../../phone_attention_bar.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../toast_avoid.dart';

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
    final d = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 150);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ToastAvoid(
        child: AnimatedContainer(
          duration: d,
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(
            color: _collapsed ? AppColors.surface1 : AppColors.bg,
            border: Border(
                bottom: BorderSide(
                    color: _collapsed ? AppColors.border : Colors.transparent)),
          ),
          padding: EdgeInsets.only(left: widget.leading == null ? 16 : 0, right: 4),
          child: Row(children: [
            if (widget.leading != null) widget.leading!,
            Expanded(
              child: AnimatedOpacity(
                duration: d,
                opacity: _collapsed ? 1 : 0,
                child: ExcludeSemantics(
                  excluding: !_collapsed,
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(16, weight: W.label, color: AppColors.fg1)),
                ),
              ),
            ),
            ...widget.actions,
          ]),
        ),
      ),
      if (kMobile) const PhoneAttentionLayer(),
      Expanded(
        child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll, child: widget.child),
      ),
    ]);
  }
}

/// The 28/500 title that heads a tab-root list, x16.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.title, {super.key, this.tagline});
  final String title;
  final String? tagline;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text(title,
                style: sans(28,
                    height: 37.8 / 28, weight: W.label, color: AppColors.fg1)),
          ),
          if (tagline != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tagline!, style: sans(13, color: AppColors.fg3)),
            ),
        ]),
      );
}
