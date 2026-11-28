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
    sheetAnimationStyle: sheetMotion,
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
    // The platform sheet; tabs and body sit on its fill.
    return AppSheetSurface(
      child: Container(
        height: 260 + bottom,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
        child: Column(children: [
          SizedBox(
            height: 40,
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
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tab == i ? AppColors.surface3 : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
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
                    style: mono(12.5,
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
