import 'package:flutter/material.dart';

import '../morph_sheet.dart';
import '../platform.dart';
import '../theme.dart';
import '../tap_detector.dart';
import '../widgets.dart';

/// The user's fork choice: [fromHere] is true for "From this message", false
/// for the full history; [title] is the optional name typed for the fork.
typedef ForkChoice = ({bool fromHere, String title});

/// "Fork this conversation" sheet; null when dismissed. [latest] means the
/// cut is the latest message, so only one Fork button is offered. [origin]
/// is the tapped chip's global rect (see `globalRectOf`) so the sheet grows
/// out of it.
Future<ForkChoice?> showForkSheet(
  BuildContext context, {
  required String fromLabel,
  int? totalMessages,
  Rect? origin,
  bool latest = false,
}) =>
    showMorphSheet<ForkChoice>(
      context,
      title: 'Fork this conversation',
      subtitle:
          'A new session; this one stays as it is. Files on disk are shared.',
      origin: origin,
      builder: (ctx) => SessionForkPanel(
          fromLabel: fromLabel,
          total: totalMessages,
          latest: latest,
          onChoose: (fromHere, title) =>
              Navigator.of(ctx).pop((fromHere: fromHere, title: title))),
    );

/// The fork choices and title field, embeddable in a sheet or the phone
/// composer tray. [onChoose] gets true for "From this message" and the typed
/// title. With [latest] both choices are the same cut, so one Fork button.
class SessionForkPanel extends StatefulWidget {
  const SessionForkPanel(
      {super.key,
      required this.fromLabel,
      this.total,
      this.latest = false,
      required this.onChoose});
  final String fromLabel;
  final int? total;
  final bool latest;
  final void Function(bool fromHere, String title) onChoose;
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

  void _choose(bool fromHere) => widget.onChoose(fromHere, _title.text);

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
          constraints: BoxConstraints(minHeight: kMobile ? 48 : 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          alignment: Alignment.center,
          child: TextField(
            controller: _title,
            style: sans(kMobile ? 15 : 13, color: AppColors.fg1),
            cursorColor: AppColors.fg1,
            decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Fork title',
                hintStyle: sans(kMobile ? 15 : 13, color: AppColors.fg3)),
          ),
        ),
        const SizedBox(height: 12),
        if (!kMobile)
          Row(children: [
            Btn('Fork', small: true, onTap: () => _choose(true)),
            if (!widget.latest) ...[
              const SizedBox(width: 8),
              Btn('Fork from the start instead',
                  small: true,
                  variant: BtnVariant.ghost,
                  onTap: () => _choose(false)),
            ],
          ])
        else ...[
          Semantics(
            button: true,
            label: 'Fork',
            child: ExcludeSemantics(
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _choose(true),
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
          if (!widget.latest)
            Semantics(
              button: true,
              label: 'Fork from the start instead',
              child: ExcludeSemantics(
                child: TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _choose(false),
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
      ],
    );
  }
}
