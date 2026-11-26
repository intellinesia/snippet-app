import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';
import '../tap_detector.dart';

/// TC-24: compact phone tool-output sheet. The active tab owns the scrolling
/// body; Copy grabs that tab's contents.
Future<void> showToolOutputSheet(
  BuildContext context, {
  required String input,
  required String output,
  required String error,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => ToolOutputSheet(input: input, output: output, error: error),
  );
}

class ToolOutputSheet extends StatefulWidget {
  const ToolOutputSheet({
    super.key,
    required this.input,
    required this.output,
    required this.error,
  });

  final String input;
  final String output;
  final String error;

  @override
  State<ToolOutputSheet> createState() => _ToolOutputSheetState();
}

class _ToolOutputSheetState extends State<ToolOutputSheet> {
  var _tab = 1;

  String get _text => switch (_tab) {
        0 => widget.input,
        2 => widget.error,
        _ => widget.output,
      };

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 12),
      child: Container(
        height: 208,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          SizedBox(
            height: 30,
            child: Row(children: [
              for (final (i, label) in const [
                (0, 'Input'),
                (1, 'Output'),
                (2, 'Error'),
              ]) ...[
                if (i > 0) const SizedBox(width: 6),
                TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tab == i ? AppColors.surface2 : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(label,
                        style: sans(12,
                            weight: W.label,
                            color: _tab == i ? AppColors.fg1 : AppColors.fg3)),
                  ),
                ),
              ],
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(_text.trim().isEmpty ? 'No output' : _text,
                    style: mono(11,
                        height: 1.45,
                        color: _text.trim().isEmpty
                            ? AppColors.fg3
                            : AppColors.fg1)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Clipboard.setData(ClipboardData(text: _text));
              toast(context, 'Copied');
            },
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Copy',
                  style: sans(12.5, weight: W.label, color: AppColors.fg1)),
            ),
          ),
        ]),
      ),
    );
  }
}
