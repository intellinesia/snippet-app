import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'controls.dart';
import 'tokens.dart';

/// A top-level phone page: large title with header actions, an optional
/// filter row, then content. Scrolling folds the title into a compact bar
/// (blurred with a hairline on iPhone, a tonal app bar on Android).
class MkPage extends StatefulWidget {
  const MkPage({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.headerTrailing,
    this.filters,
    this.onBack,
    this.controller,
    this.onRefresh,
    this.bottomClearance = true,
  });
  final String title;
  final List<Widget> slivers;
  final List<MkAction> actions;

  /// Replaces [actions] (a split button on Tasks).
  final Widget? headerTrailing;
  final Widget? filters;

  /// Pushed pages get a back button and keep the large title.
  final VoidCallback? onBack;
  final ScrollController? controller;
  final Future<void> Function()? onRefresh;

  /// Leave room for the floating tab bar under the last row.
  final bool bottomClearance;

  @override
  State<MkPage> createState() => _MkPageState();
}

class _MkPageState extends State<MkPage> {
  bool _folded = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final f = n.metrics.pixels > 44;
    if (f != _folded) setState(() => _folded = f);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final a = kAndroidLook;
    final barH = a ? 64.0 : 50.0;
    final trailing = widget.headerTrailing ??
        (widget.actions.isEmpty
            ? null
            : MkActionCluster(actions: widget.actions));
    final back = widget.onBack == null
        ? null
        : MkIconButton(
            icon: a ? 'arrow-left' : 'chevron-left',
            label: 'Back',
            onTap: widget.onBack);
    Widget scroll = CustomScrollView(
      controller: widget.controller,
      physics:
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top + barH)),
        SliverToBoxAdapter(
          child: Semantics(
            header: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(a ? 16 : 20, 0, 20, 0),
              child: Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mkLargeTitle()),
            ),
          ),
        ),
        if (widget.filters != null) SliverToBoxAdapter(child: widget.filters!),
        ...widget.slivers,
        if (widget.bottomClearance)
          SliverToBoxAdapter(
              child: SizedBox(height: MK.bottomClearance(context))),
      ],
    );
    if (widget.onRefresh != null) {
      scroll = RefreshIndicator(
        onRefresh: widget.onRefresh!,
        color: AppColors.fg1,
        backgroundColor: AppColors.surface2,
        edgeOffset: top + barH,
        child: scroll,
      );
    }
    final bar = SizedBox(
      height: top + barH,
      child: Stack(children: [
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _folded ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: a
                ? ColoredBox(color: AppColors.surface1)
                : ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.bg.withValues(alpha: 0.72),
                          border: Border(
                              bottom: BorderSide(
                                  color: AppColors.fg1.withValues(alpha: 0.10),
                                  width: 0.5)),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: top,
          height: barH,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: a ? 4 : 12),
            child: Row(children: [
              if (back != null) back else SizedBox(width: a ? 12 : 4),
              Expanded(
                child: AnimatedOpacity(
                  opacity: _folded ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: a ? TextAlign.start : TextAlign.center,
                      style: a
                          ? sans(22, weight: W.label, color: AppColors.fg1)
                          : sans(16.5,
                              weight: FontWeight.w600, color: AppColors.fg1)),
                ),
              ),
              if (trailing != null) trailing else const SizedBox(width: 44),
            ]),
          ),
        ),
      ]),
    );
    return ColoredBox(
      color: AppColors.bg,
      child: Stack(children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll, child: scroll),
        ),
        Positioned(left: 0, right: 0, top: 0, child: bar),
      ]),
    );
  }
}

/// One tab in [MkTabBar].
class MkTab {
  const MkTab(this.label, this.icon);
  final String label;
  final String icon;
}

/// Floating tab bar. iPhone: a glass capsule with the compose button split
/// out as its own glass-free primary circle. Android: a Material navigation
/// bar with pill indicators and a 56 FAB above it on the right.
class MkTabBar extends StatelessWidget {
  const MkTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onCompose,
    this.onComposeLong,
    this.attention = const {},
    this.composeIcon = 'edit',
    this.composeLabel = 'New',
    this.androidFab = true,
  });
  final List<MkTab> tabs;
  final int? selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onCompose;
  final VoidCallback? onComposeLong;

  /// Tab indexes with something waiting: an amber dot on the icon.
  final Set<int> attention;
  final String composeIcon;
  final String composeLabel;

  /// Android only: off where the page carries its own primary action
  /// (Tasks has the New task split button).
  final bool androidFab;

  @override
  Widget build(BuildContext context) =>
      kAndroidLook ? _android(context) : _ios(context);

  Widget _fab(double d, BorderRadius r, List<BoxShadow> shadow) => Semantics(
        button: true,
        label: composeLabel,
        hint: 'Session, agent, group, shell or task',
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCompose,
          onLongPress: onComposeLong,
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
                color: AppColors.fg1, borderRadius: r, boxShadow: shadow),
            child: Center(
                child: AppIcon(composeIcon, size: 24, color: MK.onPrimary)),
          ),
        ),
      );

  Widget _icon(int i, bool on, double size) => Stack(
        clipBehavior: Clip.none,
        children: [
          AppIcon(tabs[i].icon,
              size: size,
              color: on ? AppColors.fg1 : AppColors.fg2,
              filled: on),
          if (attention.contains(i))
            Positioned(
              right: -3,
              top: -1,
              child: Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: MK.amber, shape: BoxShape.circle)),
            ),
        ],
      );

  Widget _tabSemantics(int i, Widget child) => Semantics(
        button: true,
        selected: i == selected,
        label: '${tabs[i].label} tab, ${i + 1} of ${tabs.length}',
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(i),
          child: child,
        ),
      );

  Widget _ios(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final clamp = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom - 10 : 16),
      child: Row(children: [
        Expanded(
          child: MkGlass(
            radius: MK.tabBar / 2,
            child: SizedBox(
              height: MK.tabBar,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Row(children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _tabSemantics(
                        i,
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 52,
                          decoration: BoxDecoration(
                            color: i == selected
                                ? MK.selectedTab
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _icon(i, i == selected, 22),
                              const SizedBox(height: 2),
                              Text(tabs[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  textScaler: clamp,
                                  style: sans(10.5,
                                      height: 1.2,
                                      weight: W.label,
                                      color: i == selected
                                          ? AppColors.fg1
                                          : AppColors.fg2)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _fab(MK.fab, BorderRadius.circular(MK.fab / 2), const [
          BoxShadow(
              color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 8)),
        ]),
      ]),
    );
  }

  Widget _android(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final clamp = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (androidFab)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
            child: _fab(MK.androidFab, BorderRadius.circular(16), const [
              BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 6)),
            ]),
          ),
        Container(
          color: AppColors.surface1,
          padding: EdgeInsets.fromLTRB(8, 12, 8, bottom + 16),
          child: Row(children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: _tabSemantics(
                  i,
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      height: 32,
                      decoration: BoxDecoration(
                        color: i == selected ? MK.tonal : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(child: _icon(i, i == selected, 22)),
                    ),
                    const SizedBox(height: 4),
                    Text(tabs[i].label,
                        maxLines: 1,
                        textScaler: clamp,
                        style: sans(12,
                            weight: W.label,
                            color:
                                i == selected ? AppColors.fg1 : AppColors.fg2)),
                  ]),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Conversation header: back, a title pill with the character, trailing
/// action. Glass circles and pill on iPhone; a Material app bar on Android.
class MkChatHeader extends StatelessWidget {
  const MkChatHeader({
    super.key,
    required this.title,
    this.avatar,
    this.subtitle,
    this.onBack,
    this.onTitle,
    this.actions = const [],
  });
  final String title;
  final Widget? avatar;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onTitle;
  final List<MkAction> actions;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final a = kAndroidLook;
    final back = MkIconButton(
        icon: a ? 'arrow-left' : 'chevron-left',
        label: 'Back',
        size: a ? 48 : 44,
        onTap: onBack ?? () => Navigator.maybePop(context));
    final titleText = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          a ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: a
                ? sans(18, weight: W.label, color: AppColors.fg1)
                : sans(15, weight: FontWeight.w600, color: AppColors.fg1)),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg3)),
      ],
    );
    final Widget middle;
    if (a) {
      middle = Row(children: [
        if (avatar != null) ...[
          SizedBox.square(dimension: 36, child: avatar),
          const SizedBox(width: 10),
        ],
        Flexible(child: titleText),
      ]);
    } else {
      middle = Center(
        child: MkGlass(
          radius: 22,
          child: Container(
            height: 44,
            padding: EdgeInsets.fromLTRB(avatar == null ? 16 : 6, 0, 16, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (avatar != null) ...[
                SizedBox.square(dimension: 32, child: avatar),
                const SizedBox(width: 8),
              ],
              Flexible(child: titleText),
            ]),
          ),
        ),
      );
    }
    final trailing = [
      for (final x in actions)
        MkIconButton(
            icon: x.icon, label: x.label, onTap: x.onTap, size: a ? 48 : 44)
    ];
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        height: a ? 64 : 56,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: a ? 4 : 14),
          child: Row(children: [
            back,
            SizedBox(width: a ? 4 : 8),
            Expanded(
              child: Semantics(
                button: onTitle != null,
                label: title,
                child: TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTitle,
                  child: middle,
                ),
              ),
            ),
            SizedBox(width: a ? 4 : 8),
            if (trailing.isEmpty) SizedBox(width: a ? 48 : 44) else ...trailing,
          ]),
        ),
      ),
    );
  }
}

/// The rounded surface a conversation thread sits in, under the header.
class MkThreadSurface extends StatelessWidget {
  const MkThreadSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ColoredBox(color: AppColors.surface1, child: child),
      );
}

/// Height of the phone chat header under the status bar (board: 56 / 64).
double get mkChatHeaderHeight => kAndroidLook ? 64 : 56;

/// Board: the chat header starts 5 above the status inset (iPhone controls
/// centre at 82, the thread begins at 116; Android 108).
const double mkChatHeaderLift = 5;

/// Thread top below the unlifted header box: board gap 6 / 4, less the lift.
double get _threadGap => (kAndroidLook ? 4 : 6) - mkChatHeaderLift;

/// Lifts a phone chat header by [mkChatHeaderLift].
Widget mkLiftHeader(Widget header) => Transform.translate(
    offset: const Offset(0, -mkChatHeaderLift), child: header);

/// The rounded thread surface behind a phone chat: page ground above, a
/// surface1 sheet with 28 top corners starting just under the header.
class MkThreadBackdrop extends StatelessWidget {
  const MkThreadBackdrop(
      {super.key, required this.child, this.enabled = true, this.statusTop});
  final Widget child;
  final bool enabled;

  /// Status bar height when the host has already consumed the padding.
  final double? statusTop;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final top = (statusTop ?? MediaQuery.paddingOf(context).top) +
        mkChatHeaderHeight +
        _threadGap;
    final status = statusTop ?? MediaQuery.paddingOf(context).top;
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: AppColors.bg),
      Positioned(
        top: top,
        left: 0,
        right: 0,
        bottom: 0,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ColoredBox(color: AppColors.surface1),
        ),
      ),
      child,
      // Nothing scrolls into the status bar either.
      Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: status,
          child: IgnorePointer(child: ColoredBox(color: AppColors.bg))),
    ]);
  }
}

/// The phone chat header layer: solid ground down to the thread, then the
/// thread's 28 top corners cut out of it.
abstract final class MkThreadCap {
  /// How far below the header the layer reaches.
  static double get reach => _threadGap + 28;

  static Widget paint(Color bg) => CustomPaint(painter: _CapPainter(bg));
}

class _CapPainter extends CustomPainter {
  _CapPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = size.height - 28;
    final band = Path()..addRect(Rect.fromLTWH(0, 0, size.width, edge));
    final corners = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, edge, size.width, 28)),
      Path()
        ..addRRect(RRect.fromRectAndCorners(
            Rect.fromLTWH(0, edge, size.width, 56),
            topLeft: const Radius.circular(28),
            topRight: const Radius.circular(28))),
    );
    canvas.drawPath(band, Paint()..color = color);
    canvas.drawPath(corners, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CapPainter old) => old.color != color;
}

/// Modal sheet. iPhone: a floating glass card inset 8 from the edges with
/// 38 corners. Android: a bottom sheet with 28 top corners and a handle.
Future<T?> showMkSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool scrollable = true,
}) {
  final a = kAndroidLook;
  return showModalBottomSheet<T>(
    sheetAnimationStyle: sheetMotion,
    context: context,
    isScrollControlled: scrollable,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: a ? 0.32 : 0.45),
    elevation: 0,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      final inset = MediaQuery.viewInsetsOf(ctx).bottom;
      final body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: a ? 32 : 36,
              height: a ? 4 : 5,
              margin: EdgeInsets.only(bottom: a ? 20 : 14),
              decoration: BoxDecoration(
                color: a ? AppColors.fg4 : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(title,
                  textAlign: a ? TextAlign.start : TextAlign.center,
                  style: a
                      ? sans(22, weight: W.label, color: AppColors.fg1)
                      : sans(17,
                          weight: FontWeight.w600, color: AppColors.fg1)),
            ),
          Flexible(child: builder(ctx)),
        ],
      );
      if (a) {
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: Container(
            decoration: BoxDecoration(
              color: Color.lerp(AppColors.surface1, AppColors.surface2, 0.5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(16, 14, 16, bottom + 20),
            child: body,
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, (inset > 0 ? inset : bottom) + 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(38),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: const Color(0xB830302D),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
              child: body,
            ),
          ),
        ),
      );
    },
  );
}

/// Sheet tiles two to a row, 8 apart (board "+" sheet).
class MkTileGrid extends StatelessWidget {
  const MkTileGrid({super.key, required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
            ]),
          ],
        ],
      );
}

/// A grid pill inside a sheet (Photos, Files, Camera): 56 high, 28 corners.
class MkSheetTile extends StatelessWidget {
  const MkSheetTile(
      {super.key, required this.icon, required this.label, this.onTap});
  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: kAndroidLook
                  ? AppColors.surface3
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(children: [
              AppIcon(icon, size: 21, color: AppColors.fg2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
              ),
            ]),
          ),
        ),
      );
}
