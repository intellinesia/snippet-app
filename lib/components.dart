import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ambient_loop.dart';
import 'platform.dart';
import 'theme.dart';
import 'screens/action_list.dart' show ActionGroup, ActionRow;
import 'settings_form.dart' show GroupedTiles;
import 'widgets.dart'
    show AppIcon, Btn, BtnVariant, PressKind, Pressable, StatusDot;

enum Tone { neutral, accent, ok, run, danger }

(Color fg, Color bg) toneColors(Tone tone) => switch (tone) {
      Tone.neutral => (AppColors.fg2, AppColors.hover),
      Tone.accent => (AppColors.accent, AppColors.accentBg),
      Tone.ok => (AppColors.ok, AppColors.okBg),
      Tone.run => (AppColors.run, AppColors.runBg),
      Tone.danger => (AppColors.danger, AppColors.dangerBg),
    };

class Tag extends StatelessWidget {
  const Tag(
    this.label, {
    super.key,
    this.tone = Tone.neutral,
    this.icon,
    this.dot = false,
    this.live = false,
    this.mono = false,
  });

  final String label;
  final Tone tone;
  final String? icon;
  final bool dot;
  final bool live;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = toneColors(tone);
    final style = mono
        ? TS.meta(fg).copyWith(fontSize: 11, height: 16 / 11)
        : TS.meta(fg).copyWith(fontWeight: weightFor(W.label));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (live) ...[
          StatusDot(status: 'running', size: 6, color: fg),
          SizedBox(width: S.s6),
        ] else if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          SizedBox(width: S.s6),
        ] else if (icon != null) ...[
          AppIcon(icon!, size: 12, color: fg),
          SizedBox(width: S.s4),
        ],
        Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.tone = Tone.neutral});

  final int count;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = toneColors(tone);
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: EdgeInsets.symmetric(horizontal: S.s6),
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text('$count',
          style:
              TS.meta(fg).copyWith(fontWeight: weightFor(W.label), height: 1)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.count,
    this.tone = Tone.neutral,
    this.action,
    this.onAction,
    this.padding,
  });

  final String title;
  final int? count;
  final Tone tone;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, S.s8),
      child: Row(children: [
        Text(
            kMobile
                ? '${title.toUpperCase()}${count != null ? '  ·  $count' : ''}'
                : title,
            style: kMobile
                ? sans(12, weight: W.label, spacing: 0.7, color: AppColors.fg4)
                : TS.label(AppColors.fg2)),
        if (count != null && !kMobile) ...[
          SizedBox(width: S.s8),
          CountBadge(count!, tone: tone),
        ],
        const Spacer(),
        if (action != null) TextAction(action!, onTap: onAction),
      ]),
    );
  }
}

class TextAction extends StatefulWidget {
  const TextAction(this.label,
      {super.key, this.onTap, this.icon, this.danger = false});

  final String label;
  final bool danger;
  final String? icon;
  final VoidCallback? onTap;

  @override
  State<TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<TextAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.onTap == null
        ? AppColors.fg4
        : widget.danger
            ? AppColors.danger
            : AppColors.accent;
    final color = _hover && widget.onTap != null
        ? (widget.danger ? AppColors.danger : AppColors.accentHover)
        : base;
    return InkWell(
      onTap: widget.onTap,
      onHover: kMobile ? null : (v) => setState(() => _hover = v),
      hoverColor: kMobile ? null : Colors.transparent,
      highlightColor: kMobile ? null : Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        constraints: BoxConstraints(minHeight: kMobile ? M.minTarget : 24),
        padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s8 : S.s4),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.label,
              style: TS.label(color).copyWith(
                  decoration: _hover && widget.onTap != null
                      ? TextDecoration.underline
                      : null,
                  decorationColor: color)),
          if (widget.icon != null) ...[
            SizedBox(width: S.s4),
            AppIcon(widget.icon!, size: 14, color: color),
          ],
        ]),
      ),
    );
  }
}

class SurfaceScope extends InheritedWidget {
  const SurfaceScope({super.key, required this.group, required super.child});

  final Color group;

  static Color groupOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SurfaceScope>()?.group ??
      AppColors.raised;

  @override
  bool updateShouldNotify(SurfaceScope oldWidget) => group != oldWidget.group;
}

class SheetAction {
  const SheetAction(this.icon, this.label, this.onTap,
      {this.danger = false, this.detail, this.section = '', this.tile = false});

  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final String? detail;

  /// Consecutive actions with the same section share a group; on phone a
  /// non-empty section is shown as the group's label.
  final String section;

  /// On phone, shown as a square in the grid above the list.
  final bool tile;
}

class SheetActions extends StatelessWidget {
  const SheetActions(this.actions, {super.key});

  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    if (kMobile) return _phone();
    return _desktop();
  }

  Widget _phone() {
    final tiles = [
      for (final a in actions)
        if (a.tile) a
    ];
    final groups = <List<SheetAction>>[];
    for (final a in actions.where((a) => !a.tile)) {
      final last = groups.isEmpty ? null : groups.last.first;
      if (last == null || last.section != a.section) {
        groups.add([a]);
      } else {
        groups.last.add(a);
      }
    }
    final cols = tiles.length < 4 ? tiles.length : 4;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < tiles.length; i += cols)
        Padding(
          padding: EdgeInsets.only(top: S.s8),
          child: Row(children: [
            for (var j = i; j < i + cols; j++) ...[
              if (j > i) SizedBox(width: S.s8),
              Expanded(
                  child: j < tiles.length
                      ? _ActionTile(tiles[j])
                      : const SizedBox.shrink()),
            ],
          ]),
        ),
      for (var g = 0; g < groups.length; g++)
        ActionGroup(
          label: groups[g].first.section,
          top: g == 0 && tiles.isEmpty
              ? (groups[g].first.section.isEmpty ? 0 : S.s8)
              : null,
          rows: [
            for (final a in groups[g])
              ActionRow(
                  icon: a.icon,
                  label: a.label,
                  detail: a.detail,
                  danger: a.danger,
                  trailing: const SizedBox.shrink(),
                  onTap: a.onTap),
          ],
        ),
    ]);
  }

  Widget _desktop() => ListGroup(children: [
        for (final a in actions)
          InkWell(
            onTap: a.onTap,
            child: SizedBox(
              height: 32,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s12),
                child: Row(children: [
                  SizedBox(
                    width: 20,
                    child: AppIcon(a.icon,
                        size: 16,
                        color: a.onTap == null
                            ? AppColors.fg4
                            : a.danger
                                ? AppColors.danger
                                : AppColors.fg3),
                  ),
                  SizedBox(width: S.s12),
                  Expanded(
                    child: Text(a.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.ui(a.onTap == null
                            ? AppColors.fg4
                            : a.danger
                                ? AppColors.danger
                                : AppColors.fg1)),
                  ),
                ]),
              ),
            ),
          ),
      ]);
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.a);
  final SheetAction a;

  @override
  Widget build(BuildContext context) {
    final color = a.onTap == null
        ? AppColors.fg4
        : a.danger
            ? AppColors.danger
            : AppColors.fg1;
    return Semantics(
      button: true,
      label: a.label,
      child: Pressable(
        enabled: a.onTap != null,
        kind: PressKind.card,
        radius: R.md,
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: a.onTap,
            child: SizedBox(
              height: 76,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(a.icon, size: 22, color: color),
                  SizedBox(height: S.s8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: S.s4),
                    child: Text(a.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.label(color)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pane section's label: the quiet mono line the transcript's cards use.
class PaneLabel extends StatelessWidget {
  const PaneLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s8),
        child: Text(kMobile ? text : text.toUpperCase(),
            style: kMobile
                ? sans(12, color: color ?? AppColors.fg4)
                : TS.overline(color)),
      );
}

class FlatGroupScope extends InheritedWidget {
  const FlatGroupScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FlatGroupScope>() != null;

  @override
  bool updateShouldNotify(FlatGroupScope oldWidget) => false;
}

class CardGroupScope extends InheritedWidget {
  const CardGroupScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardGroupScope>() != null;

  @override
  bool updateShouldNotify(CardGroupScope oldWidget) => false;
}

class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.header});

  final List<Widget> children;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final card = kMobile && CardGroupScope.of(context);
    if (card) {
      return GroupedTiles(children: [if (header != null) header!, ...children]);
    }
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) header!,
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0 || header != null)
            Divider(
                height: 1,
                thickness: 1,
                indent: card ? 16 : (kMobile ? 4 : 0),
                endIndent: card ? 0 : (kMobile ? 4 : 0),
                color: AppColors.line),
          children[i],
        ],
      ],
    );
    if (kMobile) {
      return FlatGroupScope(
        child: Material(color: Colors.transparent, child: column),
      );
    }
    return Material(
      color: SurfaceScope.groupOf(context),
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: column,
    );
  }
}

class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.titleWidget,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? (kMobile
              ? (FlatGroupScope.of(context)
                  ? Colors.transparent
                  : AppColors.surface3)
              : AppColors.accentBg)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? M.rowHeight : 32),
          child: Padding(
            padding: kMobile
                ? EdgeInsets.symmetric(
                    horizontal: FlatGroupScope.of(context) ? S.s4 : S.s16,
                    vertical: S.of(11))
                : EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s6),
            child: Row(children: [
              if (leading != null) ...[leading!, SizedBox(width: S.s12)],
              Expanded(
                child: !kMobile && subtitle != null && subtitle!.isNotEmpty
                    // Desktop rows are one line: the subtitle sits after the title.
                    ? Row(children: [
                        Flexible(
                            child: titleWidget ??
                                Text(title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TS.rowTitle())),
                        SizedBox(width: S.s8),
                        Expanded(
                            child: Text(subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TS.meta())),
                      ])
                    : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget ??
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.rowTitle()),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: S.s2),
                        child: Text(subtitle!,
                            maxLines: kMobile ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.meta()),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: S.s8),
                trailing!,
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.name,
      {super.key, this.size = 36, this.presence, this.ring});

  final String name;
  final double size;
  final bool? presence;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final initial = t.isEmpty ? '?' : t.characters.first.toUpperCase();
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.hover,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Text(initial,
              style: TS
                  .rowTitle(AppColors.fg1)
                  .copyWith(fontSize: size * 0.42, height: 1)),
        ),
        if (presence != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: presence! ? AppColors.ok : AppColors.fg4,
                shape: BoxShape.circle,
                border: Border.all(color: ring ?? AppColors.base, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.tone = Tone.neutral, double? size})
      : _size = size;

  final String icon;
  final Tone tone;
  final double? _size;

  double get size => _size ?? (kMobile ? 36 : 28);

  @override
  Widget build(BuildContext context) {
    var (fg, bg) = toneColors(tone);
    if (kMobile && _size == null) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Center(
            child: AppIcon(icon,
                size: 19, color: tone == Tone.neutral ? AppColors.fg3 : fg)),
      );
    }
    final size = this.size;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kMobile ? 10 : R.sm + 2),
      ),
      child: AppIcon(icon, size: size / 2, color: fg),
    );
  }
}

/// The one working indicator: three dots breathing in turn, never a turning
/// ring. Keeps the square box the old ring took so layouts do not shift.
class Spinner extends StatefulWidget {
  const Spinner({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> {
  final _c = AmbientLoop(const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.bind(context);
    if (reduceMotion(context)) {
      _c.stop(at: 0.2);
    } else {
      _c.start();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Working',
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            child: CustomPaint(
                painter: WorkingDotsPainter(_c, widget.color ?? AppColors.fg3)),
          ),
        ),
      );
}

/// Three dots across the box's middle; each brightens a beat after the last.
class WorkingDotsPainter extends CustomPainter {
  WorkingDotsPainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = (w * 0.1).clamp(1.1, 3.0).toDouble();
    final gap = (w - r * 2) / 2;
    final y = size.height / 2;
    final p = Paint();
    for (var i = 0; i < 3; i++) {
      final phase = (t.value - i * 0.16) % 1.0;
      // A short lift then a long rest reads as a calm pulse.
      final lift = phase < 0.4 ? math.sin(phase / 0.4 * math.pi) : 0.0;
      p.color = color.withValues(alpha: color.a * (0.28 + 0.72 * lift));
      canvas.drawCircle(Offset(r + gap * i, y), r * (0.85 + 0.15 * lift), p);
    }
  }

  @override
  bool shouldRepaint(WorkingDotsPainter old) => old.color != color;
}

class DelayedSpinner extends StatefulWidget {
  const DelayedSpinner({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  State<DelayedSpinner> createState() => _DelayedSpinnerState();
}

class _DelayedSpinnerState extends State<DelayedSpinner> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: Motion.quick,
        child: Spinner(size: widget.size, color: widget.color),
      );
}

class PageLoader extends StatelessWidget {
  const PageLoader({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: label ?? 'Loading',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const DelayedSpinner(),
            if (label != null) ...[
              SizedBox(height: S.s12),
              Text(label!, style: TS.meta()),
            ],
          ]),
        ),
      );
}

/// A soft highlight that drifts across whatever [child] paints; still under
/// reduced motion.
class LoadingSweep extends StatefulWidget {
  const LoadingSweep({super.key, required this.child});

  final Widget child;

  @override
  State<LoadingSweep> createState() => _LoadingSweepState();
}

class _LoadingSweepState extends State<LoadingSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    final glow = AppColors.fg1.withValues(alpha: 0.05);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) {
          final x = -2.0 + 4.0 * Curves.easeInOut.transform(_c.value);
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
              colors: [glow.withValues(alpha: 0), glow, glow.withValues(alpha: 0)],
            ).createShader(rect),
            child: child,
          );
        },
      ),
    );
  }
}

/// The placeholder for content still loading: a quiet tinted block the size
/// of what it stands in for, so nothing jumps when the content lands.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({
    super.key,
    this.width,
    this.height,
    this.radius = 0,
    this.color,
    this.spinner = false,
  });

  final double? width;

  /// Used when the parent leaves the height open; otherwise it fills.
  final double? height;
  final double radius;
  final Color? color;

  /// Show a quiet delayed spinner in the centre when loading takes a moment.
  final bool spinner;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: LayoutBuilder(
          builder: (context, c) {
            final block = LoadingSweep(
              child: Container(
                width: width ?? (c.hasBoundedWidth ? c.maxWidth : null),
                height: height ?? (c.hasBoundedHeight ? c.maxHeight : 160),
                decoration: BoxDecoration(
                  color: color ?? AppColors.tint1,
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
            );
            if (!spinner) return block;
            return Stack(
              alignment: Alignment.center,
              children: [
                block,
                DelayedSpinner(size: 16, color: AppColors.fg4),
              ],
            );
          },
        ),
      );
}

/// A compact inline loading row for cards and text previews without a fixed
/// media slot, avoiding tall empty skeleton blocks.
class LoadingInline extends StatelessWidget {
  const LoadingInline({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.of(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Spinner(size: 13, color: AppColors.fg4),
            SizedBox(width: S.s8),
            Text(label, style: sans(12, color: AppColors.fg3)),
          ]),
        ),
      );
}

/// A one-line failure with a retry, centred in whatever space it is given.
class LoadFailed extends StatelessWidget {
  const LoadFailed({super.key, this.message = 'Couldn’t load', this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(S.s8),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: S.s8,
            runSpacing: S.s4,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('alert-circle', size: 14, color: AppColors.fg4),
                SizedBox(width: S.s6),
                Text(message, style: sans(12, color: AppColors.fg3)),
              ]),
              if (onRetry != null)
                Btn('Retry',
                    small: true, variant: BtnVariant.surface, onTap: onRetry),
            ],
          ),
        ),
      );
}

class Skeleton extends StatelessWidget {
  const Skeleton(
      {super.key,
      this.width,
      this.height = 12,
      this.radius,
      this.color});

  final double? width;
  final double height;
  final double? radius;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color ?? AppColors.raised,
          borderRadius: BorderRadius.circular(radius ?? R.xs),
        ),
      );
}

/// Static placeholder rows that appear only if loading takes over 400 ms, so a
/// fast load never flashes and nothing sweeps or pulses.
class ListSkeleton extends StatefulWidget {
  const ListSkeleton({super.key, this.rows = 4, this.subtitle = true});

  final int rows;
  final bool subtitle;

  @override
  State<ListSkeleton> createState() => _ListSkeletonState();
}

class _ListSkeletonState extends State<ListSkeleton> {
  bool _shown = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  int get rows => widget.rows;
  bool get subtitle => widget.subtitle;

  // Widths from the v17 frame: title bars shrink 182.7 to 88.7, sub bars
  // 117.5 to 78.3, repeating after four rows.
  static const _title = [182.7, 151.4, 120.1, 88.7];
  static const _sub = [117.5, 104.4, 91.3, 78.3];

  @override
  Widget build(BuildContext context) => !_shown
      ? const SizedBox.expand()
      : Semantics(
          label: 'Loading',
          container: true,
          child: ExcludeSemantics(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < rows; i++)
                SizedBox(
                  height: 56,
                  child: Row(children: [
                    const SizedBox(width: 24),
                    Skeleton(
                        width: 28,
                        height: 28,
                        radius: 14,
                        color: AppColors.surface2),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(
                            width: _title[i % 4],
                            height: 8,
                            radius: 4,
                            color: AppColors.surface2),
                        if (subtitle) ...[
                          const SizedBox(height: 6),
                          Skeleton(
                              width: _sub[i % 4],
                              height: 6,
                              radius: 3,
                              color: AppColors.surface1),
                        ],
                      ],
                    ),
                  ]),
                ),
            ]),
          ),
        );
}

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.maxWidth = 720,
    this.topPadding,
  });

  final List<Widget> children;
  final double maxWidth;
  final double? topPadding;

  @override
  Widget build(BuildContext context) {
    final side = kMobile ? S.s16 : S.s24;
    return LayoutBuilder(
      builder: (context, constraints) {
        final extra = (constraints.maxWidth - (maxWidth + side * 2)) / 2;
        final hPad = extra > 0 ? side + extra : side;
        return ListView(
          padding: EdgeInsets.fromLTRB(hPad, topPadding ?? S.s8, hPad, S.s40),
          children: children,
        );
      },
    );
  }
}

class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, 0),
        child: Text(text, style: TS.meta()),
      );
}

class SelectCheck extends StatelessWidget {
  const SelectCheck(this.selected, {super.key, this.size = 18});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: Motion.quick,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.accentFill : Colors.transparent,
          border: Border.all(
              color: selected ? AppColors.accentFill : AppColors.lineStrong,
              width: 1.5),
        ),
        child: selected
            ? AppIcon('check', size: size * 0.66, color: AppColors.accentFg)
            : null,
      );
}

class InlineEditField extends StatelessWidget {
  const InlineEditField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onSubmit,
    required this.onCancel,
    this.hint,
    this.dense = false,
    this.showActions,
    this.commitOnTapOutside = true,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final String? hint;
  final bool dense;
  final bool? showActions;
  final bool commitOnTapOutside;

  @override
  Widget build(BuildContext context) {
    final actions = showActions ?? !kMobile;
    Widget action(String icon, String tip, VoidCallback onTap, Color color) =>
        Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(R.xs),
            onTap: onTap,
            child: SizedBox.square(
              dimension: dense ? 24 : 28,
              child: Center(child: AppIcon(icon, size: 14, color: color)),
            ),
          ),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: Container(
        height: dense ? 30 : (kMobile ? 40 : 34),
        padding: EdgeInsets.fromLTRB(S.s8, 0, actions ? S.s2 : S.s8, 0),
        decoration: BoxDecoration(
          color: AppColors.overlay,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.accent, width: 1.5),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              maxLines: 1,
              style: dense
                  ? TS
                      .label(AppColors.fg1)
                      .copyWith(fontWeight: weightFor(W.body))
                  : TS.ui(AppColors.fg1),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TS.ui(AppColors.fg4),
              ),
              onSubmitted: (_) => onSubmit(),
              onTapOutside: commitOnTapOutside ? (_) => onSubmit() : null,
            ),
          ),
          if (actions) ...[
            action('check', 'Save', onSubmit, AppColors.accent),
            action('x', 'Cancel', onCancel, AppColors.fg3),
          ],
        ]),
      ),
    );
  }
}
