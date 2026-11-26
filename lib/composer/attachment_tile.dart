import 'dart:io';

import 'package:flutter/material.dart';

import '../media_views.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../tap_detector.dart';
import 'attachment_hover_preview.dart';

class ComposerAttachmentBar extends StatelessWidget {
  const ComposerAttachmentBar({super.key, required this.tiles});

  final List<Widget> tiles;

  static bool _voice(Widget w) => w is ComposerAttachmentTile && w.isAudio;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    if (!kMobile) {
      return LayoutBuilder(builder: (_, box) {
        final wide = box.maxWidth >= 500;
        final cols = wide ? 2 : 1;
        const gap = 8.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final t in tiles) SizedBox(width: w, child: t),
        ]);
      });
    }
    final voice = tiles.where(_voice).toList();
    final rest = tiles.where((w) => !_voice(w)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: S.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in [...voice, ...rest])
            Padding(padding: EdgeInsets.only(top: S.s6), child: t),
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
    this.sizeBytes,
    this.pastedText,
    this.imageProvider,
    this.onRetry,
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

  /// Data for the desktop hover card.
  final int? sizeBytes;
  final String? pastedText;
  final ImageProvider? imageProvider;

  /// Non-null once the upload failed; the tile shows the failure and Retry.
  final VoidCallback? onRetry;
  bool get _failed => onRetry != null;

  Widget _retryBtn() => IconBtn('refresh',
      size: 28, iconSize: 13, tooltip: 'Retry upload', onTap: onRetry);

  static const side = 56.0;

  // Uploading shows the note dimmed rather than a progress animation.
  Widget _voiceRow() => Pressable(
        kind: PressKind.row,
        radius: R.md,
        enabled: onOpen != null && !uploading,
        child: Semantics(
          button: onOpen != null,
          label: uploading ? 'Voice note, uploading' : 'Voice note',
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: uploading ? null : onOpen,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(
                  child: AnimatedOpacity(
                    opacity: uploading ? 0.4 : 1,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: Row(children: [
                      SizedBox(width: S.s8),
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface3,
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon('play', size: 14, color: AppColors.fg1),
                      ),
                      SizedBox(width: S.s12),
                      Expanded(child: NoteWaveStrip(seed: name.hashCode)),
                    ]),
                  ),
                ),
                SizedBox(width: S.s8),
                IconBtn('x',
                    size: 32,
                    iconSize: 14,
                    tooltip: 'Remove voice note',
                    onTap: onRemove),
                SizedBox(width: S.s4),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => isAudio && body == null
      ? _voiceRow()
      : AttachmentHoverPreview(
          name: name,
          isImage: isImage,
          localPath: localPath,
          sizeBytes: sizeBytes,
          pastedText: pastedText,
          imageProvider: imageProvider,
          child: _tile(context),
        );

  static String _bytes(int b) => b < 1024
      ? '$b B'
      : b < 1048576
          ? '${(b / 1024).round()} KB'
          : '${(b / 1048576).toStringAsFixed(1)} MB';

  Widget _phoneTile(BuildContext context) {
    final meta = _failed
        ? 'Upload failed'
        : pastedText != null
            ? '${pastedText!.length} chars'
            : (_effectiveSizeBytes != null
                ? _bytes(_effectiveSizeBytes!)
                : (isImage ? 'Image' : 'File'));
    final icon = pastedText != null
        ? 'file-text'
        : isImage
            ? 'image'
            : (mediaKindOf(name) == MediaKind.pdf ? 'pdf' : 'file');
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const SizedBox(width: 10),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage && localPath != null && File(localPath!).existsSync()
              ? Image.file(File(localPath!), fit: BoxFit.cover)
              : Center(child: AppIcon(icon, size: 16, color: AppColors.fg2)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            button: onOpen != null,
            label: 'Preview $name',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: uploading ? null : onOpen,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14,
                          height: 19 / 14,
                          weight: FontWeight.w500,
                          color: uploading ? AppColors.fg2 : AppColors.fg1)),
                  if (MediaQuery.textScalerOf(context).scale(14) <= 19)
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12,
                            height: 16 / 12,
                            color: _failed ? AppColors.danger : AppColors.fg2)),
                ],
              ),
            ),
          ),
        ),
        if (uploading)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Spinner(size: 14, color: AppColors.fg2),
          ),
        if (_failed) _retryBtn(),
        Semantics(
          button: true,
          label: 'Remove $name',
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: SizedBox(
              width: 40,
              height: 40,
              child:
                  Center(child: AppIcon('x', size: 14, color: AppColors.fg2)),
            ),
          ),
        ),
        const SizedBox(width: 6),
      ]),
    );
  }

  Widget _tile(BuildContext context) =>
      kMobile ? _phoneTile(context) : _deskTile();

  int? get _effectiveSizeBytes {
    if (sizeBytes != null) return sizeBytes;
    if (pastedText != null) return pastedText!.length;
    final path = localPath;
    if (path == null) return null;
    try {
      final f = File(path);
      return f.existsSync() ? f.lengthSync() : null;
    } catch (_) {
      return null;
    }
  }

  Widget _deskIcon() {
    final kind = isAudio
        ? MediaKind.audio
        : (isImage ? MediaKind.image : mediaKindOf(name));
    final icon = isAudio
        ? 'mic'
        : pastedText != null
            ? 'file-text'
            : switch (kind) {
                MediaKind.image => 'image',
                MediaKind.pdf => 'pdf',
                _ => 'file',
              };
    return AppIcon(icon, size: 15, color: AppColors.fg2);
  }

  Widget _deskTile() {
    final bytes = _effectiveSizeBytes;
    final state = uploading
        ? 'Uploading'
        : _failed
            ? 'Upload failed'
            : pastedText != null
                ? '${pastedText!.length} chars'
                : bytes != null
                    ? _bytes(bytes)
                    : isImage
                        ? 'Image'
                        : 'File';
    final row = Container(
      height: 44,
      padding: const EdgeInsets.only(left: 10, right: 0),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(R.of(8)),
      ),
      child: Row(children: [
        _deskIcon(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAudio ? 'Voice note' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12,
                      weight: FontWeight.w500,
                      height: 16 / 12,
                      color: AppColors.fg1)),
              Text(state,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(11,
                      height: 14 / 11,
                      color: _failed ? AppColors.danger : AppColors.fg2)),
              if (uploading)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: AppColors.fg2,
                    backgroundColor: AppColors.surface1,
                  ),
                ),
            ],
          ),
        ),
        if (_failed) _retryBtn(),
        Semantics(
          button: true,
          label: 'Remove $name',
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: SizedBox(
              width: 28,
              height: 28,
              child:
                  Center(child: AppIcon('x', size: 12, color: AppColors.fg2)),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ]),
    );
    if (onOpen == null || uploading) return row;
    return Semantics(
      button: true,
      label: 'Preview $name',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: row,
        ),
      ),
    );
  }
}

/// A pasted-text attachment: its size and first line, shared by every composer.
class PastedAttachmentBody extends StatelessWidget {
  const PastedAttachmentBody({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(text.trimRight()).length + 1;
    final firstLine = text.trim().split('\n').first.trim();
    return Container(
      height: ComposerAttachmentTile.side,
      width: 176,
      padding: EdgeInsets.fromLTRB(S.of(10), S.s8, S.s12, S.s8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            AppIcon('file-text', size: 12, color: AppColors.fg3),
            SizedBox(width: S.of(5)),
            Text('Pasted · $lines lines',
                style: sans(11, weight: W.label, color: AppColors.fg2)),
          ]),
          SizedBox(height: S.s4),
          Text(firstLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(11, color: AppColors.fg3)),
        ],
      ),
    );
  }
}
