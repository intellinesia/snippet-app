import 'package:flutter/foundation.dart';
import '../toast_avoid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ambient/controller.dart';
import '../api.dart';
import '../glass.dart';
import '../mobile_kit.dart';
import '../mochi.dart';
import '../motion_routes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_voice_page.dart';
import 'tasks/tasks_panel.dart';
import '../tap_detector.dart';

BoxDecoration _floating(double radius) => BoxDecoration(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
            color: AppColors.fg1.withValues(alpha: 0.08), spreadRadius: 1),
      ],
    );

class RoundBtn extends StatelessWidget {
  const RoundBtn({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    this.onTap,
    this.size = 40,
    this.iconSize = 18,
    this.badge = false,
    this.badgeCount = 0,
    this.bare = true,
  });

  final bool bare;
  final String? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool badge;
  final int badgeCount;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    tapHaptic();
                    onTap!();
                  },
            child: Stack(clipBehavior: Clip.none, children: [
              if (bare) _face() else Glass(radius: null, child: _face()),
              if (badge && badgeCount <= 0)
                Positioned(
                  right: 1,
                  top: 1,
                  child: IgnorePointer(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: AppColors.accent, shape: BoxShape.circle),
                    ),
                  ),
                ),
              if (badgeCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: IgnorePointer(
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      padding: EdgeInsets.symmetric(horizontal: S.s4),
                      decoration: BoxDecoration(
                        color: AppColors.accentFill,
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$badgeCount',
                        style: TS.caption(AppColors.accentFg).copyWith(
                            fontSize: 10, fontWeight: W.label, height: 1),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );

  Widget _face() => Container(
        width: size < 48 ? 48 : size,
        height: size < 48 ? 48 : size,
        alignment: Alignment.center,
        child: child ?? AppIcon(icon!, size: iconSize, color: AppColors.fg2),
      );
}

class ListeningPill extends StatelessWidget {
  const ListeningPill({super.key, this.onTap});

  final VoidCallback? onTap;

  static const _heights = [5.0, 11.0, 7.0, 9.0];

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 26,
      padding: EdgeInsets.symmetric(horizontal: S.of(9)),
      decoration: BoxDecoration(
        color: AppColors.ok.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(R.of(13)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _heights.length; i++) ...[
                if (i > 0) SizedBox(width: S.s2),
                Container(
                  width: 2,
                  height: _heights[i],
                  decoration: BoxDecoration(
                    color: AppColors.ok,
                    borderRadius: BorderRadius.circular(R.of(1)),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(width: S.s6),
        Text('Listening', style: TS.caption(AppColors.ok).copyWith(height: 1)),
      ]),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: 'Voice',
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: pill,
      ),
    );
  }
}

class MobileHomeHeader extends StatelessWidget {
  const MobileHomeHeader({
    super.key,
    required this.title,
    this.mcBadgeCount = 0,
    this.onMc,
    this.onBack,
    this.listening = false,
    this.onListening,
    this.trailing = const [],
  });

  final String title;
  final int mcBadgeCount;
  final VoidCallback? onMc;
  final VoidCallback? onBack;
  final bool listening;
  final VoidCallback? onListening;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) =>
      ToastAvoid(child: Builder(builder: _bar));

  Widget _bar(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(M.gutter, S.s6, M.gutter, S.s6),
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Center(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: sans(17, weight: W.strong, color: AppColors.fg1),
                  ),
                ),
              ),
              Row(children: [
                if (onBack != null)
                  RoundBtn(
                    icon: 'chevron-left',
                    tooltip: 'Back',
                    size: 44,
                    iconSize: 20,
                    onTap: onBack,
                  )
                else
                  RoundBtn(
                    tooltip: 'Lead',
                    size: 44,
                    badgeCount: mcBadgeCount,
                    onTap: onMc,
                    child: AgentMochi('lead', size: 26),
                  ),
                const Spacer(),
                if (listening) ...[
                  ListeningPill(
                    onTap: onListening ?? () => openMobileVoicePage(context),
                  ),
                  if (trailing.isNotEmpty) SizedBox(width: S.of(10)),
                ],
                ...trailing,
              ]),
            ],
          ),
        ),
      );
}

Future<void> openMobileTasksPage(BuildContext context, DaemonClient client) {
  return Navigator.of(context).push<void>(AppPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(child: TasksPanel(client: client, phoneHeader: true)),
    ),
  ));
}

class MobileMissionBar extends StatelessWidget {
  const MobileMissionBar({super.key, this.onActions, this.onBack, this.client});

  final VoidCallback? onActions;
  final VoidCallback? onBack;
  final DaemonClient? client;

  @override
  Widget build(BuildContext context) =>
      ToastAvoid(child: Builder(builder: _bar));

  Widget _bar(BuildContext context) {
    final c = client;
    final android = kAndroidLook;
    final side = android ? 48.0 : MK.glassButton;
    final identity = Row(mainAxisSize: MainAxisSize.min, children: [
      AgentMochi('lead', size: android ? 36 : 30),
      SizedBox(width: android ? 12 : 8),
      Flexible(
        child: Text('Lead',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: android
                ? sans(18, weight: W.label, color: AppColors.fg1)
                : sans(15, weight: FontWeight.w600, color: AppColors.fg1)),
      ),
    ]);
    final chip = Semantics(
      button: onActions != null,
      label: 'Lead',
      hint: 'Session actions',
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onActions,
        child: android
            ? ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(alignment: Alignment.centerLeft, child: identity))
            : MkGlass(
                radius: 24,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.fromLTRB(7, 0, 16, 0),
                  child: identity,
                ),
              ),
      ),
    );
    return SizedBox(
      height: mkChatHeaderHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: android ? 4 : M.gutter),
        child: Row(children: [
          if (onBack != null) ...[
            MkIconButton(
                icon: android ? 'arrow-left' : 'chevron-left',
                label: 'Back',
                bare: android,
                onTap: onBack),
            SizedBox(width: android ? 4 : 8),
          ] else
            SizedBox(width: android ? 12 : side + 8),
          Expanded(child: android ? chip : Center(child: chip)),
          const SizedBox(width: 8),
          if (c != null)
            ListenableBuilder(
              listenable: AmbientController.instance,
              builder: (context, _) {
                final live = AmbientController.instance.running;
                final btn = RoundBtn(
                  tooltip: live ? 'Voice call' : 'Start voice',
                  size: side,
                  onTap: () => startMobileVoice(context, c),
                  child: AppIcon('phone',
                      size: android ? 22 : 18,
                      color: live ? AppColors.ok : AppColors.fg1),
                );
                return android ? btn : MkGlass(child: btn);
              },
            )
          else
            SizedBox(width: side),
        ]),
      ),
    );
  }
}

class MobileBackBar extends StatelessWidget {
  const MobileBackBar({
    super.key,
    required this.title,
    this.onBack,
    this.subtitle,
    this.subtitleView,
    this.onTitleTap,
    this.onTitleTapHint,
    this.trailing = const [],
    this.menu = false,
    this.chevron = false,
    this.keepBack = false,
    this.leading,
  });

  final String title;
  final String? subtitle;

  /// Replaces [subtitle] when set, e.g. a live connection status.
  final Widget? subtitleView;

  /// For a back that does something the system gesture wouldn't: closing an
  /// overlay inside the page or saving on the way out. Anywhere else the gesture
  /// is the way back and the bar stays clear.
  final bool keepBack;
  final Widget? leading;
  final bool menu;
  final bool chevron;
  final VoidCallback? onBack;
  final VoidCallback? onTitleTap;
  final String? onTitleTapHint;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) =>
      ToastAvoid(child: Builder(builder: _bar));

  Widget _bar(BuildContext context) {
    final pill = onTitleTap != null || subtitle != null || subtitleView != null;
    // iOS has no system back for these pages, so only Android loses the button,
    // and only when nothing on the right would leave the bar lopsided.
    final showBack = menu ||
        keepBack ||
        trailing.isNotEmpty ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final back = !showBack
        ? null
        : onBack ??
            (trailing.isNotEmpty && canPop
                ? () => Navigator.maybePop(context)
                : null);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: pill
                    ? TS.ui(AppColors.fg1).copyWith(
                        fontSize: 15, fontWeight: W.strong, height: 1.25)
                    : sans(16, weight: W.strong, color: AppColors.fg1)),
          ),
          if (chevron) ...[
            SizedBox(width: S.s4),
            AppIcon('chevron-down', size: 14, color: AppColors.fg3),
          ],
        ]),
        if (subtitleView != null)
          Padding(padding: EdgeInsets.only(top: S.of(1)), child: subtitleView)
        else if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: S.of(1)),
            child: Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS
                    .caption(AppColors.fg3)
                    .copyWith(fontSize: 12, height: 1.2)),
          ),
      ],
    );
    final label = leading == null
        ? text
        : Row(mainAxisSize: MainAxisSize.min, children: [
            leading!,
            SizedBox(width: S.s8),
            Flexible(child: text),
          ]);
    // A floor, not a fixed height: large text grows the bar.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: M.gutter),
        child: Row(children: [
          if (back != null)
            MkIconButton(
                icon: menu
                    ? 'menu'
                    : kAndroidLook
                        ? 'arrow-left'
                        : 'chevron-left',
                label: menu ? 'Menu' : 'Back',
                bare: kAndroidLook,
                onTap: back),
          if (back == null && trailing.isNotEmpty)
            SizedBox(width: 48.0 * trailing.length),
          Expanded(
            child: pill
                ? Align(
                    alignment: Alignment.center,
                    child: Semantics(
                      button: onTitleTap != null,
                      onTapHint: onTitleTapHint,
                      child: TapDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onTitleTap,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: EdgeInsets.only(right: S.s8),
                          alignment: Alignment.center,
                          child: IntrinsicWidth(child: label),
                        ),
                      ),
                    ),
                  )
                : Align(alignment: Alignment.center, child: label),
          ),
          if (trailing.isNotEmpty) ...[
            SizedBox(width: S.s4),
            ...trailing,
          ] else if (back != null)
            const SizedBox(width: 48),
        ]),
      ),
    );
  }
}

/// A title bar with no side buttons. The pill keeps the width it has beside a
/// back and a menu button.
class MobileStackedTitleBar extends StatelessWidget {
  const MobileStackedTitleBar({
    super.key,
    required this.title,
    this.onTap,
    this.tapHint,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final String? tapHint;

  static const _side = 16.0 + 44 + 10;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(_side, S.s8, _side, S.s8),
        child: Center(
          child: Semantics(
            button: onTap != null,
            label: title,
            hint: tapHint,
            child: Pressable(
              kind: PressKind.card,
              radius: 20,
              enabled: onTap != null,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Container(
                  height: subtitle == null ? 40 : 44,
                  constraints: const BoxConstraints(minWidth: 96),
                  padding: EdgeInsets.symmetric(horizontal: S.s16),
                  decoration: _floating(subtitle == null ? 20 : 22),
                  child: Center(
                    widthFactor: 1,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: sans(subtitle == null ? 15 : 14,
                              weight: W.strong, color: AppColors.fg1)),
                      if (subtitle != null)
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12, color: AppColors.fg3)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class FloatingSearch extends StatelessWidget {
  const FloatingSearch({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Glass(
        radius: BorderRadius.circular(R.of(22)),
        child: Container(
          height: 44,
          padding: EdgeInsets.only(left: S.of(18), right: S.s8),
          child: Row(children: [
            AppIcon('search', size: 16, color: AppColors.fg4),
            SizedBox(width: S.of(10)),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                style: TS.ui(AppColors.fg1),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: TS.ui(AppColors.fg4),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: controller,
              builder: (_, __) => controller.text.isEmpty
                  ? SizedBox(width: S.s8)
                  : IconBtn('x', size: 36, iconSize: 16, tooltip: 'Clear',
                      onTap: () {
                      controller.clear();
                      onChanged('');
                    }),
            ),
          ]),
        ),
      );
}

class AccentFab extends StatelessWidget {
  const AccentFab(
      {super.key,
      required this.tooltip,
      required this.onTap,
      this.icon = 'plus'});

  final String tooltip;
  final VoidCallback onTap;
  final String icon;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: TapDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.accentFill, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: AppIcon(icon, size: 20, color: AppColors.accentFg),
            ),
          ),
        ),
      );
}

class BottomFade extends StatelessWidget {
  const BottomFade({super.key, this.height = 130});

  final double height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.bg.withValues(alpha: 0), AppColors.bg],
              stops: const [0, 0.6],
            ),
          ),
        ),
      );
}

enum MobileMenuPick { newSession, tasks, artifacts, usage, machines }

Future<void> showMobileMenu(
  BuildContext context, {
  required DaemonClient? client,
  required String newSessionSubtitle,
  required void Function(MobileMenuPick pick) onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: sheetMotion,
    builder: (sheet) => _MobileMenu(
      client: client,
      newSessionSubtitle: newSessionSubtitle,
      onPick: (p) {
        Navigator.pop(sheet);
        onPick(p);
      },
    ),
  );
}

class _MobileMenu extends StatelessWidget {
  const _MobileMenu({
    required this.client,
    required this.newSessionSubtitle,
    required this.onPick,
  });

  final DaemonClient? client;
  final String newSessionSubtitle;
  final ValueChanged<MobileMenuPick> onPick;

  Widget _row(String icon, String label, MobileMenuPick pick) => InkWell(
        onTap: () {
          tapHaptic();
          onPick(pick);
        },
        child: SizedBox(
          height: M.minTarget + 8,
          child: Row(children: [
            AppIcon(icon, size: 19, color: AppColors.fg3),
            SizedBox(width: S.of(14)),
            Expanded(child: Text(label, style: TS.rowTitle())),
            AppIcon('chevron-right', size: 15, color: AppColors.fg3),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AppSheetSurface(
      child: Material(
        color: Colors.transparent,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, bottom + S.s12),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (client != null)
                  Material(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(R.lg),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        tapHaptic();
                        onPick(MobileMenuPick.newSession);
                      },
                      child: Padding(
                        padding: EdgeInsets.all(S.of(14)),
                        child: Row(children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: AppColors.accentFill,
                                shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: AppIcon('plus',
                                size: 18, color: AppColors.accentFg),
                          ),
                          SizedBox(width: S.of(14)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('New session', style: TS.rowTitle()),
                                if (newSessionSubtitle.isNotEmpty)
                                  Text(newSessionSubtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TS.meta()),
                              ],
                            ),
                          ),
                          AppIcon('chevron-right',
                              size: 15, color: AppColors.fg4),
                        ]),
                      ),
                    ),
                  ),
                SizedBox(height: S.s8),
                if (client != null) ...[
                  _row('task', 'Tasks', MobileMenuPick.tasks),
                  _row('file-stack', 'Artifacts', MobileMenuPick.artifacts),
                  _row('analytics', 'Usage', MobileMenuPick.usage),
                ],
                _row('server', 'Machines', MobileMenuPick.machines),
              ]),
        ),
      ),
    );
  }
}
