import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'platform.dart';
import 'glass.dart';
import 'morph_sheet.dart' show showSpringSheet, SheetSize;
import 'app_dialog.dart';
import 'app_popover.dart';
import 'theme.dart';
import 'widgets.dart';

class AppField extends StatefulWidget {
  final String? label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final bool mono;
  final bool obscure;
  final String? icon;
  final Widget? rightSlot;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final bool autofocus;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  const AppField({
    super.key,
    this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.mono = false,
    this.obscure = false,
    this.icon,
    this.rightSlot,
    this.minLines = 1,
    this.maxLines = 1,
    this.enabled = true,
    this.autofocus = false,
    this.keyboardType,
    this.onSubmitted,
  });
  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
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
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: kMobile
                ? sans(12, color: AppColors.fg4)
                : sans(12, weight: W.label, color: AppColors.fg2),
          ),
          SizedBox(height: kMobile ? 6 : 7),
        ],
        AnimatedContainer(
          duration: Motion.quick,
          padding: EdgeInsets.symmetric(
            horizontal: kMobile ? S.of(14) : S.of(11),
          ),
          constraints: BoxConstraints(minHeight: kMobile ? 48 : 34),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(kMobile ? 16 : R.md),
            border: Border.all(
              color: _focus.hasFocus
                  ? AppColors.accentLine
                  : (kMobile
                      ? AppColors.fg1.withValues(alpha: 0.08)
                      : AppColors.lineStrong),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                AppIcon(widget.icon!, size: 16, color: AppColors.fg3),
                SizedBox(width: S.s8),
              ],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  obscureText: widget.obscure,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  autofocus: widget.autofocus,
                  keyboardType: widget.keyboardType,
                  onSubmitted: widget.onSubmitted,
                  cursorColor: AppColors.accent,
                  style: kMobile
                      ? sans(15, color: AppColors.fg1)
                      : widget.mono
                          ? mono(13, color: AppColors.fg1)
                          : sans(13, color: AppColors.fg1),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: kMobile ? S.s8 : S.s8,
                    ),
                    border: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: kMobile
                        ? sans(15, color: AppColors.fg4)
                        : widget.mono
                            ? mono(13, color: AppColors.fg4)
                            : sans(13, color: AppColors.fg4),
                  ),
                ),
              ),
              if (widget.rightSlot != null) widget.rightSlot!,
            ],
          ),
        ),
        if (widget.helper != null) ...[
          SizedBox(height: S.of(7)),
          Text(
            widget.helper!,
            style: kMobile
                ? sans(12, height: 17 / 12, color: AppColors.fg4)
                : sans(11, height: 1.4, color: AppColors.fg3),
          ),
        ],
      ],
    );
  }
}

/// Cancel and confirm, laid out for the platform: right-aligned and compact on
/// desktop, two full-width buttons within thumb reach on phones.
class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.danger = false,
  });

  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final variant = danger ? BtnVariant.danger : BtnVariant.primary;
    if (kMobile) {
      return Row(
        children: [
          Expanded(
            child: Btn(
              'Cancel',
              full: true,
              variant: BtnVariant.secondary,
              onTap: onCancel,
            ),
          ),
          SizedBox(width: S.s8),
          Expanded(
            child: Btn(
              confirmLabel,
              full: true,
              variant: variant,
              onTap: onConfirm,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Spacer(),
        Btn('Cancel', variant: BtnVariant.ghost, small: true, onTap: onCancel),
        SizedBox(width: S.s8),
        Btn(confirmLabel, variant: variant, small: true, onTap: onConfirm),
      ],
    );
  }
}

/// Ask before doing something; true when confirmed. A dialog on desktop, a
/// bottom sheet on phones.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Delete',
  bool danger = true,
  String? typedName,
}) async {
  if (kMobile) {
    return showConfirmDialog(
      context,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      typedName: typedName,
    );
  }
  Widget content(BuildContext ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.zero,
            child: Text(body, style: TS.ui()),
          ),
          SizedBox(height: kMobile ? S.s20 : 18),
          _DialogActions(
            confirmLabel: confirmLabel,
            danger: danger,
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
          ),
        ],
      );
  final bool? result;
  if (kMobile) {
    result = await showAppSheet<bool>(
      context,
      title: title,
      child: Builder(builder: content),
    );
  } else {
    result = await showPointPopover<bool>(
      context,
      point: lastPointerDown,
      width: 320,
      maxHeight: 220,
      child: Padding(
        padding: EdgeInsets.all(S.s12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: sans(13, weight: FontWeight.w500, color: AppColors.fg1),
            ),
            SizedBox(height: S.s4),
            Builder(builder: content),
          ],
        ),
      ),
    );
  }
  return result == true;
}

/// A single-field text prompt (rename, etc.): a dialog on desktop, a bottom
/// sheet on phones. Returns the trimmed text on save, or null if cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String saveLabel = 'Save',
  int minLines = 1,
  int maxLines = 1,
  bool anchored = false,
  Offset? point,
}) {
  final at = point ?? (anchored ? null : lastPointerDown);
  if (!kMobile) {
    return _showInlinePrompt(
      context,
      title: title,
      initial: initial,
      hint: hint,
      point: at,
      saveLabel: saveLabel,
      minLines: minLines,
      maxLines: maxLines,
    );
  }
  return showPromptDialog(
    context,
    title: title,
    initial: initial,
    hint: hint,
    verb: saveLabel,
    minLines: minLines,
    maxLines: maxLines,
  );
}

Offset? _rawPointerDown;
bool _tracking = false;

// The control (or row) a menu opened from. A confirmation or prompt that a
// menu item leads to anchors here rather than at the item the pointer hit,
// which sits in a menu that has already closed.
Rect? _trigger;
Offset? _triggerPoint;
int _menusOpen = 0;
DateTime _triggerClosedAt = DateTime.fromMillisecondsSinceEpoch(0);

bool get _triggerFresh =>
    _trigger != null &&
    (_menusOpen > 0 ||
        DateTime.now().difference(_triggerClosedAt) <
            const Duration(milliseconds: 1500));

/// Where a popover that follows a click should open: the control a menu was
/// opened from while that menu is open or has just closed, else the pointer.
Offset? get lastPointerDown => _triggerFresh ? _triggerPoint : _rawPointerDown;

/// Wraps a menu so popovers opened from its items anchor to [rect].
Future<T> trackMenuTrigger<T>(Rect rect, Future<T> Function() open) {
  _trigger = rect;
  _triggerPoint = rect.center;
  _menusOpen++;
  return open().whenComplete(() {
    _menusOpen--;
    _triggerClosedAt = DateTime.now();
  });
}

void trackPointer() {
  if (_tracking) return;
  _tracking = true;
  GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
    if (e is! PointerDownEvent) return;
    _rawPointerDown = e.position;
    if (_menusOpen == 0) _trigger = null;
  });
}

/// Phone popovers sit on a frosted blackout of the whole screen; desktop
/// ones stay anchored over an untouched window.
Widget popoverBackdrop(Animation<double> animation, Widget child) {
  if (!kMobile) return child;
  return Stack(
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, __) {
              final t = animation.value;
              final scrim = ColoredBox(
                color: AppColors.glassScrim.withValues(
                  alpha: AppColors.glassScrim.a * t,
                ),
              );
              return scrim; // spec G: no backdrop blur
            },
          ),
        ),
      ),
      child,
    ],
  );
}

Future<T?> showPointPopover<T>(
  BuildContext context, {
  required Offset? point,
  required double width,
  required double maxHeight,
  required Widget child,
}) {
  final overlay = Overlay.of(context, rootOverlay: true)
      .context
      .findRenderObject() as RenderBox?;
  final box = context.findRenderObject() as RenderBox?;
  if (overlay == null) return Future.value();
  final screen = overlay.size;
  final rect = point != null && point == _triggerPoint && _triggerFresh
      ? _trigger
      : null;
  var at = rect != null
      ? Offset(rect.left + 24, rect.bottom - 4)
      : point != null
          ? overlay.globalToLocal(point)
          : box != null && box.attached
              ? box.localToGlobal(Offset(0, box.size.height + 6),
                  ancestor: overlay)
              : screen.center(Offset.zero);
  final w = width.clamp(200.0, screen.width - 16);
  final left = (at.dx - w / 2 + (point != null ? w / 2 - 24 : 0)).clamp(
    8.0,
    screen.width - w - 8,
  );
  final below = (screen.height - at.dy - 18).clamp(0.0, screen.height);
  final above = (at.dy - 18).clamp(0.0, screen.height);
  final placeAbove = below < maxHeight && above > below;
  // Hang off the control's edge, on whichever side has room.
  if (rect != null && placeAbove) at = Offset(at.dx, rect.top + 4);
  final availH = (placeAbove ? above : below).clamp(80.0, maxHeight);
  final top = placeAbove
      ? null
      : (at.dy + 10).clamp(
          8.0,
          (screen.height - availH - 8).clamp(8.0, screen.height),
        );
  final bottom = placeAbove
      ? (screen.height - at.dy + 10).clamp(
          8.0,
          (screen.height - availH - 8).clamp(8.0, screen.height),
        )
      : null;
  final origin = Alignment(
    (((at.dx - left) / w) * 2 - 1).clamp(-1.0, 1.0),
    placeAbove ? 1 : -1,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.fast,
    pageBuilder: (ctx, _, __) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: w,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availH),
            child: AppPopoverSurface(padding: EdgeInsets.zero, child: child),
          ),
        ),
      ],
    ),
    transitionBuilder: (_, animation, __, child) {
      final curve = CurvedAnimation(parent: animation, curve: Motion.enter);
      return popoverBackdrop(
        curve,
        FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween(begin: 0.97, end: 1.0).animate(curve),
            alignment: origin,
            child: child,
          ),
        ),
      );
    },
  );
}

Future<String?> _showInlinePrompt(
  BuildContext context, {
  required String title,
  required String initial,
  String? hint,
  Offset? point,
  String saveLabel = 'Save',
  int minLines = 1,
  int maxLines = 1,
}) {
  return showPointPopover<String>(
    context,
    point: point,
    width: maxLines > 1 ? 340 : 300,
    maxHeight: maxLines > 1 ? 260 : 120,
    child: Padding(
      padding: EdgeInsets.all(S.s12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(13, color: AppColors.fg3),
          ),
          SizedBox(height: S.s8),
          _InlinePromptField(
            initial: initial,
            hint: hint,
            saveLabel: saveLabel,
            minLines: minLines,
            maxLines: maxLines,
          ),
        ],
      ),
    ),
  );
}

class _InlinePromptField extends StatefulWidget {
  final String initial;
  final String? hint;
  final String saveLabel;
  final int minLines;
  final int maxLines;
  const _InlinePromptField({
    required this.initial,
    this.hint,
    this.saveLabel = 'Save',
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  State<_InlinePromptField> createState() => _InlinePromptFieldState();
}

class _InlinePromptFieldState extends State<_InlinePromptField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, _c.text.trim());

  @override
  Widget build(BuildContext context) {
    final multi = widget.maxLines > 1;
    final field = AppField(
      controller: _c,
      hint: widget.hint,
      autofocus: true,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      onSubmitted: multi ? null : (_) => _done(),
    );
    final save = Btn(widget.saveLabel, small: true, onTap: _done);
    if (multi) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          SizedBox(height: S.of(10)),
          Align(alignment: Alignment.centerRight, child: save),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: field),
        SizedBox(width: S.s8),
        save,
      ],
    );
  }
}

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget child,
  List<Widget> headerActions = const [],
  // Desktop dialogs default to a comfortable 460px column rather than phone width.
  double maxWidth = 460,
  double maxHeight = 600,
  SheetSize size = SheetSize.auto,

  /// Medium and large sheets: a primary action pinned above the safe area.
  Widget? pinned,
}) {
  if (!kMobile) {
    return showPointPopover<T>(
      context,
      point: lastPointerDown,
      width: maxWidth.clamp(320, 420).toDouble(),
      maxHeight: maxHeight,
      child: Builder(
        builder: (ctx) => SingleChildScrollView(
          padding: EdgeInsets.all(S.s12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(
                        13,
                        weight: FontWeight.w500,
                        color: AppColors.fg1,
                      ),
                    ),
                  ),
                  ...headerActions,
                ],
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: S.s2),
                  child: Text(
                    subtitle,
                    style: sans(
                      12,
                      weight: FontWeight.w400,
                      color: AppColors.fg3,
                    ),
                  ),
                ),
              SizedBox(height: S.s12),
              child,
            ],
          ),
        ),
      ),
    );
  }
  if (size == SheetSize.medium || size == SheetSize.large) {
    return showSpringSheet<T>(
      context,
      size: size,
      builder: (sheetContext, scroll) => Material(
        type: MaterialType.transparency,
        child: AppSheetSurface(
          expand: true,
          child: _SizedSheetBody(
              title: title, scroll: scroll, pinned: pinned, child: child),
        ),
      ),
    );
  }
  return showSpringSheet<T>(
    context,
    size: size,
    builder: (sheetContext, scroll) {
      final media = MediaQuery.of(sheetContext);
      // The route lifts the sheet above the keyboard itself.
      final available = (media.size.height - media.viewInsets.bottom) * 0.92;
      final limit = available < maxHeight ? available : maxHeight;
      return Material(
        type: MaterialType.transparency,
        child: AppSheetSurface(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: limit),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitle != null &&
                    title.isNotEmpty &&
                    !ShellPanelRoot.inPanel(sheetContext))
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      M.gutter,
                      S.s4,
                      M.gutter,
                      S.s4,
                    ),
                    child: Column(
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TS.rowTitle(),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TS.meta(),
                          ),
                      ],
                    ),
                  )
                else if (title.isNotEmpty &&
                    !ShellPanelRoot.inPanel(sheetContext))
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      M.gutter,
                      S.s4,
                      M.gutter,
                      S.s8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.sectionTitle(),
                      ),
                    ),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: EdgeInsets.fromLTRB(
                      M.gutter,
                      S.s4,
                      M.gutter,
                      S.s12 + media.padding.bottom,
                    ),
                    child: SurfaceScope(
                      group: kMobile ? Colors.transparent : AppColors.overlay,
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A theme-styled switch track + thumb.
///
/// Extracted so a settings row can use the switch WITHOUT the card chrome that
/// [AppToggle] wraps around it. Call sites previously reached for
/// `Transform.scale(child: Switch(...))` to size a Material switch down, which
/// scales the whole widget including its touch target and distorts Material's
/// fixed internal proportions — that is why the result looked wrong.

/// A panel that drops down under [anchor] (desktop pickers): no dimmed
/// backdrop, closes on an outside click or Escape.
Future<T?> showAnchoredPanel<T>(
  BuildContext anchor, {
  required Widget child,
  double width = 360,
  double maxHeight = 460,
  bool above = false,
  bool alignRight = false,
  Color? borderColor,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor, rootOverlay: true)
      .context
      .findRenderObject() as RenderBox?;
  if (box == null || overlay == null) {
    return showAppSheet<T>(anchor, title: '', child: child);
  }
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final screen = overlay.size;
  final w = width.clamp(200.0, screen.width - 16);
  final left = (alignRight ? origin.dx + box.size.width - w : origin.dx).clamp(
    8.0,
    screen.width - w - 8,
  );
  final top = origin.dy + box.size.height + 6;
  final bottom = screen.height - origin.dy + 6;
  final room = (above ? origin.dy - 18 : screen.height - top - 12).clamp(
    160.0,
    maxHeight,
  );
  final grow = Alignment(
    ((origin.dx + box.size.width / 2 - left) / w * 2 - 1).clamp(-1.0, 1.0),
    above ? 1 : -1,
  );
  return trackMenuTrigger<T?>(
    origin & box.size,
    () => showGeneralDialog<T>(
      context: anchor,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: Motion.fast,
      pageBuilder: (ctx, _, __) => Stack(
        children: [
          Positioned(
            left: left,
            top: above ? null : top,
            bottom: above ? bottom : null,
            width: w,
            child: kMobile
                ? Glass(
                    radius: BorderRadius.circular(R.of(16)),
                    tint: AppColors.surface2.withValues(alpha: 0.7),
                    blur: 28,
                    child: Material(
                      type: MaterialType.transparency,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: room),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(S.s6),
                          child: child,
                        ),
                      ),
                    ),
                  )
                : Material(
                    color: AppColors.surface2,
                    elevation: 10,
                    shadowColor: Colors.black.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.of(12)),
                      side: BorderSide(color: borderColor ?? AppColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: room),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(S.s8),
                        child: child,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      transitionBuilder: (_, animation, __, child) {
        final curve = CurvedAnimation(parent: animation, curve: Motion.enter);
        return popoverBackdrop(
          curve,
          FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(curve),
              alignment: grow,
              child: child,
            ),
          ),
        );
      },
    ),
  );
}

/// A form beside its trigger on desktop (no dialog), a sheet on phones.
Future<T?> showSidePopover<T>(
  BuildContext context, {
  BuildContext? anchorContext,
  required String title,
  required Widget child,
  Key? popoverKey,
  double width = 340,
}) async {
  if (kMobile) return showAppSheet<T>(context, title: title, child: child);
  final box = anchorContext?.findRenderObject() as RenderBox?;
  final anchor = box == null || !box.attached
      ? const Rect.fromLTWH(16, 96, 0, 0)
      : box.localToGlobal(Offset.zero) & box.size;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.transparent,
    transitionDuration: Motion.quick,
    pageBuilder: (ctx, _, __) => SafeArea(
      minimum: EdgeInsets.all(S.s12),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final origin =
                (context.findRenderObject() as RenderBox?)?.localToGlobal(
                      Offset.zero,
                    ) ??
                    Offset.zero;
            return CustomSingleChildLayout(
              delegate: _SidePopoverLayout(anchor.shift(-origin), width),
              child: KeyedSubtree(
                key: popoverKey,
                child: AppPopoverSurface(
                  padding: EdgeInsets.zero,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(S.s16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: sans(
                            13,
                            weight: FontWeight.w500,
                            color: AppColors.fg1,
                          ),
                        ),
                        SizedBox(height: S.s12),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Motion.enter),
      child: child,
    ),
  );
}

class _SidePopoverLayout extends SingleChildLayoutDelegate {
  const _SidePopoverLayout(this.anchor, this.width);

  final Rect anchor;
  final double width;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.maxWidth.clamp(0, width),
        maxWidth: constraints.maxWidth.clamp(0, width),
        maxHeight: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = anchor.right + 8;
    final left = right + childSize.width <= size.width
        ? right
        : anchor.right - childSize.width;
    return Offset(
      left.clamp(0, size.width - childSize.width),
      anchor.top.clamp(0, size.height - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_SidePopoverLayout old) =>
      anchor != old.anchor || width != old.width;
}

/// Input container: an inset well that reads against any popover, brighter
/// edge while a field inside has focus.
class FieldWell extends StatefulWidget {
  const FieldWell({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.minHeight = 0,
    this.alignment,
  });
  final Widget child;
  final EdgeInsets padding;
  final double minHeight;
  final AlignmentGeometry? alignment;

  @override
  State<FieldWell> createState() => _FieldWellState();
}

class _FieldWellState extends State<FieldWell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) => setState(() => _focused = f),
        child: AnimatedContainer(
          duration: Motion.quick,
          constraints: BoxConstraints(minHeight: widget.minHeight),
          alignment: widget.alignment,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.of(14)),
            border: Border.all(
              color: _focused ? AppColors.fg4 : AppColors.lineStrong,
            ),
          ),
          child: widget.child,
        ),
      );
}

/// Medium and large sheet content: 56 high header (title 16/500 at x20, 48
/// close), hairline once the body has scrolled, scrolling body, pinned action.
class _SizedSheetBody extends StatefulWidget {
  const _SizedSheetBody(
      {required this.title,
      required this.scroll,
      required this.child,
      this.pinned});
  final String title;
  final ScrollController scroll;
  final Widget child;
  final Widget? pinned;
  @override
  State<_SizedSheetBody> createState() => _SizedSheetBodyState();
}

class _SizedSheetBodyState extends State<_SizedSheetBody> {
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 56,
        padding: const EdgeInsets.only(left: 20, right: 8),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: _scrolled ? AppColors.line : Colors.transparent))),
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(16, weight: FontWeight.w500, color: AppColors.fg1)),
            ),
          ),
          Semantics(
            button: true,
            label: 'Close',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              splashFactory: NoSplash.splashFactory,
              child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                      child: AppIcon('x', size: 20, color: AppColors.fg2))),
            ),
          ),
        ]),
      ),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
              final v = n.metrics.pixels > 1;
              if (v != _scrolled) setState(() => _scrolled = v);
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: widget.scroll,
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, widget.pinned == null ? 12 + bottom : 12),
            child: SurfaceScope(group: Colors.transparent, child: widget.child),
          ),
        ),
      ),
      if (widget.pinned != null)
        Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: -12,
            height: 12,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                      AppColors.surface1.withValues(alpha: 0),
                      AppColors.surface1
                    ])),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
            child: SizedBox(width: double.infinity, child: widget.pinned),
          ),
        ]),
    ]);
  }
}
