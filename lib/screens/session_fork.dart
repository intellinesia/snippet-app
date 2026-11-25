import 'package:flutter/material.dart';

import '../morph_sheet.dart';
import '../theme.dart';
import '../tap_detector.dart';

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
      builder: (ctx) => SessionForkPanel(
          fromLabel: fromLabel,
          total: totalMessages,
          onChoose: (fromHere) => Navigator.of(ctx).pop(fromHere)),
    );

/// The two fork choices and the Fork button, embeddable in a sheet or the
/// phone composer tray. [onChoose] gets true for "From this message".
class SessionForkPanel extends StatefulWidget {
  const SessionForkPanel(
      {super.key, required this.fromLabel, this.total, required this.onChoose});
  final String fromLabel;
  final int? total;
  final ValueChanged<bool> onChoose;
  @override
  State<SessionForkPanel> createState() => _SessionForkPanelState();
}

class _SessionForkPanelState extends State<SessionForkPanel> {
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(10)),
          child: Text(widget.fromLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(13, color: AppColors.fg2)),
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          alignment: Alignment.center,
          child: TextField(
            controller: _title,
            style: sans(15, color: AppColors.fg1),
            cursorColor: AppColors.fg1,
            decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Fork title',
                hintStyle: sans(15, color: AppColors.fg3)),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: 'Fork',
          child: ExcludeSemantics(
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onChoose(true),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border)),
                child: Text('Fork',
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Fork from the start instead',
          child: ExcludeSemantics(
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onChoose(false),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                child: Text('Fork from the start instead',
                    style: sans(15, color: AppColors.fg2)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
