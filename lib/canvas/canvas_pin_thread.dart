import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'canvas_client.dart';
import 'canvas_models.dart';

/// A pin's conversation: the note, the agent reply, what changed, and the
/// decision (Approve or Revert).
class PinThreadView extends StatelessWidget {
  const PinThreadView({
    super.key,
    required this.pin,
    required this.frameTitle,
    required this.client,
    required this.onApprove,
    this.beforeRev,
    this.afterRev,
    this.onRevert,
    this.revertBusy = false,
  });

  final CanvasPin pin;
  final String frameTitle;
  final CanvasClient? client;
  final Future<void> Function() onApprove;

  /// Frame revisions to compare; null hides the before and after row.
  final int? beforeRev;
  final int? afterRev;

  /// Reverts the latest step that changed this frame since the pin.
  final VoidCallback? onRevert;
  final bool revertBusy;

  @override
  Widget build(BuildContext context) {
    final reply = pin.reply?.trim() ?? '';
    final who = pin.author.isNotEmpty ? pin.author : 'You';
    final when = pin.createdAt != null
        ? ' · ${formatCanvasRelativeTime(pin.createdAt!)}'
        : '';
    return ListView(
      padding: EdgeInsets.all(S.s16),
      children: [
        Container(
          padding: EdgeInsets.all(S.s12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Text(pin.text, style: sans(13, color: AppColors.fg1)),
        ),
        Padding(
          padding: EdgeInsets.only(top: S.s4, bottom: S.s12),
          child: Text('$who$when', style: sans(11, color: AppColors.fg4)),
        ),
        if (reply.isNotEmpty) ...[
          Row(
            children: [
              Text('Agent',
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
              const Spacer(),
              AppIcon('check', size: 13, color: AppColors.fg3),
              SizedBox(width: S.s4),
              Text(pin.isResolved ? 'Approved' : 'Acknowledged',
                  style: sans(12, color: AppColors.fg3)),
            ],
          ),
          SizedBox(height: S.s4),
          Text(reply, style: sans(13, height: 1.4, color: AppColors.fg2)),
        ] else
          Text(
            pin.isResolved
                ? 'Resolved without an agent reply.'
                : 'Waiting for an agent to reply.',
            style: sans(12, color: AppColors.fg3),
          ),
        if (beforeRev != null && afterRev != null && client != null) ...[
          SizedBox(height: S.s16),
          Row(
            children: [
              Expanded(
                child: _Compare(
                  label: 'Before · r$beforeRev',
                  client: client!,
                  frameId: pin.frameId,
                  rev: beforeRev!,
                ),
              ),
              SizedBox(width: S.s8),
              Expanded(
                child: _Compare(
                  label: 'After · r$afterRev',
                  client: client!,
                  frameId: pin.frameId,
                  rev: afterRev!,
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: S.s16),
        Container(
          padding: EdgeInsets.all(S.s12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The agent receives',
                  style: sans(11, weight: W.label, color: AppColors.fg3)),
              SizedBox(height: S.s4),
              Text(
                'frame $frameTitle\n'
                '${pin.elId != null ? 'element ${pin.elId}\n' : ''}'
                'text "${_clip(pin.text)}"',
                style: mono(11, height: 1.5, color: AppColors.fg2),
              ),
            ],
          ),
        ),
        SizedBox(height: S.s16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: () => onApprove(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentFg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                  ),
                  child: Text(pin.isResolved ? 'Reopen' : 'Approve',
                      style: sans(13,
                          weight: W.label, color: AppColors.accentFg)),
                ),
              ),
            ),
            if (onRevert != null) ...[
              SizedBox(width: S.s8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: revertBusy ? null : onRevert,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                    ),
                    child: Text(revertBusy ? 'Reverting...' : 'Revert',
                        style: sans(13, weight: W.label, color: AppColors.fg1)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static String _clip(String t) => t.length > 40 ? '${t.substring(0, 40)}...' : t;
}

class _Compare extends StatelessWidget {
  const _Compare({
    required this.label,
    required this.client,
    required this.frameId,
    required this.rev,
  });

  final String label;
  final CanvasClient client;
  final String frameId;
  final int rev;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: sans(11, color: AppColors.fg3)),
          SizedBox(height: S.s4),
          CanvasRevThumb(client: client, frameId: frameId, rev: rev),
        ],
      );
}

/// Small frame thumbnail at a given revision, fetched once through the
/// canvas client and decoded at thumbnail size.
class CanvasRevThumb extends StatefulWidget {
  const CanvasRevThumb({
    super.key,
    required this.client,
    required this.frameId,
    required this.rev,
  });

  final CanvasClient client;
  final String frameId;
  final int rev;

  @override
  State<CanvasRevThumb> createState() => _CanvasRevThumbState();
}

class _CanvasRevThumbState extends State<CanvasRevThumb> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(CanvasRevThumb old) {
    super.didUpdateWidget(old);
    if (old.frameId != widget.frameId ||
        old.rev != widget.rev ||
        old.client != widget.client) {
      _bytes = _load();
    }
  }

  Future<Uint8List> _load() =>
      widget.client.fetchThumbPng(widget.frameId, 0.5, rev: widget.rev);

  @override
  Widget build(BuildContext context) => Container(
        height: 96,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snap) {
            if (snap.hasData) {
              return Image.memory(
                snap.data!,
                fit: BoxFit.contain,
                cacheWidth: 320,
                gaplessPlayback: true,
              );
            }
            return Center(
              child: snap.hasError
                  ? Text('Not available',
                      style: sans(11, color: AppColors.fg4))
                  : const DelayedSpinner(size: 16),
            );
          },
        ),
      );
}
