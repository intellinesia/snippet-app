import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'canvas_models.dart';

/// Draft anchor created when the user places a new pin via long-press or Pin tool.
class PendingPinAnchor {
  const PendingPinAnchor({
    required this.frame,
    this.element,
    required this.dx,
    required this.dy,
  });

  final CanvasFrame frame;
  final CanvasElementRect? element;
  final double dx;
  final double dy;
}

/// Desktop docked side panel (width >= 900) wrapping Pins or Steps content.
class CanvasSidePanel extends StatelessWidget {
  const CanvasSidePanel({
    super.key,
    required this.title,
    this.subtitle,
    required this.onClose,
    required this.child,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(S.s16, S.s12, S.s8, S.s12),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    onPressed: onBack,
                    tooltip: 'Back to pins',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 44, height: 44),
                    icon: AppIcon('arrow-left', size: 16, color: AppColors.fg2),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: sans(14,
                              weight: W.label, color: AppColors.fg1)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(11, color: AppColors.fg3)),
                    ],
                  ),
                ),
                CanvasCloseButton(onPressed: onClose),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Composer body for typing a comment on a newly placed pin.
class PinComposerView extends StatefulWidget {
  const PinComposerView({
    super.key,
    required this.anchor,
    required this.onCancel,
    required this.onSubmit,
  });

  final PendingPinAnchor anchor;
  final VoidCallback onCancel;
  final Future<void> Function(String text) onSubmit;

  @override
  State<PinComposerView> createState() => _PinComposerViewState();
}

class _PinComposerViewState extends State<PinComposerView> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final el = widget.anchor.element;
    return Padding(
      padding: EdgeInsets.all(S.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.anchor.frame.title.isNotEmpty
                      ? widget.anchor.frame.title
                      : widget.anchor.frame.id,
                  style: sans(12, weight: W.label, color: AppColors.fg1),
                ),
                SizedBox(height: S.s2),
                Text(
                  el != null
                      ? '${el.id}  (${(widget.anchor.dx * 100).round()}%, ${(widget.anchor.dy * 100).round()}%)'
                      : 'Frame anchor (${(widget.anchor.dx * 100).round()}%, ${(widget.anchor.dy * 100).round()}%)',
                  style: mono(11, color: AppColors.fg3),
                ),
              ],
            ),
          ),
          SizedBox(height: S.s12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            style: sans(13, color: AppColors.fg1),
            decoration: InputDecoration(
              hintText: 'Leave a note for this element...',
              hintStyle: sans(13, color: AppColors.fg3),
              filled: true,
              fillColor: AppColors.surface2,
              contentPadding: EdgeInsets.all(S.s12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: S.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: _saving ? null : widget.onCancel,
                  child: Text('Cancel',
                      style: sans(13, color: AppColors.fg2)),
                ),
              ),
              SizedBox(width: S.s8),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentFg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                  ),
                  child: Text(_saving ? 'Saving...' : 'Place pin',
                      style: sans(13,
                          weight: W.label, color: AppColors.accentFg)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lists all pins with status, agent reply text, and resolve toggle.
class PinsListView extends StatelessWidget {
  const PinsListView({
    super.key,
    required this.pins,
    required this.frameTitles,
    required this.selectedPinId,
    required this.onSelectPin,
    required this.onToggleResolve,
  });

  final List<CanvasPin> pins;
  final Map<String, String> frameTitles;
  final String? selectedPinId;
  final ValueChanged<CanvasPin> onSelectPin;
  final Future<void> Function(CanvasPin pin) onToggleResolve;

  @override
  Widget build(BuildContext context) {
    if (pins.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(S.s24),
          child: Text(
            'No pins yet. Long-press a frame or pick Pin to leave a note.',
            textAlign: TextAlign.center,
            style: sans(13, color: AppColors.fg3),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(S.s12),
      itemCount: pins.length,
      separatorBuilder: (_, __) => SizedBox(height: S.s8),
      itemBuilder: (context, index) {
        final pin = pins[index];
        final isSelected = pin.id == selectedPinId;
        final frameLabel = frameTitles[pin.frameId] ?? pin.frameId;
        final target = (pin.elId != null && pin.elId!.isNotEmpty)
            ? '$frameLabel / ${pin.elId}'
            : frameLabel;
        final statusLabel = pin.isResolved ? 'resolved' : 'open';

        return Semantics(
          button: true,
          selected: isSelected,
          label: 'Pin ${index + 1}, $statusLabel, $target: ${pin.text}',
          child: Material(
          color: isSelected ? AppColors.surface3 : AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            onTap: () => onSelectPin(pin),
            borderRadius: BorderRadius.circular(R.sm),
            child: Container(
              padding: EdgeInsets.all(S.s12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                  color: isSelected ? AppColors.accentLine : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: pin.isResolved ? AppColors.fg3 : AppColors.fg1,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: mono(11, weight: W.strong, color: AppColors.bg),
                        ),
                      ),
                      SizedBox(width: S.s8),
                      Expanded(
                        child: Text(
                          target,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(11,
                              color: isSelected ? AppColors.fg2 : AppColors.fg3),
                        ),
                      ),
                      if (pin.isResolved)
                        Text('Resolved',
                            style: sans(12,
                                color: isSelected
                                    ? AppColors.fg2
                                    : AppColors.fg3)),
                    ],
                  ),
                  SizedBox(height: S.s8),
                  Text(
                    pin.text,
                    style: sans(
                      13,
                      color: pin.isResolved
                          ? (isSelected ? AppColors.fg2 : AppColors.fg3)
                          : AppColors.fg1,
                    ),
                  ),
                  if (pin.reply != null && pin.reply!.trim().isNotEmpty) ...[
                    SizedBox(height: S.s8),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(S.s8),
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(R.xs),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Agent reply',
                              style: sans(11,
                                  weight: W.label, color: AppColors.fg3)),
                          SizedBox(height: S.s2),
                          Text(pin.reply!,
                              style: sans(12, color: AppColors.fg2)),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: S.s8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Semantics(
                      button: true,
                      label:
                          '${pin.isResolved ? 'Reopen' : 'Resolve'} pin ${index + 1}',
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: () => onToggleResolve(pin),
                        borderRadius: BorderRadius.circular(R.xs),
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: 44,
                            minWidth: 44,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: S.s8,
                            vertical: S.s4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(
                                pin.isResolved ? 'undo' : 'check',
                                size: 14,
                                color: AppColors.fg2,
                              ),
                              SizedBox(width: S.s6),
                              Text(
                                pin.isResolved ? 'Reopen' : 'Resolve',
                                style: sans(12,
                                    weight: W.label, color: AppColors.fg2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }
}

/// Versions list: every edit is a named step. Tap a step to preview that
/// version on the canvas; Revert undoes that single step.
class StepsHistoryView extends StatelessWidget {
  const StepsHistoryView({
    super.key,
    required this.ops,
    required this.currentRev,
    required this.revertingBatchId,
    required this.onRevert,
    this.frameTitles = const <String, String>{},
    this.previewRev,
    this.onPreview,
  });

  final List<CanvasOpBatch> ops;
  final int currentRev;
  final String? revertingBatchId;
  final Future<void> Function(CanvasOpBatch batch) onRevert;
  final Map<String, String> frameTitles;
  final int? previewRev;

  /// Called with the tapped step, or null to leave the preview.
  final ValueChanged<CanvasOpBatch?>? onPreview;

  @override
  Widget build(BuildContext context) {
    if (ops.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(S.s24),
          child: Text('No recorded steps yet.',
              style: sans(13, color: AppColors.fg3)),
        ),
      );
    }

    final sorted = [...ops]..sort((a, b) => b.rev.compareTo(a.rev));
    final anyBusy = revertingBatchId != null;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(S.s8, S.s4, S.s8, S.s16),
      itemCount: sorted.length + 1,
      itemBuilder: (context, index) {
        if (index == sorted.length) {
          return Padding(
            padding: EdgeInsets.fromLTRB(S.s8, S.s12, S.s8, 0),
            child: Text('Reverting adds a step; nothing is lost.',
                style: sans(12, color: AppColors.fg3)),
          );
        }
        final batch = sorted[index];
        final isBusy = revertingBatchId == batch.batchId;
        final isCurrent = currentRev > 0 && batch.rev == currentRev;
        final isPreview = previewRev == batch.rev;
        final detail = describeCanvasBatch(batch, frameTitles);
        final title = batch.label.isNotEmpty ? batch.label : batch.batchId;
        return Semantics(
          button: true,
          selected: isPreview,
          label: 'Preview revision ${batch.rev}: $title',
          child: Material(
            color: isPreview ? AppColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(R.sm),
            child: InkWell(
              onTap: onPreview == null
                  ? null
                  : () => onPreview!(isCurrent && !isPreview ? null : batch),
              borderRadius: BorderRadius.circular(R.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(S.s8, S.s8, S.s4, S.s8),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface3,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          batch.author.isNotEmpty
                              ? batch.author[0].toUpperCase()
                              : '?',
                          style: sans(12,
                              weight: W.label, color: AppColors.fg1),
                        ),
                      ),
                      SizedBox(width: S.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13,
                                    weight: W.label, color: AppColors.fg1)),
                            if (detail.isNotEmpty)
                              Text(detail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(12, color: AppColors.fg2)),
                            Text(
                              '${batch.author} · ${formatCanvasRelativeTime(batch.ts)} · r${batch.rev}${isCurrent ? ' · current' : ''}',
                              style: sans(11,
                                  color:
                                      isPreview ? AppColors.fg2 : AppColors.fg3),
                            ),
                          ],
                        ),
                      ),
                      Semantics(
                        button: true,
                        enabled: !anyBusy,
                        label: 'Revert revision ${batch.rev}',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: anyBusy ? null : () => onRevert(batch),
                          borderRadius: BorderRadius.circular(R.xs),
                          child: Container(
                            constraints: const BoxConstraints(
                                minHeight: 44, minWidth: 44),
                            padding: EdgeInsets.symmetric(horizontal: S.s8),
                            alignment: Alignment.center,
                            child: Text(
                              isBusy ? 'Reverting...' : 'Revert',
                              style: sans(12,
                                  weight: W.label, color: AppColors.fg2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Close affordance: 48 on phone, 44 on desktop.
class CanvasCloseButton extends StatelessWidget {
  const CanvasCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final size = kMobile ? 48.0 : 44.0;
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Close',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      icon: AppIcon('x', size: 16, color: AppColors.fg2),
    );
  }
}
