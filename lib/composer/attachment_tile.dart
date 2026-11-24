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
    final voice = tiles.where(_voice).toList();
    final rest = tiles.where((w) => !_voice(w)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: S.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in voice)
            Padding(padding: EdgeInsets.only(top: S.s6), child: v),
          if (rest.isNotEmpty && kMobile)
            // Phone spec CH-07: a tray of two-column tiles, 118 high each.
            Container(
              margin: EdgeInsets.only(top: S.s6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(16)),
              child: LayoutBuilder(
                builder: (_, c) => Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final t in rest)
                    SizedBox(width: (c.maxWidth - 10) / 2, child: t),
                ]),
              ),
            )
          else if (rest.isNotEmpty)
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(top: S.s6, right: S.s6),
                itemCount: rest.length,
                separatorBuilder: (_, __) => SizedBox(width: S.s8),
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
    this.sizeBytes,
    this.pastedText,
    this.imageProvider,
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
      padding: EdgeInsets.fromLTRB(S.s8, 0, S.s12, 0),
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
        SizedBox(width: S.s8),
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
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border),
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
                          color: AppColors.accentBg,
                          shape: BoxShape.circle,
                        ),
                        child:
                            AppIcon('play', size: 14, color: AppColors.accent),
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
          child: _tile(),
        );

  static String _bytes(int b) => b < 1024
      ? '$b B'
      : b < 1048576
          ? '${(b / 1024).round()} KB'
          : '${(b / 1048576).toStringAsFixed(1)} MB';

  Widget _phoneTile() {
    final meta = pastedText != null
        ? '${pastedText!.length} chars'
        : (sizeBytes != null
            ? _bytes(sizeBytes!)
            : (isImage ? 'Image' : 'File'));
    final thumb = isImage && localPath != null && File(localPath!).existsSync()
        ? Image.file(File(localPath!),
            fit: BoxFit.cover, cacheWidth: 300, cacheHeight: 150)
        : Center(
            child: AppIcon(
                pastedText != null
                    ? 'file-text'
                    : (mediaKindOf(name) == MediaKind.pdf ? 'pdf' : 'file'),
                size: 20,
                color: AppColors.fg3));
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
      child: Stack(children: [
        Semantics(
          button: onOpen != null,
          label: 'Preview $name',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 72,
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(6)),
                    child: thumb,
                  ),
                  const SizedBox(height: 4),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, weight: W.label, color: AppColors.fg1)),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11, color: AppColors.fg3)),
                ],
              ),
            ),
          ),
        ),
        if (uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.scrim,
                  borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Spinner(size: 16, color: AppColors.fg1),
            ),
          ),
        Positioned(
          top: 0,
          right: 0,
          child: Semantics(
            button: true,
            label: 'Remove $name',
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.surface3, shape: BoxShape.circle),
                    child: AppIcon('x', size: 12, color: AppColors.fg1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tile() => kMobile ? _phoneTile() : _deskTile();

  Widget _deskTile() => Stack(clipBehavior: Clip.none, children: [
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
            child: TapDetector(
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
