import 'package:flutter/material.dart';

import '../glass.dart';
import '../platform.dart';
import '../theme.dart';
import 'chat_style.dart';
import 'stage_header.dart';

/// A chat's top bar built on [StageHeader]: back on the left, an action on the
/// right, the cast and chip in the middle. The phone floats it on a frosted
/// strip; desktop keeps the compact window-bar height.
///
/// Pad the transcript's top by [StageBar.height].
class StageBar extends StatelessWidget {
  const StageBar({
    super.key,
    required this.members,
    required this.title,
    this.subtitle,
    this.subtitleDot,
    this.onTap,
    this.onBack,
    this.trailing,
    this.leading,
  });

  final List<StageMember> members;
  final String title;
  final String? subtitle;
  final Color? subtitleDot;
  final VoidCallback? onTap;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// Desktop only: replaces the back button.
  final Widget? leading;

  static const double phoneHeight = 140;

  // Desktop leaves headroom above the cast: the characters' crowns rise past their box.
  static double get height => kMobile ? phoneHeight : ChatHeader.overlap + 24;

  @override
  Widget build(BuildContext context) {
    final header = StageHeader(
      members: members,
      title: title,
      subtitle: subtitle,
      subtitleDot: subtitleDot,
      onTap: onTap,
      compact: !kMobile,
    );
    Widget side(Widget w) => kMobile
        ? SizedBox(
            width: 44, height: 44, child: Center(child: w))
        : w;
    final back = onBack == null
        ? null
        : ChatGlassButton(
            icon: 'chevron-left', tooltip: 'Back', onTap: onBack!);
    final body = SizedBox(
      height: height - (kMobile ? GlassTopFrame.fade : 0),
      child: Padding(
        padding: EdgeInsets.fromLTRB(kMobile ? S.s12 : S.s12,
            kMobile ? S.s4 : S.s24, kMobile ? S.s12 : S.s12, 0),
        child: Stack(children: [
          Align(alignment: Alignment.topCenter, child: header),
          if (leading != null || back != null)
            Positioned(left: 0, top: 0, child: leading ?? side(back!)),
          if (trailing != null)
            Positioned(right: 0, top: 0, child: side(trailing!)),
        ]),
      ),
    );
    if (!kMobile) {
      return SizedBox(
          height: height,
          child: Align(alignment: Alignment.topCenter, child: body));
    }
    return SizedBox(
        height: height, child: GlassTopFrame(color: readingBg, child: body));
  }
}
