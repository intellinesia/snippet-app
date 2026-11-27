import 'dart:async';

import 'package:flutter/material.dart';
import 'platform.dart';
import 'package:flutter/semantics.dart';

import 'theme.dart';

// Phone dialog kit (spec W2-2, DL-01): one centred, opaque card for confirms
// and prompts. No backdrop blur, 200 ms ease-out, buttons 48 high.

const Duration kDialogMotion = Duration(milliseconds: 200);

/// Open [builder] as a centred card dialog. The card moves up with the
/// keyboard and never exceeds 85 percent of the screen.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String label,
  required WidgetBuilder builder,
}) {
  final instant = reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: AppColors.scrim,
    transitionDuration:
        instant ? const Duration(milliseconds: 1) : kDialogMotion,
    pageBuilder: (ctx, _, __) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(ctx).height -
                      MediaQuery.viewInsetsOf(ctx).bottom) *
                  0.85,
            ),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: label,
              explicitChildNodes: true,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

/// A 48 high dialog button: primary (fg1 fill) or secondary (surface2 with a
/// hairline). Disabled primary is surface3 with fg3 text.
class AppDialogButton extends StatelessWidget {
  const AppDialogButton(
    this.label, {
    super.key,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
    this.hint,
    this.autofocus = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool enabled;
  final String? hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final bg = !enabled
        ? AppColors.surface3
        : primary
            ? AppColors.fg1
            : AppColors.surface2;
    final fg = !enabled
        ? AppColors.fg3
        : primary
            ? AppColors.base
            : AppColors.fg1;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: enabled ? null : hint,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: primary || !enabled
              ? BorderSide.none
              : BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          autofocus: autofocus,
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: primary || !enabled
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.line),
                  ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: sans(14, weight: FontWeight.w500, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cancel then confirm, side by side; stacked (confirm on top) when either
/// label would wrap at the current text scale.
class AppDialogButtons extends StatelessWidget {
  const AppDialogButtons({
    super.key,
    required this.cancel,
    required this.confirm,
  });
  final AppDialogButton cancel;
  final AppDialogButton confirm;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          final each = (c.maxWidth - 8) / 2 - 24;
          final scaler = MediaQuery.textScalerOf(ctx);
          bool wraps(String s) {
            final p = TextPainter(
              text: TextSpan(
                text: s,
                style: sans(14, weight: FontWeight.w500),
              ),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            return p.width > each;
          }

          if (wraps(cancel.label) || wraps(confirm.label)) {
            // Reading order stays Cancel first; the confirm sits on top visually.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(sortKey: const OrdinalSortKey(1), child: confirm),
                const SizedBox(height: 8),
                Semantics(sortKey: const OrdinalSortKey(0), child: cancel),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: cancel),
              const SizedBox(width: 8),
              Expanded(child: confirm),
            ],
          );
        },
      );
}

/// The dialog card: title, optional body, optional middle, then [buttons].
class AppDialogCard extends StatelessWidget {
  const AppDialogCard({
    super.key,
    required this.title,
    this.body,
    this.middle,
    required this.buttons,
  });
  final String title;
  final String? body;
  final Widget? middle;
  final Widget buttons;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Material(
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kMobile ? 16 : R.lg)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(
                  17,
                  weight: FontWeight.w500,
                  color: AppColors.fg1,
                ).copyWith(height: 23 / 17),
              ),
            ),
            if (body != null && body!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    body!,
                    style: sans(
                      14,
                      color: AppColors.fg2,
                    ).copyWith(height: 20 / 14),
                  ),
                ),
              ),
            ],
            if (middle != null) ...[const SizedBox(height: 12), middle!],
            const SizedBox(height: 20),
            buttons,
          ],
        ),
      ),
    );
  }
}

/// The dialog text field: 48 high, radius 8, surface3 fill, hairline border,
/// 1.5 fg2 ring on focus, no autocorrect or suggestions.
class AppDialogField extends StatefulWidget {
  const AppDialogField({
    super.key,
    required this.controller,
    this.hint,
    this.autofocus = true,
    this.onSubmitted,
    this.minLines = 1,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final int minLines;
  final int maxLines;
  @override
  State<AppDialogField> createState() => _AppDialogFieldState();
}

class _AppDialogFieldState extends State<AppDialogField> {
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focus.hasFocus ? AppColors.fg2 : AppColors.line,
            width: _focus.hasFocus ? 1.5 : 1,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          autofocus: widget.autofocus,
          autocorrect: false,
          enableSuggestions: false,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          onSubmitted: widget.onSubmitted,
          cursorColor: AppColors.fg1,
          style: sans(15, color: AppColors.fg1),
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: InputBorder.none,
            hintText: widget.hint,
            hintStyle: sans(15, color: AppColors.fg3),
          ),
        ),
      );
}

/// Confirm dialog. With [typedName] the confirm stays disabled until the
/// field equals the name (trimmed, case sensitive). [action] runs on confirm;
/// returning an error string keeps the dialog open and shows it under the field.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String? typedName,
  Future<String?> Function()? action,
}) async {
  final r = await showAppDialog<bool>(
    context,
    label: title,
    builder: (_) => _ConfirmCard(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      typedName: typedName,
      action: action,
    ),
  );
  return r == true;
}

class _ConfirmCard extends StatefulWidget {
  const _ConfirmCard({
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.typedName,
    this.action,
  });
  final String title;
  final String body;
  final String confirmLabel;
  final String? typedName;
  final Future<String?> Function()? action;
  @override
  State<_ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends State<_ConfirmCard> {
  final _c = TextEditingController();
  String? _error;
  bool _busy = false;

  bool get _ok =>
      widget.typedName == null || _c.text.trim() == widget.typedName!.trim();

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_ok || _busy) return;
    final a = widget.action;
    if (a == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _busy = true);
    final err = await a();
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final typed = widget.typedName != null;
    return AppDialogCard(
      title: widget.title,
      body: widget.body,
      middle: typed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Type ${widget.typedName} to confirm',
                  style: sans(
                    12.5,
                    weight: FontWeight.w500,
                    color: AppColors.fg1,
                  ),
                ),
                const SizedBox(height: 8),
                AppDialogField(controller: _c, onSubmitted: (_) => _confirm()),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: sans(12, color: AppColors.fg2)),
                ],
              ],
            )
          : (_error != null
              ? Text(_error!, style: sans(12, color: AppColors.fg2))
              : null),
      buttons: AppDialogButtons(
        cancel: AppDialogButton(
          'Cancel',
          autofocus: !typed,
          onTap: () => Navigator.pop(context, false),
        ),
        confirm: AppDialogButton(
          widget.confirmLabel,
          primary: true,
          enabled: _ok && !_busy,
          hint: 'Type the name to enable',
          onTap: _confirm,
        ),
      ),
    );
  }
}

/// Text prompt: field prefilled and fully selected; the verb is disabled when
/// the text is empty or unchanged. Returns trimmed text or null.
Future<String?> showPromptDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  required String verb,
  int minLines = 1,
  int maxLines = 1,
}) {
  return showAppDialog<String>(
    context,
    label: title,
    builder: (_) => _PromptCard(
      title: title,
      initial: initial,
      hint: hint,
      verb: verb,
      minLines: minLines,
      maxLines: maxLines,
    ),
  );
}

class _PromptCard extends StatefulWidget {
  const _PromptCard({
    required this.title,
    required this.initial,
    this.hint,
    required this.verb,
    required this.minLines,
    required this.maxLines,
  });
  final String title;
  final String initial;
  final String? hint;
  final String verb;
  final int minLines;
  final int maxLines;
  @override
  State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  late final _c = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _ok {
    final t = _c.text.trim();
    return t.isNotEmpty &&
        (widget.initial.isEmpty || t != widget.initial.trim());
  }

  void _done() {
    if (_ok) Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) => AppDialogCard(
        title: widget.title,
        middle: AppDialogField(
          controller: _c,
          hint: widget.hint,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          onSubmitted: widget.maxLines > 1 ? null : (_) => _done(),
        ),
        buttons: AppDialogButtons(
          cancel:
              AppDialogButton('Cancel', onTap: () => Navigator.pop(context)),
          confirm: AppDialogButton(
            widget.verb,
            primary: true,
            enabled: _ok,
            hint: 'Enter a new value to enable',
            onTap: _done,
          ),
        ),
      );
}
