import 'dart:async';

import 'package:flutter/material.dart';

import 'platform.dart';
import 'tap_detector.dart';
import 'theme.dart';
import 'toast_avoid.dart';
import 'widgets.dart';

// Toast (spec W2-2 DL-04). Phones: top band under the lowest registered top
// bar plus 8, x16, 48 high cards, at most two stacked, newest on top.

class _ToastData {
  _ToastData(this.id, this.message, this.danger, this.actionLabel,
      this.onAction, this.hold);
  final int id;
  final String message;
  final bool danger;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration hold;
  final dismiss = ValueNotifier<bool>(false);
  final DateTime at = DateTime.now();
}

final _toasts = ValueNotifier<List<_ToastData>>(const []);
OverlayEntry? _host;
int _nextId = 0;

/// Show a transient message. Plain 3 s, with an action 6 s, error 8 s; an
/// identical message within 2 s collapses into one; a third evicts the oldest.
void toast(BuildContext context, String message,
    {bool danger = false, String? actionLabel, VoidCallback? onAction}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final live = _toasts.value;
  final now = DateTime.now();
  if (live.any((t) =>
      t.message == message &&
      t.actionLabel == actionLabel &&
      now.difference(t.at) < const Duration(seconds: 2))) {
    return;
  }
  final hold = Duration(seconds: danger ? 8 : (actionLabel != null ? 6 : 3));
  final data =
      _ToastData(_nextId++, message, danger, actionLabel, onAction, hold);
  var next = [data, ...live];
  if (next.length > 2) {
    next.last.dismiss.value = true;
    next = next.sublist(0, 2);
  }
  _toasts.value = next;
  if (_host == null) {
    _host = OverlayEntry(builder: (_) => const _ToastHost());
    overlay.insert(_host!);
  }
}

@visibleForTesting
void resetToastsForTest() {
  _toasts.value = const [];
  _host = null;
}

void _gone(_ToastData d) {
  _toasts.value = [
    for (final t in _toasts.value)
      if (t.id != d.id) t
  ];
  if (_toasts.value.isEmpty) {
    _host?.remove();
    _host = null;
  }
}

class _ToastHost extends StatelessWidget {
  const _ToastHost();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: ToastBands.bottom,
      builder: (_, band, __) => ValueListenableBuilder<List<_ToastData>>(
        valueListenable: _toasts,
        builder: (_, list, __) {
          final top = (band > mq.padding.top ? band : mq.padding.top) + 8;
          final cards = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _ToastCard(key: ValueKey(list[i].id), data: list[i]),
              ],
            ],
          );
          if (kMobile) {
            return Positioned(left: 16, right: 16, top: top, child: cards);
          }
          return Positioned(
            left: S.s12,
            right: S.s12,
            top: mq.padding.top + 44 + S.s8,
            child: Align(
                alignment: Alignment.topRight,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: cards)),
          );
        },
      ),
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.data});
  final _ToastData data;
  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _timer;
  Duration _left = Duration.zero;
  DateTime _started = DateTime.now();
  double _drag = 0;
  bool _leaving = false;

  _ToastData get d => widget.data;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200))
      ..forward();
    d.dismiss.addListener(_onDismiss);
    _left = d.hold;
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _started = DateTime.now();
    _timer = Timer(_left, _dismiss);
  }

  // The hold clock stops while the card is pressed.
  void _pause() {
    if (_timer == null || !_timer!.isActive) return;
    _timer!.cancel();
    _left -= DateTime.now().difference(_started);
    if (_left < const Duration(seconds: 1)) _left = const Duration(seconds: 1);
  }

  @override
  void dispose() {
    _timer?.cancel();
    d.dismiss.removeListener(_onDismiss);
    _c.dispose();
    super.dispose();
  }

  void _onDismiss() {
    if (d.dismiss.value) _dismiss();
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    if (mounted && !reduceMotion(context)) {
      try {
        await _c.reverse().orCancel;
      } on TickerCanceled {
        // Disposed mid-flight.
      }
    }
    _gone(d);
  }

  // Phone: the kit notice shape, floating. A 20 mark in a 24 slot, a 15
  // line, and a text action with a full target instead of a nested pill.
  Widget _phoneCard(bool hasAction) => Container(
        key: Key('toastCard-${d.message}'),
        constraints: const BoxConstraints(minHeight: 52),
        padding: EdgeInsets.fromLTRB(16, 4, hasAction ? 4 : 16, 4),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Row(children: [
          SizedBox.square(
            dimension: 24,
            child: Center(
              child: AppIcon(d.danger ? 'alert-triangle' : 'check',
                  size: 20, color: AppColors.fg1),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(d.message,
                  maxLines: hasAction ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15, height: 20 / 15, color: AppColors.fg1)
                      .copyWith(decoration: TextDecoration.none)),
            ),
          ),
          if (hasAction)
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                d.onAction?.call();
                _dismiss();
              },
              child: ConstrainedBox(
                key: const Key('toastAction'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(d.actionLabel!,
                        style: sans(15, weight: W.label, color: AppColors.fg1)
                            .copyWith(decoration: TextDecoration.none)),
                  ),
                ),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (reduceMotion(context)) _c.value = 1;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    final hasAction = d.actionLabel != null;
    final style = sans(14,
            weight: d.actionLabel != null ? FontWeight.w400 : FontWeight.w400,
            color: AppColors.fg1)
        .copyWith(decoration: TextDecoration.none);
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        liveRegion: true,
        label: hasAction ? '${d.message}, ${d.actionLabel}' : d.message,
        child: FadeTransition(
          opacity: curve,
          child: AnimatedBuilder(
            animation: curve,
            builder: (_, child) => Transform.translate(
                offset: Offset(0, (curve.value - 1) * 8 + _drag), child: child),
            child: Listener(
              onPointerDown: (_) => _pause(),
              onPointerUp: (_) {
                if (!_leaving && _timer?.isActive == false) _arm();
              },
              onPointerCancel: (_) {
                if (!_leaving && _timer?.isActive == false) _arm();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Swipe up dismisses.
                onVerticalDragUpdate: (u) => setState(() => _drag =
                    (_drag + u.delta.dy).clamp(double.negativeInfinity, 0.0)),
                onVerticalDragEnd: (u) {
                  if (_drag < -16 || (u.primaryVelocity ?? 0) < -300) {
                    _dismiss();
                  } else {
                    setState(() => _drag = 0);
                  }
                },
                child: kMobile
                    ? _phoneCard(hasAction)
                    : Container(
                  key: Key('toastCard-${d.message}'),
                  constraints: BoxConstraints(minHeight: d.danger ? 48 : 36),
                  padding: EdgeInsets.only(left: 16, right: hasAction ? 0 : 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    AppIcon(d.danger ? 'x' : 'check',
                        size: 14, color: AppColors.fg1),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: d.danger ? 12 : 7),
                        child: Text(d.message,
                            maxLines: hasAction ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: style),
                      ),
                    ),
                    if (hasAction)
                      TapDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          d.onAction?.call();
                          _dismiss();
                        },
                        child: Container(
                          key: const Key('toastAction'),
                          width: 60,
                          height: 36,
                          margin: const EdgeInsets.all(6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Text(d.actionLabel!,
                              style:
                                  style.copyWith(fontWeight: FontWeight.w500)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
