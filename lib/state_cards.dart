import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat/ask_kit.dart';
import 'platform.dart';
import 'theme.dart';
import 'toast.dart';
import 'widgets.dart';

/// Tool error panel (ES-03): x glyph, title, at most six lines of output with a
/// "Show all" row, then Retry (only when the call can be re-run) and Copy error.
/// Neutral throughout: no red, no amber.
class ToolErrorPanel extends StatelessWidget {
  const ToolErrorPanel(
      {super.key, required this.title, required this.output, this.onRetry});
  final String title;
  final String output;
  final VoidCallback? onRetry;

  static const maxLines = 6;

  @override
  Widget build(BuildContext context) {
    final text = output.trimRight();
    final lines = text.split('\n');
    final more = lines.length > maxLines;
    final shown = more ? lines.take(maxLines).join('\n') : text;
    final mono = TextStyle(
        fontFamily: 'monospace',
        fontSize: 11.5,
        height: 16 / 11.5,
        fontWeight: FontWeight.w400,
        color: AppColors.fg2);
    if (!kMobile) {
      return Container(
        key: const ValueKey('tool-error-panel'),
        margin: EdgeInsets.symmetric(vertical: S.s4),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                AppIcon('x', size: 13, color: AppColors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5,
                          weight: FontWeight.w500, color: AppColors.fg1)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                key: const ValueKey('tool-error-output'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: SelectableText(shown, style: mono),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                if (more)
                  AskButton('Show all',
                      variant: AskButtonVariant.ghost,
                      onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: AppColors.surface1,
                            builder: (_) => SafeArea(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxHeight:
                                        MediaQuery.sizeOf(context).height * 0.6),
                                child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(16),
                                    child: SelectableText(text, style: mono)),
                              ),
                            ),
                          )),
                const Spacer(),
                AskButton('Copy error',
                    variant: AskButtonVariant.secondary,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) toast(context, 'Copied');
                    }),
                if (onRetry != null) ...[
                  const SizedBox(width: 6),
                  AskButton('Retry',
                      variant: AskButtonVariant.primary,
                      icon: 'refresh',
                      onTap: onRetry),
                ],
              ]),
            ),
          ],
        ),
      );
    }
    final copy = _PanelButton('Copy error', primary: false, onTap: () async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) toast(context, 'Copied');
    });
    final retry = onRetry == null
        ? null
        : _PanelButton('Retry', primary: true, icon: 'refresh', onTap: onRetry);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          key: const ValueKey('tool-error-panel'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(width: 2),
              ExcludeSemantics(
                  child: AppIcon('x', size: 16, color: AppColors.fg2)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15,
                        weight: FontWeight.w500, color: AppColors.fg1)),
              ),
            ]),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                key: const ValueKey('tool-error-output'),
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(shown, style: mono),
              ),
            ),
            if (more)
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: AppColors.surface1,
                    builder: (_) => SafeArea(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.6),
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Text(text, style: mono)),
                      ),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text('Show all',
                            style: sans(13,
                                weight: FontWeight.w500, color: AppColors.fg1)),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              // Large text stacks the pair, Retry on top.
              final stack = MediaQuery.textScalerOf(context).scale(14) > 20 ||
                  retry == null;
              if (retry == null) return copy;
              if (stack) {
                return Column(
                    children: [retry, const SizedBox(height: 8), copy]);
              }
              return Row(children: [
                Expanded(child: retry),
                const SizedBox(width: 8),
                Expanded(child: copy),
              ]);
            }),
          ]),
        ));
  }
}

/// 48 high, radius 10 button used by the limit card and the error panel.
class _PanelButton extends StatelessWidget {
  const _PanelButton(this.label,
      {required this.primary, this.icon, required this.onTap});
  final String label;
  final bool primary;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? AppColors.bg : AppColors.fg1;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: primary ? AppColors.fg1 : AppColors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: primary
              ? BorderSide.none
              : BorderSide(color: AppColors.line, width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: 48, minWidth: double.infinity),
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  AppIcon(icon!, size: 14, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: sans(14, weight: FontWeight.w500, color: fg)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Public wrapper so the limit card shares the exact button.
class PanelButton extends StatelessWidget {
  const PanelButton(this.label,
      {super.key, required this.primary, required this.onTap});
  final String label;
  final bool primary;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) =>
      _PanelButton(label, primary: primary, onTap: onTap);
}
