import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../mochi.dart';
import '../theme.dart';
import '../widgets.dart';

BoxDecoration _floating(double radius) => BoxDecoration(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
            color: AppColors.fg1.withValues(alpha: 0.08), spreadRadius: 1),
      ],
    );

// Shared by the home list and the top bar so both follow the agents/sessions switch.
final mobileAgentsList = ValueNotifier<bool>(false);
const _agentsListPref = 'mobile_home_agents_list';

Future<void> loadMobileAgentsList() async {
  mobileAgentsList.value =
      (await SharedPreferences.getInstance()).getBool(_agentsListPref) ?? false;
}

void setMobileAgentsList(bool agents) {
  FocusManager.instance.primaryFocus?.unfocus();
  mobileAgentsList.value = agents;
  SharedPreferences.getInstance()
      .then((p) => p.setBool(_agentsListPref, agents));
}

// The chat composer's card, so the home search row reads as the same control.
BoxDecoration _composerLike(double radius) => BoxDecoration(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
    );

class RoundBtn extends StatelessWidget {
  const RoundBtn({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    this.onTap,
    this.size = 44,
    this.iconSize = 19,
    this.badge = false,
  });

  final String? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool badge;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: Container(
              width: size,
              height: size,
              decoration: _floating(size / 2),
              alignment: Alignment.center,
              child: Stack(clipBehavior: Clip.none, children: [
                child ?? AppIcon(icon!, size: iconSize, color: AppColors.fg2),
                if (badge)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: AppColors.accent, shape: BoxShape.circle),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

class MobileTopBar extends StatelessWidget {
  const MobileTopBar({
    super.key,
    required this.mission,
    required this.onMission,
    required this.onSessions,
    required this.onMenu,
    required this.onSettings,
    this.sessionsBusy = false,
    this.trailingOrb,
    this.onActions,
  });

  final Widget? trailingOrb;
  final VoidCallback? onActions;
  final bool mission;
  final VoidCallback onMission;
  final VoidCallback onSessions;
  final VoidCallback onMenu;
  final VoidCallback onSettings;
  final bool sessionsBusy;

  Widget _segment({
    Key? key,
    required bool active,
    required Widget glyph,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onActiveTap,
    bool dot = false,
    bool flips = false,
  }) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: active
            ? (onActiveTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onActiveTap();
                  })
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: active ? 14 : 13),
          decoration: BoxDecoration(
            color: active ? AppColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              glyph,
              if (dot && !active)
                Positioned(
                  right: -4,
                  top: -2,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                  ),
                ),
            ]),
            if (active) ...[
              const SizedBox(width: 8),
              Text(label,
                  style: sans(15, weight: W.strong, color: AppColors.fg1)),
              if (flips) ...[
                const SizedBox(width: 6),
                AppIcon('chevron-down', size: 14, color: AppColors.fg3),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          RoundBtn(icon: 'menu', tooltip: 'Menu', onTap: onMenu),
          if (trailingOrb != null) const SizedBox(width: 44),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: _floating(24),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _segment(
                active: mission,
                label: 'Mission',
                glyph: MochiIcon(
                    color: mission ? mochiPalette.first.$2 : AppColors.fg4,
                    size: 19),
                onTap: onMission,
                onActiveTap: onActions,
              ),
              const SizedBox(width: 2),
              ValueListenableBuilder<bool>(
                valueListenable: mobileAgentsList,
                builder: (_, agents, __) => _segment(
                  key: const ValueKey('home-list-segment'),
                  active: !mission,
                  label: agents ? 'Agents' : 'Sessions',
                  flips: true,
                  onActiveTap: () => setMobileAgentsList(!agents),
                  dot: sessionsBusy,
                  glyph: AppIcon(agents ? 'agent' : 'list',
                      size: 18,
                      color: mission ? AppColors.fg3 : AppColors.fg1),
                  onTap: onSessions,
                ),
              ),
            ]),
          ),
          const Spacer(),
          if (trailingOrb != null) trailingOrb!,
          RoundBtn(icon: 'settings', tooltip: 'Settings', onTap: onSettings),
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
  Widget build(BuildContext context) {
    final pill = onTitleTap != null || subtitle != null;
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
    final fill = back != null || trailing.isNotEmpty;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: sans(pill ? 14.5 : 16,
                    weight: W.strong, color: AppColors.fg1)),
          ),
          if (chevron) ...[
            const SizedBox(width: 4),
            AppIcon('chevron-down', size: 14, color: AppColors.fg3),
          ],
        ]),
        if (subtitleView != null)
          Padding(padding: const EdgeInsets.only(top: 1), child: subtitleView)
        else if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, color: AppColors.fg3)),
          ),
      ],
    );
    final label = leading == null
        ? text
        : Row(mainAxisSize: MainAxisSize.min, children: [
            leading!,
            const SizedBox(width: 8),
            Flexible(child: text),
          ]);
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          if (back == null && trailing.isNotEmpty && !pill)
            const SizedBox(width: 44)
          else if (back != null)
            RoundBtn(
                icon: menu ? 'menu' : 'chevron-left',
                tooltip: menu ? 'Menu' : 'Back',
                onTap: back),
          if (trailing.length == 2 && !pill) const SizedBox(width: 44),
          if (back != null || (trailing.isNotEmpty && !pill))
            const SizedBox(width: 10),
          Expanded(
            child: pill
                ? Center(
                    child: Semantics(
                      button: onTitleTap != null,
                      onTapHint: onTitleTapHint,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onTitleTap,
                        child: Container(
                          height: 44,
                          constraints: fill
                              ? const BoxConstraints(minWidth: double.infinity)
                              : const BoxConstraints(minWidth: 280),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: _floating(22),
                          child: Align(
                              widthFactor: fill ? null : 1,
                              child:
                                  fill ? label : IntrinsicWidth(child: label)),
                        ),
                      ),
                    ),
                  )
                : Center(child: label),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 10),
            ...trailing,
          ] else if (back != null && !pill) ...[
            const SizedBox(width: 10),
            const SizedBox(width: 44),
          ],
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
  });

  final String title;
  final VoidCallback? onTap;
  final String? tapHint;

  static const _side = 16.0 + 44 + 10;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_side, 8, _side, 8),
        child: Center(
          child: Semantics(
            button: onTap != null,
            label: title,
            hint: tapHint,
            child: Pressable(
              kind: PressKind.card,
              radius: 20,
              enabled: onTap != null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Container(
                  height: 40,
                  constraints: const BoxConstraints(minWidth: 96),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: _floating(20),
                  child: Center(
                    widthFactor: 1,
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style:
                            sans(15, weight: W.strong, color: AppColors.fg1)),
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
  Widget build(BuildContext context) => Container(
        height: 50,
        decoration: _composerLike(25),
        padding: const EdgeInsets.only(left: 18, right: 8),
        child: Row(children: [
          AppIcon('search', size: 16, color: AppColors.fg4),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: sans(15, color: AppColors.fg1),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: sans(15, color: AppColors.fg4),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (_, __) => controller.text.isEmpty
                ? const SizedBox(width: 8)
                : IconBtn('x', size: 36, iconSize: 16, tooltip: 'Clear',
                    onTap: () {
                    controller.clear();
                    onChanged('');
                  }),
          ),
        ]),
      );
}

/// Sessions or agents for the home list: two icons in one floating pill,
/// the active one filled.
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
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Container(
              width: 50,
              height: 50,
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

enum MobileMenuPick { newSession, tasks, usage, machines }

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
        onTap: () => onPick(pick),
        child: SizedBox(
          height: M.minTarget + 8,
          child: Row(children: [
            AppIcon(icon, size: 19, color: AppColors.fg3),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TS.rowTitle())),
            AppIcon('chevron-right', size: 15, color: AppColors.fg4),
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
                      onTap: () => onPick(MobileMenuPick.newSession),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
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
                          const SizedBox(width: 14),
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
                const SizedBox(height: S.s8),
                if (client != null) ...[
                  _row('task', 'Tasks', MobileMenuPick.tasks),
                  _row('analytics', 'Usage', MobileMenuPick.usage),
                ],
                _row('server', 'Machines', MobileMenuPick.machines),
              ]),
        ),
      ),
    );
  }
}
