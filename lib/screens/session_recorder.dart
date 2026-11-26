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

  Future<void> _attachVoiceTake(Uint8List bytes, String name) =>
      _ingest([(name: name, localPath: null, readBytes: () async => bytes)]);

  Future<void> _pickDesktopPhoto() async {
    final path = await pickLocalImage();
    if (path == null) return;
        final name = path.split('/').last.split('\\').last;
    await _ingest([
      (name: name, localPath: path, readBytes: () => File(path).readAsBytes())
    ]);
  }

  Future<void> _newCanvasFromComposer() async {
    final draft = _input.text.trim();
    final title = draft.isEmpty ? 'Untitled canvas' : draft;
    try {
      final canvas = await widget.client.postCanvas(title);
      final id = canvas['canvas_id'] as String?;
      if (!mounted) return;
      openCanvas(context, canvasId: id, title: title);
    } catch (e) {
      if (mounted) _toast('canvas failed: $e');
    }
  }

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

  /// A file already in this session's workspace: attached by path, no upload.
  Future<void> _attachSessionFile() async {
    final ws = (_state?.workspace ?? '').trim();
    if (ws.isEmpty) {
      _toast('This session has no workspace');
      return;
    }
    List<String> all;
    try {
      all = await widget.client.fsFiles(ws);
    } catch (e) {
      if (mounted) _toast('$e');
      return;
    }
    if (!mounted) return;
    final picked = await showAppSheet<String>(context,
        title: 'Attach a session file',
        maxHeight: 640,
        child: _SessionFilePicker(root: ws, files: all));
    if (picked == null) return;
    final name = picked.split('/').last;
    final a = _Attachment(
        name: name,
        isImage: _isImageName(name),
        isAudio: isAudioAttachmentPath(name))
      ..remotePath = picked.startsWith('/') ? picked : '$ws/$picked'
      ..uploading = false;
    _setState(() => _attachments.add(a));
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
    for (var i = 0; i < entries.length; i++) {
      await _upload(entries[i], picked[i].readBytes);
    }
  }

  /// Uploads one chip; a failure keeps the chip with a Retry instead of
  /// dropping what the user picked.
  Future<void> _upload(
      _Attachment a, Future<Uint8List> Function() readBytes) async {
    final generation = _attachmentGeneration;
    final draftKey = _draftKey;
    try {
      final bytes = await readBytes();
      // A voice take reuses the upload begun when recording stopped.
      final path = await _voice.uploadTake(bytes, a.name);
      if (!mounted || generation != _attachmentGeneration) {
        // The composer moved on mid-upload: the file still belongs to the
        // session it was attached in, as part of that session's draft.
        a.remotePath = path;
        a.uploading = false;
        Drafts.instance.addAttachment(draftKey, a.toDraft());
        return;
      }
      _setState(() {
        a.remotePath = path;
        a.uploading = false;
        a.retry = null;
      });
    } catch (e) {
      if (!mounted || !_attachments.contains(a)) return;
      _setState(() {
        a.uploading = false;
        a.retry = () {
          _setState(() {
            a.uploading = true;
            a.retry = null;
          });
          _upload(a, readBytes);
        };
      });
      _toast('upload failed: ${a.name}');
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

class _SessionFilePicker extends StatefulWidget {
  const _SessionFilePicker({required this.root, required this.files});
  final String root;
  final List<String> files;

  @override
  State<_SessionFilePicker> createState() => _SessionFilePickerState();
}

class _SessionFilePickerState extends State<_SessionFilePicker> {
  final _ctl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() => _q = _ctl.text));
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final f in widget.files)
        if (q.isEmpty || f.toLowerCase().contains(q)) f
    ].take(60).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(controller: _ctl, hint: 'Search files', icon: 'search'),
        SizedBox(height: S.s8),
        Flexible(
          child: shown.isEmpty
              ? Padding(
                  padding: EdgeInsets.all(S.s24),
                  child: Center(
                      child: Text('No files match',
                          style: sans(14, color: AppColors.fg3))))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final f = shown[i];
                    final name = f.split('/').last;
                    final dir = f.contains('/')
                        ? f.substring(0, f.lastIndexOf('/'))
                        : '';
                    return QuietRow(
                      title: name,
                      sub: dir.isEmpty ? null : dir,
                      leading: AppIcon(
                          ComposerAttachmentController.isImageName(name)
                              ? 'image'
                              : 'file',
                          size: 20,
                          color: AppColors.fg2),
                      onTap: () => Navigator.pop(context, f),
                    );
                  }),
        ),
      ],
    );
  }
}
