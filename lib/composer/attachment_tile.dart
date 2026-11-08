import 'dart:io';

import 'package:flutter/material.dart';

import '../media_views.dart';
import '../theme.dart';
import '../widgets.dart';

class ComposerAttachmentBar extends StatelessWidget {
  const ComposerAttachmentBar({super.key, required this.tiles});

  final List<Widget> tiles;

  static bool _voice(Widget w) => w is ComposerAttachmentTile && w.isAudio;

  @override
  Widget build(BuildContext context) {
    final voice = tiles.where(_voice).toList();
    final rest = tiles.where((w) => !_voice(w)).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in voice)
            Padding(padding: const EdgeInsets.only(top: 6), child: v),
          if (rest.isNotEmpty)
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(top: 6, right: 6),
                itemCount: rest.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => rest[i],
              ),
            ),
        ],
      ),
    );
  }
}

/// Thumbnail or file card with an upload overlay and a remove button. A caller
/// with a special body (pasted text, remote image) passes it as [body].
class ComposerAttachmentTile extends StatelessWidget {
  const ComposerAttachmentTile({
    super.key,
    required this.name,
    required this.isImage,
    required this.isAudio,
    required this.uploading,
    required this.onRemove,
    this.onOpen,
    this.localPath,
    this.body,
  });

  final String name;
  final bool isImage;
  final bool isAudio;
  final bool uploading;
  final VoidCallback onRemove;

  /// Tapping the tile body, e.g. to preview it.
  final VoidCallback? onOpen;
  final String? localPath;
  final Widget? body;

  static const side = 56.0;

  Widget _defaultBody() {
    final kind = isAudio
        ? MediaKind.audio
        : (isImage ? MediaKind.image : mediaKindOf(name));
    if (isImage && localPath != null && File(localPath!).existsSync()) {
      return Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(File(localPath!),
            fit: BoxFit.cover, cacheWidth: 168, cacheHeight: 168),
      );
    }
    final ext =
        name.contains('.') ? name.split('.').last.toUpperCase() : 'FILE';
    return Container(
      height: side,
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isAudio ? AppColors.accentBg : AppColors.surface3,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: AppIcon(
              isAudio ? 'mic' : (kind == MediaKind.pdf ? 'pdf' : 'file'),
              size: 16,
              color: isAudio ? AppColors.accent : AppColors.fg2),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAudio ? 'Voice note' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, weight: W.label, color: AppColors.fg1)),
              Text(isAudio ? 'Audio' : (ext.length > 6 ? 'FILE' : ext),
                  style: mono(10, color: AppColors.fg3)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _voiceRow() => Pressable(
        kind: PressKind.row,
        radius: R.md,
        enabled: onOpen != null,
        child: Semantics(
          button: onOpen != null,
          label: uploading ? 'Voice note, uploading' : 'Voice note',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Container(
              height: 48,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Stack(children: [
                Row(children: [
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentBg,
                      shape: BoxShape.circle,
                    ),
                    child: AppIcon(uploading ? 'mic' : 'play',
                        size: 14, color: AppColors.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Voice note',
                            maxLines: 1,
                            style: sans(13,
                                weight: W.label, color: AppColors.fg1)),
                        Text(uploading ? 'Uploading…' : 'Ready to send',
                            maxLines: 1,
                            style: sans(12, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  IconBtn('x',
                      size: 32,
                      iconSize: 14,
                      tooltip: 'Remove voice note',
                      onTap: onRemove),
                  const SizedBox(width: 4),
                ]),
                if (uploading)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: AppColors.accent,
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => isAudio && body == null
      ? _voiceRow()
      : Stack(clipBehavior: Clip.none, children: [
        onOpen == null
            ? (body ?? _defaultBody())
            : Semantics(
                button: true,
                label: 'Preview $name',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: body ?? _defaultBody(),
                  ),
                ),
              ),
        if (uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.scrim,
                  borderRadius: BorderRadius.circular(R.md)),
              alignment: Alignment.center,
              child: Spinner(size: 16, color: AppColors.fg1),
            ),
          ),
        Positioned(
          top: -6,
          right: -6,
          child: Semantics(
            button: true,
            label: 'Remove $name',
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bg, width: 2),
                ),
                child: AppIcon('x', size: 10, color: AppColors.fg1),
              ),
            ),
          ),
        ),
      ]);
}
