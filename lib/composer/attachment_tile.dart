import 'dart:io';

import 'package:flutter/material.dart';

import '../media_views.dart';
import '../theme.dart';
import '../widgets.dart';

class ComposerAttachmentBar extends StatelessWidget {
  const ComposerAttachmentBar({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 6, right: 6),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => tiles[i],
          ),
        ),
      );
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
    this.localPath,
    this.body,
  });

  final String name;
  final bool isImage;
  final bool isAudio;
  final bool uploading;
  final VoidCallback onRemove;
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
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : 'FILE';
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

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        body ?? _defaultBody(),
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
