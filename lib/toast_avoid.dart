import 'package:flutter/material.dart';

/// Pass-through kept for callers; phone toasts dock in their own top band in
/// NotificationPopovers so no per-bar inset tracking is needed.
class ToastAvoid extends StatelessWidget {
  const ToastAvoid({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
