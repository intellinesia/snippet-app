import 'package:flutter/material.dart';

import '../glass.dart';
import '../platform.dart';
import '../theme.dart';
import 'chat_style.dart';
import 'stage_header.dart';
import '../screens/mobile_chrome.dart' show RoundBtn;

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
    this.below,
    this.framed = true,
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

  /// Phone only: a pill under the chip.
  final Widget? below;

  /// Phone only: false when the host already floats it on [GlassTopFrame].
  final bool framed;

  static const double phoneHeight = 140;

  // Desktop leaves headroom above the cast: the characters' crowns rise past their box.
  static double get height => kMobile ? phoneHeight : ChatHeader.overlap + 24;

  @override
  Widget build(BuildContext context) => kMobile ? _phone() : _desk();

  // One phone header for sessions, agents and groups: same frame, same buttons.
  Widget _phone() {
    final body = Stack(alignment: Alignment.topCenter, children: [
      Padding(
        padding: EdgeInsets.only(top: S.s8),
        child: StageHeader(
          members: members,
          title: title,
          subtitle: subtitle,
          subtitleDot: subtitleDot,
          onTap: onTap,
          below: below,
        ),
      ),
      if (onBack != null)
        Positioned(
          left: M.gutter,
          top: S.s8,
          child: RoundBtn(
              icon: 'chevron-left',
              tooltip: 'Back',
              size: 40,
              iconSize: 20,
              onTap: onBack!),
        ),
      if (trailing != null)
        Positioned(right: M.gutter, top: S.s8, child: trailing!),
    ]);
    return framed ? GlassTopFrame(child: body) : body;
  }

  Widget _desk() {
    final header = StageHeader(
      members: members,
      title: title,
      subtitle: subtitle,
      subtitleDot: subtitleDot,
      onTap: onTap,
      compact: true,
    );
    final back = onBack == null
        ? null
        : ChatGlassButton(
            icon: 'chevron-left', tooltip: 'Back', onTap: onBack!);
    final body = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.s24, S.s12, 0),
        child: Stack(children: [
          Align(alignment: Alignment.topCenter, child: header),
          if (leading != null || back != null)
            Positioned(left: 0, top: 0, child: leading ?? back!),
          if (trailing != null)
            Positioned(right: 0, top: 0, child: trailing!),
        ]),
      ),
    );
    return SizedBox(
        height: height,
        child: Align(alignment: Alignment.topCenter, child: body));
  }
}
