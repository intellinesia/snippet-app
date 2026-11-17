import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gesture_physics.dart';
import '../theme.dart';
import '../widgets.dart';
import 'composer_pill.dart';

/// Open state and current page of the phone composer tray. Also the
/// [TapRegion] group shared by the tray and the "+" that toggles it.
class ComposerTrayController extends ChangeNotifier {
  static const menu = 'menu';

  bool _open = false;
  String _view = menu;

  /// How far the tray is open, 0 to about 1.05 on the spring; drives the "+".
  final ValueNotifier<double> progress = ValueNotifier(0);

  bool get open => _open;
  String get view => _view;

  void toggle() => _open ? close() : _show(menu);

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  /// Swaps the tray's content in place, opening it if needed.
  void show(String view) => _show(view);

  /// Back steps out of a sub-page first, then closes.
  void back() => _view != menu ? _show(menu) : close();

  void _show(String view) {
    if (_open && _view == view) return;
    _open = true;
    _view = view;
    notifyListeners();
  }

  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }
}

/// The grouped sheet the "+" opens: it rises out of the composer on a spring,
/// dims the page behind it, and swaps its content in place for sub-pages.
class ComposerTray extends StatefulWidget {
  const ComposerTray(
      {super.key, required this.controller, required this.child, this.bleed});

  final ComposerTrayController controller;

  /// The current page; keyed by [ComposerTrayController.view] for the swap.
  final Widget child;

  /// How far the sheet reaches past the composer's side insets.
  final double? bleed;

  @override
  State<ComposerTray> createState() => _ComposerTrayState();
}

class _ComposerTrayState extends State<ComposerTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _k = AnimationController.unbounded(
      vsync: this, value: widget.controller.open ? 1 : 0)
    ..addListener(_tick);

  bool _wasOpen = false;
  Widget? _shown;
  String? _shownView;

  @override
  void initState() {
    super.initState();
    _wasOpen = widget.controller.open;
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(ComposerTray old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  void _tick() {
    widget.controller.progress.value = _k.value.clamp(0.0, 1.2);
    if (mounted) setState(() {});
  }

  void _onController() {
    final open = widget.controller.open;
    if (open == _wasOpen) return;
    _wasOpen = open;
    if (open) HapticFeedback.selectionClick();
    if (reduceMotion(context)) {
      _k.value = open ? 1 : 0;
    } else {
      springTo(_k, open ? 1 : 0, _k.velocity,
          spring: C7.tray, epsilon: 0.001);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _k.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final calm = reduceMotion(context);
    if (c.open) {
      _shown = widget.child;
      _shownView = c.view;
    }
    final k = math.max(0.0, _k.value);
    final shown = _shown;
    final Widget body;
    if ((k <= 0.001 && !c.open) || shown == null) {
      body = const SizedBox.shrink();
    } else {
      final content = Padding(
        padding: EdgeInsets.only(bottom: S.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: EdgeInsets.only(top: S.s8, bottom: S.s12),
                decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            AnimatedSize(
              duration: calm ? Duration.zero : Motion.base,
              curve: Motion.enter,
              alignment: Alignment.bottomCenter,
              child: AnimatedSwitcher(
                duration: calm ? Duration.zero : Motion.fast,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.bottomCenter,
                  children: [...previous, if (current != null) current],
                ),
                child: KeyedSubtree(key: ValueKey(_shownView), child: shown),
              ),
            ),
          ],
        ),
      );
      body = TapRegion(
        groupId: c,
        onTapOutside: (_) => c.close(),
        child: CustomPaint(
          painter: _SheetPainter(
            open: k.clamp(0.0, 1.0),
            bleed: widget.bleed ?? M.gutter,
            sheet: AppColors.bg,
            edge: AppColors.border2,
          ),
          child: ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: calm ? (c.open ? 1 : 0) : k,
              child: _TrayMotion(
                  k: calm ? 1 : k, calm: calm, child: content),
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: !c.open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: body,
    );
  }
}

/// Paints the dim above the sheet and the sheet itself past the composer's
/// insets, so the tray reads as a full-width sheet without leaving the column.
class _SheetPainter extends CustomPainter {
  _SheetPainter(
      {required this.open,
      required this.bleed,
      required this.sheet,
      required this.edge});

  final double open;
  final double bleed;
  final Color sheet;
  final Color edge;

  static const _far = 6000.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (open <= 0) return;
    canvas.drawRect(
        Rect.fromLTRB(-bleed - _far, -_far, size.width + bleed + _far, 20),
        Paint()..color = const Color(0xFF000000).withValues(alpha: 0.45 * open));
    final r = RRect.fromRectAndCorners(
      Rect.fromLTRB(-bleed, 0, size.width + bleed, size.height + _far),
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
    );
    canvas.drawRRect(r, Paint()..color = sheet);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-bleed - 1, -1, size.width + bleed + 1, 24));
    canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = edge);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.open != open ||
      old.bleed != bleed ||
      old.sheet != sheet ||
      old.edge != edge;
}

class _TrayMotion extends InheritedWidget {
  const _TrayMotion(
      {required this.k, required this.calm, required super.child});

  final double k;
  final bool calm;

  @override
  bool updateShouldNotify(_TrayMotion old) => old.k != k || old.calm != calm;
}

/// One staggered block in the tray: it fades and rises 10px as the tray opens.
class ComposerTrayItem extends StatelessWidget {
  const ComposerTrayItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = context.dependOnInheritedWidgetOfExactType<_TrayMotion>();
    if (m == null || m.calm) return child;
    final o = ((m.k - 0.2 - index * 0.08) / 0.5).clamp(0.0, 1.0);
    if (o >= 1) return child;
    return Opacity(
      opacity: o,
      child: Transform.translate(
        offset: Offset(0, (1 - o) * 10),
        child: Transform.scale(scale: 0.96 + 0.04 * o, child: child),
      ),
    );
  }
}

/// One tray action on its own surface: icon, label, an optional line under
/// it, a value on the right and a chevron when it opens something further.
class ComposerTrayRow extends StatelessWidget {
  const ComposerTrayRow(
      {super.key,
      required this.icon,
      required this.label,
      this.subtitle,
      this.value,
      this.chevron = false,
      this.color,
      required this.onTap});

  final String icon;
  final String label;
  final String? subtitle;
  final String? value;
  final bool chevron;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: C7.row,
        child: InkWell(
          onTap: () {
            tapHaptic();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              AppIcon(icon, size: 22, color: color ?? AppColors.fg2),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(17,
                            height: 22 / 17, color: color ?? AppColors.fg1)),
                    if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(15, height: 20 / 15, color: AppColors.fg3)),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                Text(value!,
                    style: sans(15, color: AppColors.fg3, tabular: true)),
              ],
              if (chevron) ...[
                const SizedBox(width: 10),
                AppIcon('chevron-right', size: 16, color: AppColors.fg4),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A small heading over a tray group, in the sheet's quiet voice.
class ComposerTrayHeading extends StatelessWidget {
  const ComposerTrayHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(15, height: 20 / 15, color: AppColors.fg3)),
      );
}

/// A sub-page's back and title row, with an optional line beneath.
class ComposerTrayHeader extends StatelessWidget {
  const ComposerTrayHeader(
      {super.key, required this.title, this.subtitle, required this.onBack});

  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Semantics(
            button: true,
            label: 'Back',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onBack,
                customBorder: const CircleBorder(),
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                      child: AppIcon('chevron-left',
                          size: 20, color: AppColors.fg2)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(title,
                style: sans(17, weight: W.label, color: AppColors.fg1)),
          ),
        ]),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(subtitle!,
                style: sans(15, height: 20 / 15, color: AppColors.fg3)),
          ),
      ],
    );
  }
}
