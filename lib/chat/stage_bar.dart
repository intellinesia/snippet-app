import 'package:flutter/material.dart';

import '../glass.dart';
import '../mochi.dart';
import '../widgets.dart' show AppIcon, ProviderLogo, providerLogoAsset;
import '../platform.dart';
import '../theme.dart';
import '../tap_detector.dart';
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

  static const double phoneHeight = 58;

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
    final groupAvatar = members.length > 1;
    final avatar = members.isEmpty
        ? null
        : groupAvatar
            ? Container(
                width: 30,
                height: 30,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8.4),
                  border: Border.all(color: AppColors.line),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6.4),
                  child: AgentMochi(members.first.agentId, size: 26),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: AgentMochi(members.first.agentId, size: 30));
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        constraints: BoxConstraints(minHeight: h),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: subtitleHand ? AppColors.surface2 : AppColors.surface1,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          if (onBack != null)
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: SizedBox(
                width: 36,
                height: 48,
                child: Center(
                  child: AppIcon('chevron-left', size: 20, color: AppColors.fg1),
                ),
              ),
            )
          else
            const SizedBox(width: 10),
          if (avatar != null) ...[
            const SizedBox(width: 4),
            avatar,
            const SizedBox(width: 9),
          ] else
            const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              button: onTap != null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(15, weight: W.label, color: AppColors.fg1)),
                      if (sub.isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (subtitleHand) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: AppColors.run, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                          ],
                          if (subtitleProvider != null &&
                              providerLogoAsset(subtitleProvider) != null) ...[
                            ProviderLogo(subtitleProvider,
                                size: 12, color: AppColors.fg3),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(12,
                                    color: subtitleHand
                                        ? AppColors.fg2
                                        : AppColors.fg3)),
                          ),
                        ]),
                      if (below != null) ...[const SizedBox(height: 6), below!],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null)
            Padding(
                padding: const EdgeInsets.only(right: 4), child: trailing!)
          else if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: SizedBox(
                  width: 36,
                  height: 48,
                  child: Center(
                    child: AppIcon('more-horizontal',
                        size: 20, color: AppColors.fg2),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
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
          if (trailing != null) Positioned(right: 0, top: 0, child: trailing!),
        ]),
      ),
    );
    return SizedBox(
        height: height,
        child: Align(alignment: Alignment.topCenter, child: body));
  }
}
