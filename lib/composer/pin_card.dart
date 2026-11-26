import 'package:flutter/material.dart';

import '../platform.dart';
import '../tap_detector.dart';
import '../theme.dart';

/// Daemon-owned pinned composer context. The app deliberately has no local
/// factory for this model: it exists only when the session wire exposes one.
class ComposerPinnedMessage {
  const ComposerPinnedMessage({
    required this.id,
    required this.title,
    this.meta = '',
    this.body = '',
  });

  final String id;
  final String title;
  final String meta;
  final String body;
}

/// A resolved pin plus its daemon-backed actions. This mirrors RC-10's nullable
/// loader seam: no resolver, no pin card; no local pretend state.
class ComposerPinResolution {
  const ComposerPinResolution({
    required this.pin,
    this.onUnpin,
    this.onOpen,
    this.onEdit,
  });

  final ComposerPinnedMessage pin;
  final VoidCallback? onUnpin;
  final VoidCallback? onOpen;
  final ValueChanged<String>? onEdit;
}

typedef ComposerPinLookup = ComposerPinResolution? Function(String sessionId);

/// Installed by the session data layer when the daemon exposes pinned composer
/// context. It is null in builds whose wire model has no pinned-message field.
ComposerPinLookup? composerPinLookup;

/// CMP-14: the tonal card for pinned composer context, 10-radius surface1,
/// 36-high tonal actions and a 44-high surface3 edit field.
class ComposerPinCard extends StatefulWidget {
  const ComposerPinCard({
    super.key,
    required this.pin,
    this.onUnpin,
    this.onOpen,
    this.onEdit,
  });

  final ComposerPinnedMessage pin;
  final VoidCallback? onUnpin;
  final VoidCallback? onOpen;
  final ValueChanged<String>? onEdit;

  @override
  State<ComposerPinCard> createState() => _ComposerPinCardState();
}

class _ComposerPinCardState extends State<ComposerPinCard> {
  bool _editing = false;
  late final TextEditingController _edit =
      TextEditingController(text: widget.pin.body.isEmpty ? widget.pin.title : widget.pin.body);

  @override
  void dispose() {
    _edit.dispose();
    super.dispose();
  }

  Widget _button(String label,
      {required bool primary, required VoidCallback? onTap}) {
    final fill = primary ? AppColors.fg1 : AppColors.surface3;
    final ink = primary ? AppColors.bg : AppColors.fg1;
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            maxLines: 1,
            style: sans(12.5, weight: FontWeight.w500, color: ink)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pinned: ${pin.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(15,
                  height: 21 / 15,
                  weight: FontWeight.w500,
                  color: AppColors.fg1)),
          if (pin.meta.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(pin.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, height: 18 / 13, color: AppColors.fg2)),
          ],
          const SizedBox(height: 12),
          if (_editing) ...[
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _edit,
                autofocus: true,
                maxLines: 1,
                style: sans(14, color: AppColors.fg1),
                cursorColor: AppColors.fg1,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (value) {
                  widget.onEdit?.call(value);
                  setState(() => _editing = false);
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(children: [
            _button('Unpin', primary: false, onTap: widget.onUnpin),
            const SizedBox(width: 8),
            _button(_editing ? 'Done' : 'Edit',
                primary: false,
                onTap: widget.onEdit == null
                    ? null
                    : () {
                        if (_editing) widget.onEdit?.call(_edit.text);
                        setState(() => _editing = !_editing);
                      }),
            const Spacer(),
            _button('Open', primary: true, onTap: widget.onOpen),
          ]),
        ],
      ),
    );
  }
}

/// Resolve and render CMP-14 only when the daemon-backed lookup supplies a
/// pinned-message model. Returns zero-sized UI when no such model exists.
Widget composerPinCardForSession(String sessionId) {
  if (!kMobile) return const SizedBox.shrink();
  final resolved = composerPinLookup?.call(sessionId);
  if (resolved == null) return const SizedBox.shrink();
  return ComposerPinCard(
    pin: resolved.pin,
    onUnpin: resolved.onUnpin,
    onOpen: resolved.onOpen,
    onEdit: resolved.onEdit,
  );
}
