import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ambient/controller.dart';
import '../api.dart';
import '../glass.dart';
import '../mochi.dart';
import '../models.dart';
import '../motion_routes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_voice_page.dart';
import 'tasks/task_common.dart' show TaskFeed;
import 'tasks/tasks_panel.dart';

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
  });

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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: Stack(clipBehavior: Clip.none, children: [
              Glass(
                radius: null,
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  child:
                      child ?? AppIcon(icon!, size: iconSize, color: AppColors.fg2),
                ),
              ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentFill,
                        borderRadius: BorderRadius.circular(8),
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
}

class ListeningPill extends StatelessWidget {
  const ListeningPill({super.key, this.onTap});

  final VoidCallback? onTap;

  static const _heights = [5.0, 11.0, 7.0, 9.0];

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: AppColors.ok.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _heights.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Container(
                  width: 2,
                  height: _heights[i],
                  decoration: BoxDecoration(
                    color: AppColors.ok,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text('Listening', style: TS.caption(AppColors.ok).copyWith(height: 1)),
      ]),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: 'Voice',
      child: GestureDetector(
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 6, M.gutter, 6),
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
                    size: 40,
                    iconSize: 20,
                    onTap: onBack,
                  )
                else
                  RoundBtn(
                    tooltip: 'Mission Control',
                    size: 40,
                    badgeCount: mcBadgeCount,
                    onTap: onMc,
                    child: MochiIcon(color: AppColors.fg1, size: 22),
                  ),
                const Spacer(),
                if (listening) ...[
                  ListeningPill(
                    onTap: onListening ?? () => openMobileVoicePage(context),
                  ),
                  if (trailing.isNotEmpty) const SizedBox(width: 10),
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
      backgroundColor: AppColors.bg,
      body: SafeArea(child: TasksPanel(client: client, phoneHeader: true)),
    ),
  ));
}

class MobileMissionBar extends StatefulWidget {
  const MobileMissionBar({
    super.key,
    required this.onBack,
    this.onActions,
    this.onTasks,
    this.client,
    this.tasksBadgeCount,
  });

  final VoidCallback onBack;
  final VoidCallback? onActions;
  final VoidCallback? onTasks;
  final DaemonClient? client;
  final int? tasksBadgeCount;

  @override
  State<MobileMissionBar> createState() => _MobileMissionBarState();
}

class _MobileMissionBarState extends State<MobileMissionBar> {
  TaskFeed? _feed;

  @override
  void initState() {
    super.initState();
    _syncFeed();
  }

  @override
  void didUpdateWidget(covariant MobileMissionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        (oldWidget.tasksBadgeCount == null) !=
            (widget.tasksBadgeCount == null)) {
      _feed?.dispose();
      _feed = null;
      _syncFeed();
    }
  }

  void _syncFeed() {
    if (widget.tasksBadgeCount != null || widget.client == null) return;
    _feed = TaskFeed(widget.client!, onChange: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _feed?.dispose();
    super.dispose();
  }

  int get _badgeCount {
    final override = widget.tasksBadgeCount;
    if (override != null) return override;
    var count = 0;
    for (final t in _feed?.tasks ?? const <TaskItem>[]) {
      if (t.status == TaskStatus.inReview ||
          t.status == TaskStatus.blocked ||
          t.status == TaskStatus.failed) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final openTasks = widget.onTasks ??
        (widget.client == null
            ? null
            : () => openMobileTasksPage(context, widget.client!));
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: M.gutter),
        child: Row(children: [
          RoundBtn(
            icon: 'chevron-left',
            tooltip: 'Back',
            size: 40,
            iconSize: 20,
            onTap: widget.onBack,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Center(
              child: Semantics(
                button: widget.onActions != null,
                label: 'Mission Control',
                hint: 'Session actions',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onActions,
                  child: Glass(
                    radius: BorderRadius.circular(20),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        MochiIcon(size: 20, color: AppColors.fg1),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            'Mission Control',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.ui(AppColors.fg1).copyWith(
                                fontSize: 14,
                                fontWeight: W.strong,
                                height: 1.2),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (widget.client != null) ...[
            ListenableBuilder(
              listenable: AmbientController.instance,
              builder: (context, _) {
                final live = AmbientController.instance.running;
                return RoundBtn(
                  tooltip: live ? 'Voice call' : 'Start voice',
                  size: 40,
                  onTap: () => startMobileVoice(context, widget.client!),
                  child: AppIcon('phone',
                      size: 18,
                      color: live ? AppColors.ok : AppColors.fg1),
                );
              },
            ),
            const SizedBox(width: 10),
          ],
          RoundBtn(
            icon: 'task',
            tooltip: 'Tasks',
            size: 40,
            iconSize: 18,
            badgeCount: _badgeCount,
            onTap: openTasks,
          ),
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
    final pill =
        onTitleTap != null || subtitle != null || subtitleView != null;
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
                textAlign: TextAlign.center,
                style: pill
                    ? TS.ui(AppColors.fg1).copyWith(
                        fontSize: 15, fontWeight: W.strong, height: 1.25)
                    : sans(16, weight: W.strong, color: AppColors.fg1)),
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
            const SizedBox(width: 8),
            Flexible(child: text),
          ]);
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: M.gutter),
        child: Row(children: [
          if (back == null && trailing.isNotEmpty && !pill)
            const SizedBox(width: 40)
          else if (back != null)
            RoundBtn(
                icon: menu ? 'menu' : 'chevron-left',
                tooltip: menu ? 'Menu' : 'Back',
                size: 40,
                iconSize: menu ? 18 : 20,
                onTap: back),
          if (trailing.length == 2 && !pill) const SizedBox(width: 40),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          child: IntrinsicWidth(child: label),
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
            const SizedBox(width: 40),
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
    this.subtitle,
  });

  final String title;
  final String? subtitle;
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
                  height: subtitle == null ? 40 : 44,
                  constraints: const BoxConstraints(minWidth: 96),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
        radius: BorderRadius.circular(22),
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: 18, right: 8),
          child: Row(children: [
            AppIcon('search', size: 16, color: AppColors.fg4),
            const SizedBox(width: 10),
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
                  ? const SizedBox(width: 8)
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
          child: GestureDetector(
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
