import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';

/// A small text button: 30px of ink on a phone with a 44px hit area around it,
/// 28px on desktop where the pointer is precise.
class CompactBtn extends StatelessWidget {
  const CompactBtn(this.label,
      {super.key, this.onTap, this.primary = false, this.disabled = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.accentFill : AppColors.surface3;
    final fg = primary ? AppColors.accentFg : AppColors.fg2;
    final ink = kMobile ? 30.0 : 28.0;
    final enabled = !disabled && onTap != null;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 24,
        highlightShape: BoxShape.rectangle,
        containedInkWell: true,
        borderRadius: BorderRadius.circular(R.sm),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? M.minTarget : ink),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: ink,
              padding: EdgeInsets.symmetric(horizontal: S.s12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Text(label,
                  style: sans(kMobile ? 13 : 12,
                      weight: W.label, color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}
