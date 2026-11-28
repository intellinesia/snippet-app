import 'package:flutter/material.dart';

import '../theme.dart';

/// Where "Use draft" on a draft card sends its text: the composer of the chat
/// on screen. The chat registers itself while mounted.
class DraftSink {
  static void Function(String text)? _use;
  static Object? _owner;

  static void register(Object owner, void Function(String text) use) {
    _owner = owner;
    _use = use;
  }

  static void unregister(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      _use = null;
    }
  }

  /// Puts [text] in the composer and focuses it; false when no chat is open.
  static bool use(String text) {
    final f = _use;
    if (f == null) return false;
    f(text);
    return true;
  }
}

/// Phone spec CH-20 buttons: Use draft 225 wide, Dismiss 100, both 48 high.
class DraftActions extends StatelessWidget {
  const DraftActions({super.key, required this.onUse, required this.onDismiss});

  final VoidCallback onUse;
  final VoidCallback onDismiss;

  Widget _btn(String label, VoidCallback onTap, bool primary, Color fg,
          Color bg, Color border) =>
      Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: primary ? BorderSide.none : BorderSide(color: border),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6)),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14, fontWeight: weightFor(FontWeight.w500), color: fg)),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          flex: 225,
          child: _btn('Use draft', onUse, true, AppColors.bg, AppColors.fg1,
              Colors.transparent)),
      const SizedBox(width: 8),
      Expanded(
          flex: 100,
          child: _btn('Dismiss', onDismiss, false, AppColors.fg1,
              AppColors.surface2, AppColors.border)),
    ]);
  }
}
