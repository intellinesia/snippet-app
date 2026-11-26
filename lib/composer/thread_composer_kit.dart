import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../drafts.dart';
import '../platform.dart';
import 'composer_attachments.dart';
import 'voice_note.dart';

/// What the session composer does beyond the shared card, for agent and group
/// threads: drafts that survive leaving and restarts, big pastes as cards,
/// clipboard images and files, keyboard images and file drops.
class ThreadComposerKit {
  ThreadComposerKit({
    required this.input,
    required this.attachments,
    required this.voice,
    required this.draftKey,
    required this.onToast,
  });

  final TextEditingController input;
  final ComposerAttachmentController attachments;
  final VoiceNoteController voice;
  final String draftKey;
  final void Function(String message) onToast;

  /// True while files are dragged over the thread.
  final dragging = ValueNotifier<bool>(false);

  static const _pasteCardChars = 600;
  static const _pasteCardLines = 8;
  static const _pasteFileChars = 30000;
  String _lastInput = '';
  bool _restoring = false;
  int _pasteN = 0;
  String _savedIds = '';
  bool _disposed = false;

  void start() {
    final draft = Drafts.instance.of(draftKey);
    if (draft != null) {
      if (input.text.isEmpty && draft.text.isNotEmpty) {
        _restoring = true;
        input.value = TextEditingValue(
            text: draft.text,
            selection: TextSelection.collapsed(offset: draft.text.length));
        _restoring = false;
      }
      if (attachments.isEmpty) attachments.restore(draft.attachments);
    }
    _lastInput = input.text;
    _savedIds = _ids();
    input.addListener(_onInput);
    attachments.addListener(_onAttachments);
  }

  String _ids() => attachments.readyDrafts().map((d) => d.id).join('|');

  Draft _draft() =>
      Draft(text: input.text, attachments: attachments.readyDrafts());

  void _save({bool now = false}) =>
      Drafts.instance.save(draftKey, _draft(), now: now);

  void _onInput() {
    if (_disposed || _restoring) return;
    _interceptBigPaste();
    _save();
  }

  void _onAttachments() {
    final ids = _ids();
    if (ids == _savedIds) return;
    _savedIds = ids;
    _save();
  }

  // A paste arrives as one controller change, so an insertion this large
  // cannot be typing: it leaves the field and becomes a card.
  void _interceptBigPaste() {
    final prev = _lastInput;
    final now = input.text;
    var p = 0;
    while (p < prev.length && p < now.length && prev[p] == now[p]) {
      p++;
    }
    var s = 0;
    while (s < prev.length - p &&
        s < now.length - p &&
        prev[prev.length - 1 - s] == now[now.length - 1 - s]) {
      s++;
    }
    final inserted = now.substring(p, now.length - s);
    final lines = '\n'.allMatches(inserted).length + 1;
    if (inserted.length < _pasteCardChars && lines < _pasteCardLines) {
      _lastInput = now;
      return;
    }
    _restoring = true;
    input.value = TextEditingValue(
      text: prev,
      selection: TextSelection.collapsed(offset: p.clamp(0, prev.length)),
    );
    _restoring = false;
    _lastInput = prev;
    final name = 'paste-${++_pasteN}.txt';
    if (inserted.length <= _pasteFileChars) {
      attachments.addPasted(inserted, name);
      return;
    }
    unawaited(attachments.ingest([
      (
        name: name,
        localPath: null,
        readBytes: () async => Uint8List.fromList(utf8.encode(inserted)),
      )
    ]));
    onToast('Long paste attached as a file ($lines lines)');
  }

  /// Desktop paste: files or an image on the clipboard attach; text pastes.
  Future<void> paste() async {
    if (await _pasteMedia()) return;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty || _disposed) return;
    final v = input.value;
    final sel = v.selection;
    final start = sel.isValid ? sel.start : v.text.length;
    final end = sel.isValid ? sel.end : v.text.length;
    input.value = v.copyWith(
        text: v.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length));
  }

  Future<bool> _pasteMedia() async {
    if (kMobile) return false;
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        await attachments.ingest([
          for (final path in files)
            (
              name: path.split(RegExp(r'[\\/]')).last,
              localPath: path,
              readBytes: () => File(path).readAsBytes(),
            )
        ]);
        return true;
      }
      final image = await Pasteboard.image;
      if (image != null && image.isNotEmpty) {
        final name = 'pasted-${DateTime.now().millisecondsSinceEpoch}.png';
        await attachments.ingest(
            [(name: name, localPath: null, readBytes: () async => image)]);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// The shared card's keys, plus the desktop paste.
  Map<ShortcutActivator, VoidCallback> shortcuts({
    required bool Function() canSend,
    required VoidCallback onSend,
    Map<ShortcutActivator, VoidCallback> extra = const {},
  }) =>
      {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!kMobile && canSend()) onSend();
        },
        ...extra,
        if (!kMobile)
          SingleActivator(LogicalKeyboardKey.keyV,
              meta: kMacOS, control: !kMacOS): () => unawaited(paste()),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
          if (canSend()) onSend();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (canSend()) onSend();
        },
      };

  /// Images from the Android keyboard (clipboard and screenshot suggestions).
  ContentInsertionConfiguration get keyboardContent =>
      ContentInsertionConfiguration(
        allowedMimeTypes: const [
          'image/png',
          'image/jpeg',
          'image/gif',
          'image/webp',
        ],
        onContentInserted: (content) async {
          final data = content.data;
          if (data == null || data.isEmpty) return;
          final ext = switch (content.mimeType) {
            'image/jpeg' => 'jpg',
            'image/gif' => 'gif',
            'image/webp' => 'webp',
            _ => 'png',
          };
          await attachments.ingest([
            (
              name: 'keyboard-${DateTime.now().millisecondsSinceEpoch}.$ext',
              localPath: null,
              readBytes: () async => data,
            )
          ]);
        },
      );

  /// Files dropped on the thread attach, as in sessions (macOS, like there).
  Widget dropTarget(Widget child) {
    if (!kMacOS) return child;
    return DropTarget(
      onDragEntered: (_) => dragging.value = true,
      onDragExited: (_) => dragging.value = false,
      onDragDone: (details) {
        dragging.value = false;
        unawaited(attachments.ingest([
          for (final item in details.files.whereType<DropItemFile>())
            (
              name: item.name,
              localPath: item.path,
              readBytes: () => _readDropped(item),
            )
        ]));
      },
      child: child,
    );
  }

  static Future<Uint8List> _readDropped(DropItemFile item) async {
    final bookmark = item.extraAppleBookmark;
    var accessed = false;
    try {
      if (bookmark != null && bookmark.isNotEmpty) {
        accessed = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
      }
      return await item.readAsBytes();
    } finally {
      if (accessed) {
        await DesktopDrop.instance
            .stopAccessingSecurityScopedResource(bookmark: bookmark!);
      }
    }
  }

  /// Saves at once; a reviewed voice note is kept as an attachment once its
  /// upload lands, so it survives leaving the thread.
  void dispose() {
    _disposed = true;
    input.removeListener(_onInput);
    attachments.removeListener(_onAttachments);
    final draft = _draft();
    Drafts.instance.save(draftKey, draft, now: true);
    final upload = voice.takeUpload;
    final name = voice.takeName;
    if (upload != null && name != null) {
      unawaited(upload.then((remote) {
        Drafts.instance.save(
            draftKey,
            Draft(text: draft.text, attachments: [
              ...draft.attachments,
              DraftAttachment(name: name, isAudio: true, remotePath: remote),
            ]),
            now: true);
      }).catchError((_) {}));
    }
    dragging.dispose();
  }
}
