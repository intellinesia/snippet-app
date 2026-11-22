import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../drafts.dart';
import '../media_views.dart' show pastedTextBlock;
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'attachment_preview.dart';
import 'attachment_tile.dart';

typedef PickedAttachment = ({
  String name,
  String? localPath,
  Future<Uint8List> Function() readBytes,
});

class ComposerAttachment {
  final String name;
  final bool isImage;
  final bool isAudio;
  final String? localPath;
  String? remotePath;
  bool uploading;

  /// Text pasted into the composer, kept as a card and sent inline.
  final String? pastedText;

  ComposerAttachment({
    required this.name,
    required this.isImage,
    required this.isAudio,
    this.localPath,
    this.remotePath,
    this.uploading = true,
    this.pastedText,
  });

  bool get ready => remotePath != null || pastedText != null;

  DraftAttachment toDraft() => DraftAttachment(
        name: name,
        isImage: isImage,
        isAudio: isAudio,
        localPath: localPath,
        remotePath: remotePath,
        pastedText: pastedText,
      );
}

/// Manages picked attachments, background uploads, previewing, and marker
/// formatting for chat composers.
class ComposerAttachmentController extends ChangeNotifier {
  ComposerAttachmentController({
    required this.client,
    required this.onToast,
    this.pickFilesOverride,
  });

  final DaemonClient client;
  final void Function(String message, {bool danger}) onToast;
  final Future<List<PickedLocalFile>> Function()? pickFilesOverride;

  final List<ComposerAttachment> items = [];
  int _generation = 0;
  bool _disposed = false;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  bool get isUploading => items.any((a) => a.uploading);

  static bool isImageName(String name) {
    final l = name.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
      '.heif',
    ].any(l.endsWith);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void debugSeed(String name) {
    items.add(ComposerAttachment(
      name: name,
      isImage: false,
      isAudio: false,
      uploading: false,
    ));
    notifyListeners();
  }

  Future<void> pickFromSheet(BuildContext context) async {
    if (!kMobile) {
      await pickFiles();
      return;
    }
    final choice = await showAppSheet<String>(
      context,
      title: 'Attach',
      child: Padding(
        padding: EdgeInsets.only(bottom: S.s8),
        child: Row(
          children: [
            _attachOption(context, 'camera', 'Camera', 'camera'),
            SizedBox(width: S.of(10)),
            _attachOption(context, 'image', 'Photos', 'photos'),
            SizedBox(width: S.of(10)),
            _attachOption(context, 'file', 'Files', 'files'),
          ],
        ),
      ),
    );
    if (choice == 'camera') {
      await _pickCamera();
    } else if (choice == 'photos') {
      await _pickPhotos();
    } else if (choice == 'files') {
      await pickFiles();
    }
  }

  Widget _attachOption(
      BuildContext context, String icon, String label, String value) {
    return Expanded(
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: () {
            tapHaptic();
            Navigator.pop(context, value);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: S.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 22, color: AppColors.fg2),
                SizedBox(height: S.s8),
                Text(label, style: sans(12, color: AppColors.fg1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhotos() async {
    final xs =
        await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2200);
    if (xs.isEmpty) return;
    await ingest(xs
        .map((x) => (name: x.name, localPath: x.path, readBytes: x.readAsBytes))
        .toList());
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    await ingest([(name: x.name, localPath: x.path, readBytes: x.readAsBytes)]);
  }

  Future<void> pickFiles() async {
    List<PickedLocalFile> files;
    try {
      files = await (pickFilesOverride?.call() ?? pickLocalFiles());
    } catch (e) {
      if (!_disposed) onToast('$e', danger: true);
      return;
    }
    if (files.isEmpty) return;
    await ingest(files
        .map((f) => (
              name: f.name,
              localPath: f.path,
              readBytes: f.readAsBytes,
            ))
        .toList());
  }

  /// [upload] lets a voice note reuse the upload begun when recording stopped.
  Future<void> ingest(List<PickedAttachment> picked,
      {Future<String> Function(Uint8List bytes, String name)? upload}) async {
    final entries = picked
        .map((p) => ComposerAttachment(
              name: p.name,
              isImage: isImageName(p.name),
              isAudio: isAudioAttachmentPath(p.name),
              localPath: p.localPath,
            ))
        .toList();
    if (entries.isEmpty) return;
    items.addAll(entries);
    notifyListeners();
    final generation = _generation;
    for (var i = 0; i < entries.length; i++) {
      final p = picked[i];
      final a = entries[i];
      try {
        final bytes = await p.readBytes();
        final path = upload != null
            ? await upload(bytes, p.name)
            : await client.uploadFile(bytes, name: p.name);
        if (_disposed || generation != _generation) return;
        a.remotePath = path;
        a.uploading = false;
        notifyListeners();
      } catch (_) {
        if (_disposed) return;
        items.remove(a);
        notifyListeners();
        onToast('Upload failed: ${p.name}', danger: true);
      }
    }
  }

  void addPasted(String text, String name) {
    items.add(ComposerAttachment(
      name: name,
      isImage: false,
      isAudio: false,
      uploading: false,
      pastedText: text,
    ));
    notifyListeners();
  }

  /// Brings back a saved draft's attachments; they are uploaded already.
  void restore(List<DraftAttachment> saved) {
    if (saved.isEmpty) return;
    items.addAll(saved.map((d) => ComposerAttachment(
          name: d.name,
          isImage: d.isImage,
          isAudio: d.isAudio,
          localPath: d.localPath,
          remotePath: d.remotePath,
          pastedText: d.pastedText,
          uploading: false,
        )));
    notifyListeners();
  }

  List<DraftAttachment> readyDrafts() =>
      [for (final a in items) if (a.ready) a.toDraft()];

  void remove(ComposerAttachment a) {
    items.remove(a);
    notifyListeners();
  }

  void clear() {
    _generation++;
    items.clear();
    notifyListeners();
  }

  List<String> markers() => [
        for (final a in items)
          if (a.pastedText case final pasted?)
            pastedTextBlock(pasted)
          else if (a.remotePath != null)
            a.isImage
                ? '[attached image — call view_image on this exact path to see it: ${a.remotePath}]'
                : '[attached file — read it at this exact path: ${a.remotePath}]',
      ];

  String appendMarkers(String text) {
    final trimmed = text.trim();
    final m = markers();
    if (m.isEmpty) return trimmed;
    return trimmed.isEmpty ? m.join('\n\n') : '$trimmed\n\n${m.join('\n\n')}';
  }

  Widget buildBar(BuildContext context) => ComposerAttachmentBar(tiles: [
        for (final a in items)
          ComposerAttachmentTile(
            name: a.name,
            isImage: a.isImage,
            isAudio: a.isAudio,
            uploading: a.uploading,
            localPath: a.localPath,
            body: a.pastedText == null
                ? null
                : PastedAttachmentBody(text: a.pastedText!),
            onOpen: a.pastedText == null ? () => preview(context, a) : null,
            onRemove: () => remove(a),
          ),
      ]);

  Future<void> preview(BuildContext context, ComposerAttachment a) {
    final pairs = {
      for (final x in items.where((x) => x.pastedText == null))
        PreviewAttachment(
          name: x.name,
          isImage: x.isImage,
          isAudio: x.isAudio,
          localPath: x.localPath,
          imageProvider: x.remotePath == null
              ? null
              : client.imageProvider(x.remotePath!),
        ): x,
    };
    return showAttachmentPreview(
      context,
      pairs.keys.toList(),
      pairs.values.toList().indexOf(a),
      onRemove: (p) {
        final target = pairs[p];
        if (target != null) remove(target);
      },
    );
  }
}
