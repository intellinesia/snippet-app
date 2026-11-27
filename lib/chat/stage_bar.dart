import 'package:flutter/material.dart';

import '../glass.dart';
import '../mobile_kit.dart';
import '../mochi.dart';
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
    this.below,
    this.framed = true,
    this.subtitleProvider,
    this.subtitleHand = false,
    this.avatarSize = 32,
    this.titleSize = 16,
  });

  final List<StageMember> members;
  final String title;
  final String? subtitle;

  /// Phone: provider mark drawn before the subtitle, in the subtitle's ink.
  final String? subtitleProvider;

  /// Phone: avatar and title size (session chats use 30 and 15).
  final double avatarSize;
  final double titleSize;

  /// Phone: the amber needs-you hand before the subtitle.
  final bool subtitleHand;
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

  // Board: 56 on iPhone, 64 on Android.
  static double get phoneHeight => mkChatHeaderHeight;

  // Desktop leaves headroom above the cast: the characters' crowns rise past their box.
  static double get height => kMobile ? phoneHeight : ChatHeader.overlap + 24;

  @override
  Widget build(BuildContext context) => kMobile ? _phone() : _desk();

  // One phone header for sessions, agents and groups: same frame, same buttons.
  Widget _phone() => Builder(builder: _phoneIn);

  Widget _phoneIn(BuildContext context) {
    // Title and meta grow with text scale; the bar grows with them.
    final grow = MediaQuery.textScalerOf(context).scale(36) - 36;
    final h = phoneHeight + (grow > 0 ? grow : 0);
    final sub = (subtitle ?? '').trim();
    final android = kAndroidLook;
    final face = android ? 36.0 : 32.0;
    final avatar = members.isEmpty
        ? null
        : members.length > 1
            ? Container(
                width: face,
                height: face,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(face * 0.28)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(face * 0.22),
                  child: AgentMochi(members.first.agentId, size: face - 4),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(face / 2),
                child: AgentMochi(members.first.agentId, size: face));
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          android ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (subtitleHand) ...[
            Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: MK.amber, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: android
                    ? sans(18, weight: W.label, color: AppColors.fg1)
                    : sans(15, weight: FontWeight.w600, color: AppColors.fg1)),
          ),
        ]),
        if (below != null) ...[const SizedBox(height: 6), below!],
      ],
    );
    final chip = Semantics(
      button: onTap != null,
      // The board shows the name only; the state line stays for screen readers.
      hint: sub.isEmpty ? null : sub,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: android
            ? ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(children: [
                  if (avatar != null) ...[avatar, const SizedBox(width: 10)],
                  Expanded(child: text),
                ]),
              )
            // iPhone: the identity floats as one glass capsule, centred.
            : MkGlass(
                radius: 24,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding:
                        EdgeInsets.fromLTRB(avatar == null ? 16 : 7, 4, 16, 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (avatar != null) ...[avatar, const SizedBox(width: 8)],
                      Flexible(child: text),
                    ]),
                  ),
                ),
              ),
      ),
    );
    final more = onTap == null
        ? null
        : MkIconButton(
            icon: android ? 'more-vertical' : 'more-horizontal',
            label: 'More',
            bare: android,
            onTap: onTap);
    // iPhone gives any trailing control the same glass circle as back.
    final Widget? end = trailing == null
        ? more
        : android
            ? trailing
            : MkGlass(
                child: SizedBox.square(
                    dimension: MK.glassButton, child: Center(child: trailing)));
    final back = onBack == null
        ? null
        : MkIconButton(
            icon: android ? 'arrow-left' : 'chevron-left',
            label: 'Back',
            bare: android,
            onTap: onBack);
    final side = android ? 48.0 : MK.glassButton;
    final body = ConstrainedBox(
      constraints: BoxConstraints(minHeight: h),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: android ? 4 : 14),
        child: Row(children: [
          if (back != null)
            back
          else if (!android)
            SizedBox(width: end == null ? 0 : side)
          else
            const SizedBox(width: 12),
          SizedBox(width: android ? 4 : 8),
          Expanded(child: android ? chip : Center(child: chip)),
          SizedBox(width: android ? 4 : 8),
          if (end != null)
            end
          else if (!android && back != null)
            SizedBox(width: side),
        ]),
      ),
    );
    final lifted = mkLiftHeader(body);
    return framed ? GlassTopFrame(thread: true, child: lifted) : lifted;
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
          if (trailing != null) Positioned(right: 0, top: 0, child: trailing!),
        ]),
      ),
    );
    return SizedBox(
        height: height,
        child: Align(alignment: Alignment.topCenter, child: body));
  }
}
