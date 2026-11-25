import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'toast_avoid.dart';

/// Phone top zone (spec 3 rule G): page bar, then the attention bar, then
/// floating layers. Bars register their bottom edge here; banners and the
/// toast read one number from it.
class TopZone {
  TopZone._();

  /// Page bar height below the status bar (spec A, SH-10).
  static const pageBarHeight = 52.0;

  /// Gap between the lowest bar and a floating layer.
  static const gap = 8.0;

  /// The one registry: shared with the toast (ToastBands in toast_avoid.dart).
  static ValueNotifier<double> get lowestBar => ToastBands.bottom;

  /// Pages that own the needs-you surface themselves (chat, session, viewers).
  static final ValueNotifier<int> attentionHolds = ValueNotifier(0);

  static void register(Object key, double bottom) =>
      ToastBands.report(key, bottom);

  static void unregister(Object key) => ToastBands.report(key, null);

  /// Bottom of the status bar plus the page bar.
  static double pageBarBottom(BuildContext context) =>
      MediaQuery.paddingOf(context).top + pageBarHeight;

  /// Top edge of the first floating layer: lowest registered bar plus 8.
  static double floatTop(BuildContext context) =>
      math.max(lowestBar.value, MediaQuery.paddingOf(context).top) + gap;

  @visibleForTesting
  static void reset() {
    for (final k in ['page', 'attention', 'attention-bar']) {
      ToastBands.report(k, null);
    }
    attentionHolds.value = 0;
  }
}

/// Wrap a composer page (chat, session, full-screen viewer) so the phone
/// attention bar hides while it is on screen.
class AttentionBarHidden extends StatefulWidget {
  const AttentionBarHidden({super.key, required this.child});
  final Widget child;

  @override
  State<AttentionBarHidden> createState() => _AttentionBarHiddenState();
}

class _AttentionBarHiddenState extends State<AttentionBarHidden> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => TopZone.attentionHolds.value = TopZone.attentionHolds.value + 1);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => TopZone.attentionHolds.value = TopZone.attentionHolds.value - 1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
