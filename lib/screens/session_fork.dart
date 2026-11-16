import 'package:flutter/material.dart';

import '../morph_sheet.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Fork this conversation" sheet. Resolves true for "From this message",
/// false for "Full history", null when dismissed. [origin] is the tapped
/// chip's global rect (see `globalRectOf`) so the sheet grows out of it.
Future<bool?> showForkSheet(
  BuildContext context, {
  required String fromLabel,
  int? totalMessages,
  Rect? origin,
}) =>
    showMorphSheet<bool>(
      context,
      title: 'Fork this conversation',
      subtitle: 'A new session; this one stays as it is. Files on disk are shared.',
      origin: origin,
      builder: (_) => _ForkBody(fromLabel: fromLabel, total: totalMessages),
    );

class _ForkBody extends StatefulWidget {
  const _ForkBody({required this.fromLabel, this.total});
  final String fromLabel;
  final int? total;
  @override
  State<_ForkBody> createState() => _ForkBodyState();
}

class _ForkBodyState extends State<_ForkBody> {
  bool _fromHere = true;

  Widget _row(bool value, String title, String sub) {
    final on = _fromHere == value;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _fromHere = value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: on ? AppColors.accentBg : Colors.transparent,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: on ? AppColors.accent : AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: on ? AppColors.accent : AppColors.border2, width: 1.5),
              ),
              child: on
                  ? Center(
                      child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: AppColors.accent, shape: BoxShape.circle)))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(true, 'From this message',
            'Keeps everything up to "${widget.fromLabel}"'),
        _row(false, 'Full history',
            total == null ? 'All messages' : 'All $total messages'),
        const SizedBox(height: 4),
        Btn('Fork',
            full: true, onTap: () => Navigator.of(context).pop(_fromHere)),
      ],
    );
  }
}
