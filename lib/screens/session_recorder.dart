part of 'session.dart';

extension _SessionScreenRecorderExt on _SessionScreenState {
  Future<void> _onAttachTap() async {
    if (!kMobile) {
      _pickFiles();
      return;
    }
    final choice = await showAppSheet<String>(context,
        title: 'Add context',
        child: Row(children: [
          _ctxOption('camera', 'Camera', 'camera'),
          SizedBox(width: S.s8),
          _ctxOption('image', 'Photos', 'photos'),
          SizedBox(width: S.s8),
          _ctxOption('file', 'Files', 'files'),
        ]));
    if (choice == 'camera') {
      _pickCamera();
    } else if (choice == 'photos') {
      _pickPhotos();
    } else if (choice == 'files') {
      _pickFiles();
    }
  }

  Future<void> _attachVoiceTake(Uint8List bytes, String name) => _ingest([
        (name: name, localPath: null, readBytes: () async => bytes)
      ]);

  Widget _ctxOption(String icon, String label, String value) {
    return Expanded(
      child: Builder(
        builder: (tileContext) => Material(
          color: SurfaceScope.groupOf(tileContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.md),
            side: BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.pop(tileContext, value),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: S.s12),
              child: Column(children: [
                AppIcon(icon, size: 20, color: AppColors.fg1),
                SizedBox(height: S.s6),
                Text(label, style: TS.label(AppColors.fg2)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    List<PickedLocalFile> files;
    try {
      files = await pickLocalFiles();
    } catch (e) {
      _toast('$e');
      return;
    }
    if (files.isEmpty) return;
    await _ingest(files
        .map((f) => (
              name: f.name,
              localPath: f.path,
              readBytes: f.readAsBytes,
            ))
        .toList());
  }

  /// Images and files on the system clipboard (desktop). Returns false when
  /// the clipboard holds neither, so the caller falls back to a text paste.
  Future<bool> _pasteMedia() async {
    if (kMobile) return false;
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        await _ingest([
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
        await _ingest(
            [(name: name, localPath: null, readBytes: () async => image)]);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _pasteFromShortcut() async {
    if (await _pasteMedia()) return;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty || !mounted) return;
    final v = _input.value;
    final sel = v.selection;
    final start = sel.isValid ? sel.start : v.text.length;
    final end = sel.isValid ? sel.end : v.text.length;
    _input.value = v.copyWith(
        text: v.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length));
  }

  /// Images from the Android keyboard (Gboard's clipboard and screenshot
  /// suggestions, stickers, GIFs).
  ContentInsertionConfiguration get _keyboardContent =>
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
          await _ingest([
            (
              name: 'keyboard-${DateTime.now().millisecondsSinceEpoch}.$ext',
              localPath: null,
              readBytes: () async => data,
            )
          ]);
        },
      );

  Future<void> _pickPhotos() async {
    final xs =
        await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2200);
    if (xs.isEmpty) return;
    await _ingest(xs
        .map((x) => (name: x.name, localPath: x.path, readBytes: x.readAsBytes))
        .toList());
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    await _ingest(
        [(name: x.name, localPath: x.path, readBytes: x.readAsBytes)]);
  }

  // Create attachment chips for the picked items (capped to 10 total) and upload each.
  Future<void> _ingest(
      List<
              ({
                String name,
                String? localPath,
                Future<Uint8List> Function() readBytes
              })>
          picked) async {
    final entries = picked
        .map((p) => _Attachment(
            name: p.name,
            isImage: _isImageName(p.name),
            isAudio: isAudioAttachmentPath(p.name),
            localPath: p.localPath))
        .toList();
    if (entries.isEmpty) return;
    _setState(() => _attachments.addAll(entries));
    final generation = _attachmentGeneration;
    final draftKey = _draftKey;
    for (var i = 0; i < entries.length; i++) {
      final p = picked[i];
      final a = entries[i];
      try {
        final bytes = await p.readBytes();
        // A voice take reuses the upload begun when recording stopped.
        final path = await _voice.uploadTake(bytes, p.name);
        if (!mounted || generation != _attachmentGeneration) {
          // The composer moved on mid-upload: the file still belongs to the
          // session it was attached in, as part of that session's draft.
          a.remotePath = path;
          a.uploading = false;
          Drafts.instance.addAttachment(draftKey, a.toDraft());
          continue;
        }
        _setState(() {
          a.remotePath = path;
          a.uploading = false;
        });
      } catch (e) {
        if (!mounted) return;
        _setState(() => _attachments.remove(a));
        _toast('upload failed: ${p.name}');
      }
    }
  }

  Future<void> _consumeInboundShare(SharedInbound share) async {
    if (_consumedShare == share || share.isEmpty) return;
    _consumedShare = share;
    // Drop it at the source immediately: mobile destroys non-active session
    // states, and a fresh state re-runs initState → consume → resend.
    widget.onShareConsumed?.call();
    // Stage the share in the composer — text pre-filled, attachments attached
    // — but never auto-send. The user writes their message around it and sends
    // like they normally would.
    if (share.text.trim().isNotEmpty) {
      final existing = _input.text;
      _input.text = existing.isEmpty
          ? share.text.trim()
          : '${existing.trim()}\n\n${share.text.trim()}';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    if (share.paths.isNotEmpty) {
      await _ingest([
        for (var i = 0; i < share.paths.length; i++)
          (
            name: i < share.names.length && share.names[i].isNotEmpty
                ? share.names[i]
                : share.paths[i].split('/').last,
            localPath: share.paths[i],
            readBytes: () => File(share.paths[i]).readAsBytes(),
          ),
      ]);
    }
    if (share.send) {
      for (var i = 0; i < 50 && mounted && _channel == null; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (mounted) await _sendMessage();
    }
  }
}

/// The newest samples, right-aligned so the wave scrolls in as you speak; in
/// review the part already played is drawn in the accent.
