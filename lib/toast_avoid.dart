import 'package:flutter/material.dart';

/// One registry of the top bars a phone toast must sit below (page bar,
/// attention bar, offline banner). Each [ToastAvoid] reports its bottom edge;
/// the toast top is the lowest bottom plus 8.
class ToastBands {
  ToastBands._();

  /// Lowest registered bottom edge in logical pixels, 0 when none.
  static final ValueNotifier<double> bottom = ValueNotifier<double>(0);
  static final Map<Object, double> _edges = {};

  static void report(Object key, double? edge) {
    if (edge == null) {
      _edges.remove(key);
    } else {
      _edges[key] = edge;
    }
    final next = _edges.values.fold<double>(0, (a, b) => b > a ? b : a);
    if (next != bottom.value) bottom.value = next;
  }
}

/// Registers its child as a top bar. Only bars whose top edge is in the upper
/// quarter of the screen count, so a composer-side bar never moves toasts.
class ToastAvoid extends StatefulWidget {
  const ToastAvoid({super.key, required this.child});
  final Widget child;

  @override
  State<ToastAvoid> createState() => _ToastAvoidState();
}

class _ToastAvoidState extends State<ToastAvoid> {
  final _key = Object();
  bool _queued = false;

  void _measure() {
    _queued = false;
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final screen = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    ToastBands.report(
        _key, top < screen * 0.25 && box.size.height > 0 ? bottom : null);
  }

  @override
  void dispose() {
    // Deferred: dispose can run mid-build and the notifier has listeners.
    final key = _key;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ToastBands.report(key, null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_queued) {
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
    return widget.child;
  }
}
