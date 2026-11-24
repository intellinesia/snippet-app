import 'package:flutter/material.dart';

import '../glass.dart';
import '../mochi.dart';
import '../quiet.dart' show QuietHand;
import '../widgets.dart' show ProviderLogo, providerLogoAsset;
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
    this.subtitleProvider,
    this.subtitleHand = false,
  });

  final List<StageMember> members;
  final String title;
  final String? subtitle;

  /// Phone: provider mark drawn before the subtitle, in the subtitle's ink.
  final String? subtitleProvider;

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

  static const double phoneHeight = 56;

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
    final avatar = members.isEmpty
        ? null
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AgentMochi(members.first.agentId, size: 32));
    final body = SizedBox(
      width: double.infinity,
      height: h,
      child: Row(children: [
        // Spec B header: back 48 at x0, avatar 32 at x56, title at x96.
        if (onBack != null)
          RoundBtn(
              icon: 'chevron-left',
              tooltip: 'Back',
              size: 48,
              iconSize: 20,
              onTap: onBack!)
        else
          const SizedBox(width: 16),
        if (avatar != null) ...[
          SizedBox(width: onBack != null ? 8 : 24),
          avatar,
          const SizedBox(width: 8),
        ] else
          const SizedBox(width: 8),
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
                        style: sans(16, weight: W.label, color: AppColors.fg1)),
                    if (sub.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (subtitleHand) ...[
                          const QuietHand(size: 14),
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12.5, color: AppColors.fg3)),
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
              padding: const EdgeInsets.only(right: 13.5), child: trailing!)
        else if (onTap != null)
          Padding(
            padding: const EdgeInsets.only(right: 13.5),
            child: RoundBtn(
                icon: 'more-horizontal',
                tooltip: 'More',
                size: 48,
                iconSize: 20,
                onTap: onTap!),
          ),
      ]),
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
