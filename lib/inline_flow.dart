import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat/ask_kit.dart';
import 'mobile_kit/controls.dart' show MkPill, MkPillTone;
import 'platform.dart';
import 'settings_form.dart';
import 'theme.dart';
import 'widgets.dart';

/// Desktop Settings flows expand in the card instead of opening a popover.
/// A danger strip that replaces a row: title, consequence, Cancel / confirm.
/// Reverts by itself after [revertAfter] so a stray click never leaves it armed.
class InlineConfirmStrip extends StatefulWidget {
  const InlineConfirmStrip({
    super.key,
    required this.title,
    required this.body,
    required this.onCancel,
    required this.onConfirm,
    this.confirmLabel = 'Remove',
    this.revertAfter = const Duration(seconds: 6),
    this.busy = false,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final Duration revertAfter;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool busy;

  @override
  State<InlineConfirmStrip> createState() => _InlineConfirmStripState();
}

class _InlineConfirmStripState extends State<InlineConfirmStrip> {
  Timer? _timer;
  final FocusNode _focus = FocusNode(debugLabel: 'inline-confirm');

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.revertAfter, () {
      if (mounted) widget.onCancel();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kMobile) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
        },
        child: Focus(
          focusNode: _focus,
          child: Container(
            height: 30,
            color: AppColors.surface1,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: widget.title,
                        style: sans(12, height: 17 / 12, color: AppColors.fg1)),
                    if (widget.body.trim().isNotEmpty)
                      TextSpan(
                          text: '  ${widget.body}',
                          style:
                              sans(12, height: 17 / 12, color: AppColors.fg3)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              AskButton(widget.confirmLabel,
                  variant: AskButtonVariant.secondary,
                  busy: widget.busy,
                  onTap: widget.busy ? null : widget.onConfirm),
              const SizedBox(width: 8),
              AskButton('Cancel',
                  variant: AskButtonVariant.ghost,
                  onTap: widget.busy ? null : widget.onCancel),
            ]),
          ),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Focus(
        focusNode: _focus,
        // Phone: a kit confirm. 15 question, 13.5 consequence, two 40 pills.
        child: Container(
          color: AppColors.danger.withValues(alpha: 0.06),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: sans(15, weight: W.label, color: AppColors.fg1)),
              const SizedBox(height: 2),
              Text(widget.body,
                  style: sans(13.5, height: 18 / 13.5, color: AppColors.fg3)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: MkPill('Cancel',
                      expand: true,
                      onTap: widget.busy ? null : widget.onCancel),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MkPill(widget.confirmLabel,
                      expand: true,
                      tone: MkPillTone.primary,
                      onTap: widget.busy ? null : widget.onConfirm),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of in-place actions shown under a tapped row; Esc collapses it.
class InlineActionsStrip extends StatelessWidget {
  const InlineActionsStrip(
      {super.key, required this.actions, required this.onClose});
  final List<Widget> actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onClose,
        },
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                Grouped.padX, 4, Grouped.padX, Grouped.padY + 3),
            child: Row(children: [
              for (final a in actions) ...[a, const SizedBox(width: 8)],
              const Spacer(),
              Btn('Close',
                  small: true, variant: BtnVariant.ghost, onTap: onClose),
            ]),
          ),
        ),
      );
}

/// Two or more choices in one 24pt track; the thumb marks the current one.
class InlineSegmented<T> extends StatelessWidget {
  const InlineSegmented(
      {super.key,
      required this.value,
      required this.options,
      required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        // Grows with large text instead of clipping the labels.
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: IntrinsicHeight(
            child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          for (final (v, label) in options)
            Material(
              color: v == value ? AppColors.surface3 : Colors.transparent,
              borderRadius: BorderRadius.circular(R.sm - 1),
              child: InkWell(
                borderRadius: BorderRadius.circular(R.sm - 1),
                onTap: v == value ? null : () => onChanged(v),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Center(
                    child: Text(label,
                        style: sans(12,
                            weight: v == value ? W.label : W.body,
                            color: v == value ? AppColors.fg1 : AppColors.fg3)),
                  ),
                ),
              ),
            ),
        ])),
      );
}
