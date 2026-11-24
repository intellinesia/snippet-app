import 'package:flutter/material.dart';

import 'platform.dart';

/// Bottom edge (global y) of the lowest registered top bar; 0 when none.
/// Phone toasts sit below it, so a toast never covers a top action.
final ValueNotifier<double> toastTopInset = ValueNotifier<double>(0);

final Map<State, Rect> _bars = {};

void _publish() {
  var bottom = 0.0;
  for (final r in _bars.values) {
    if (r.top < 160 && r.height <= 200 && r.bottom > bottom) bottom = r.bottom;
  }
  if (toastTopInset.value != bottom) toastTopInset.value = bottom;
}

/// Wrap a phone screen's top bar (the strip holding its actions) in this so
/// toasts avoid it. Desktop and unwrapped screens are unaffected.
class ToastAvoid extends StatefulWidget {
  const ToastAvoid({super.key, required this.child});
  final Widget child;

  @override
  State<ToastAvoid> createState() => _ToastAvoidState();
}

class _ToastAvoidState extends State<ToastAvoid> {
  void _measure() {
    if (!mounted || !kMobile) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    _bars[this] = box.localToGlobal(Offset.zero) & box.size;
    _publish();
  }

  @override
  void dispose() {
    _bars.remove(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return widget.child;
  }
}
