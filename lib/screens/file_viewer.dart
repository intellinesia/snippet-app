import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'file_preview_parts.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../file_actions.dart';
import '../highlight.dart';
import '../models.dart';
import '../motion_routes.dart';
import '../notifications.dart';
import '../panel.dart';
import '../platform.dart';
import '../media_views.dart';
import '../theme.dart';
import '../widgets.dart';
import 'editor.dart';

/// The surface a phone can show. `onOpenFile` opens the file as a shell TAB,
/// which is a desktop concept: the phone shell renders `_activeTab`, and a file
/// tab is AUXILIARY, so `_activeTab` skips it and `_mobileShell` never draws it.
/// Honouring that callback on a phone therefore pushed a view the phone does not
/// render, and tapping a file appeared to do nothing.
///
/// Shared so a file reached from the browser and one reached from an agent's
/// `present_file` card cannot diverge — the card called the tab callback
/// directly and so kept the old, dead behaviour after the browser was fixed.
Future<void> pushFileViewerRoute(
  BuildContext context, {
  required DaemonClient client,
  required String path,
  required String name,
}) {
  return Navigator.of(context).push(AppPageRoute<void>(
    builder: (_) => FileViewer(
      client: client,
      path: path,
      name: name,
      onClose: () => Navigator.of(context).pop(),
    ),
  ));
}

/// Open a file for viewing, choosing the surface the CURRENT platform can show.
///
/// Returns true when this handled the open (a phone route was pushed); false
/// means the caller should run its own desktop path — a shell tab, or a panel.
///
/// Phones MUST take the route. `onOpenFileTab` creates a shell TAB, and the
/// phone shell renders `_activeTab`, which skips auxiliary tabs — so a file tab
/// is never drawn and the tap appears to do nothing. Both the file browser and
/// the agent's `present_file` card got this wrong by calling the tab callback
/// directly, so the decision lives in ONE place and a third call site cannot
/// repeat it.
bool openFileForViewing(
  BuildContext context, {
  required DaemonClient client,
  required String path,
  required String name,
}) {
  if (!kMobile) return false;
  if (mediaKindOf(path) == MediaKind.image) {
    showImageViewer(context, client: client, path: path);
  } else {
    pushFileViewerRoute(context, client: client, path: path, name: name);
  }
  return true;
}

Future<void> presentFileOnDesktop(
  BuildContext context, {
  required DaemonClient client,
  required String path,
  required String name,
}) {
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    purpose: ShellPanelPurpose.file,
    panelId: path,
    originClient: client,
    maxWidth: 1060,
    maxHeight: 760,
    builder: (_, close) =>
        FileViewer(client: client, path: path, name: name, onClose: close),
  );
}

String _homeShort(String path) =>
    path.replaceFirst(RegExp(r'^/(home|Users)/[^/]+(?=/|$)'), '~');

/// The phone header's Edit button: a pill beside the download action.
class _EditPill extends StatelessWidget {
  const _EditPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: S.s8),
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.pill),
            onTap: onTap,
            child: Container(
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: S.of(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('edit', size: 15, color: AppColors.fg1),
                SizedBox(width: S.s6),
                Text('Edit',
                    style: sans(14, weight: W.label, color: AppColors.fg1)),
              ]),
            ),
          ),
        ),
      );
}

/// One row over a file: mode tabs, size, save and download.
class _FileToolbar extends StatelessWidget {
  const _FileToolbar(
      {this.leading = const [], this.meta, this.actions = const []});
  final List<Widget> leading;
  final String? meta;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
        height: kMobile ? 40 : PaneRow.height,
        padding: EdgeInsets.only(left: S.s12, right: S.s8),
        decoration: kMobile
            ? null
            : BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.paneLine, width: AppColors.hairline))),
        child: Row(children: [
          ...leading,
          const Spacer(),
          if (meta != null)
            Text(meta!,
                style: kMobile
                    ? mono(10, color: AppColors.fg3)
                    : sans(12, color: AppColors.fg4)),
          if (meta != null && actions.isNotEmpty) SizedBox(width: S.s8),
          ...actions,
        ]),
      );
}

/// Viewer for one file; editable in place on desktop.
class FileViewer extends StatefulWidget {
  final DaemonClient client;
  final String path;
  final String name;
  final VoidCallback? onClose;

  /// When true (desktop/shell tab), the window already has a tab strip —
  /// skip the in-pane title bar and put download/edit on a thin action row.
  final bool embedded;

  /// Session and workspace-relative path: when both are set the viewer asks
  /// git for this file's changes (Modified chip, gutter marks, +/- totals).
  final String? sessionId;
  final String? relPath;

  /// Shows a Diff button that opens the file's diff.
  final VoidCallback? onShowDiff;

  /// False when the host already draws a header above the embedded viewer.
  final bool header;
  const FileViewer(
      {super.key,
      required this.client,
      required this.path,
      required this.name,
      this.onClose,
      this.embedded = false,
      this.sessionId,
      this.relPath,
      this.onShowDiff,
      this.header = true});
  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  final CodeLineEditingController _controller = CodeLineEditingController();
  FileContent? _f;
  bool _loading = true;
  bool _downloading = false;
  String? _error;
  String _initial = '';
  String _hash = '';
  bool _crlf = false;
  bool _dirty = false;
  bool _saving = false;
  DiffMarks? _marks;
  final FocusNode _focus = FocusNode();

  // Desktop edits in place; phones keep the separate editor screen.
  bool get _inline => !kMobile && (_f?.editable ?? false);

  String _normalized(String s) =>
      s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  void _onChanged() {
    final d = _normalized(_controller.text) != _initial;
    if (d != _dirty && mounted) setState(() => _dirty = d);
  }

  Future<void> _save({bool force = false}) async {
    if (_saving || !_dirty) return;
    setState(() => _saving = true);
    try {
      final text = _normalized(_controller.text);
      final r = await widget.client.writeFile(
          widget.path, _crlf ? text.replaceAll('\n', '\r\n') : text,
          prevHash: force ? null : _hash);
      if (!mounted) return;
      setState(() => _saving = false);
      if (r['ok'] == true) {
        _initial = text;
        _hash = r['hash'] as String? ?? _hash;
        setState(() => _dirty = _normalized(_controller.text) != text);
        return;
      }
      if (r['conflict'] == true) {
        final overwrite = await confirmAction(context,
            title: 'File changed on disk',
            body:
                'It was modified since you opened it. Overwrite it with your version?',
            confirmLabel: 'Overwrite');
        if (overwrite && mounted) await _save(force: true);
      } else {
        toast(context, (r['error'] as String?) ?? 'Save failed', danger: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, '$e', danger: true);
      }
    }
  }

  static const _imageExts = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'avif'
  };
  static const _videoExts = {'mp4', 'm4v', 'mov', 'webm', 'mkv', 'avi'};
  static const _audioExts = {'mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac'};
  String get _ext {
    final d = widget.name.lastIndexOf('.');
    return d >= 0 ? widget.name.substring(d + 1).toLowerCase() : '';
  }

  bool get _isImage => _imageExts.contains(_ext);
  bool get _isMarkdown => const {'md', 'markdown', 'mdx'}.contains(_ext);
  bool _source = false;

  Widget _modeTab(String label, bool on, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kMobile ? R.md : PaneRow.radius),
        child: AnimatedContainer(
          duration: Motion.quick,
          height: kMobile ? null : PaneRow.pill,
          alignment: kMobile ? null : Alignment.center,
          padding: EdgeInsets.symmetric(
              horizontal: S.of(10), vertical: kMobile ? S.s4 : 0),
          decoration: BoxDecoration(
            color: on
                ? (kMobile ? AppColors.surface2 : PaneRow.plate)
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(kMobile ? R.md : PaneRow.radius),
          ),
          child: Text(label,
              style: sans(kMobile ? 13 : PaneRow.label,
                  color: on
                      ? (kMobile ? AppColors.fg1 : PaneRow.labelOn)
                      : (kMobile ? AppColors.fg3 : PaneRow.labelOff))),
        ),
      );

  Widget _markdownView(String content) => SelectionArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(kMobile ? M.gutter : S.of(28), S.s20,
              kMobile ? M.gutter : S.of(28), S.of(48)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SizedBox(
                width: double.infinity,
                child: MarkdownBody(
                  data: content,
                  selectable: false,
                  styleSheet: kMobile
                      ? markdownStyle(context)
                      : documentMarkdownStyle(context),
                  builders: {'pre': PreBlockBuilder()},
                  onTapLink: (_, href, __) => openMarkdownLink(href, context),
                ),
              ),
            ),
          ),
        ),
      );
  bool get _isVideo => _videoExts.contains(_ext);
  bool get _isAudio => _audioExts.contains(_ext);
  // Phones render PDFs on device; desktop keeps the download path.
  bool get _isPdf => kMobile && _ext == 'pdf';
  bool get _isMedia => _isImage || _isVideo || _isAudio || _isPdf;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final message = await downloadRemoteFileWithCancel(
        context,
        widget.client,
        path: widget.path,
        name: widget.name,
      );
      if (!mounted) return;
      setState(() => _downloading = false);
      if (message != null) toast(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Media renders straight from its streaming URL — no text read.
    if (_isMedia) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMarks() async {
    final sid = widget.sessionId, rel = widget.relPath;
    if (kMobile || sid == null || rel == null) return;
    try {
      final patch = await widget.client.gitDiff(sid, file: rel);
      if (mounted) setState(() => _marks = DiffMarks.parse(patch));
    } catch (_) {}
  }

  void _edit() {
    if (_isMarkdown && !_source) setState(() => _source = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Widget _desktopHeader(FileContent? f) {
    final text = f != null && !f.binary && !_isMedia && _error == null;
    final marks = _marks;
    return _FileHeaderBar(
      path: widget.relPath ?? _homeShort(widget.path),
      modified: _dirty || (marks != null && !marks.isEmpty),
      leading: [
        if (text && _isMarkdown) ...[
          _modeTab('Preview', !_source, () => setState(() => _source = false)),
          SizedBox(width: S.s4),
          _modeTab('Source', _source, () => setState(() => _source = true)),
          SizedBox(width: S.s8),
        ],
      ],
      actions: [
        if (_inline && (_dirty || _saving))
          Btn(_saving ? 'Saving…' : 'Save',
              small: true, disabled: _saving, onTap: _save),
        if (widget.onShowDiff != null)
          _HeaderButton('Diff', icon: 'split', onTap: widget.onShowDiff),
        if (text && _inline) _HeaderButton('Edit', icon: 'edit', onTap: _edit),
        IconBtn('download',
            tooltip: 'Download', onTap: _downloading ? null : _download),
      ],
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    unawaited(_loadMarks());
    setState(() => _loading = true);
    try {
      final f = await widget.client.readFile(widget.path);
      if (!mounted) return;
      _crlf = f.content.contains('\r\n');
      _initial = _normalized(f.content);
      _hash = f.hash;
      if (!f.binary) _controller.text = f.content;
      setState(() {
        _dirty = false;
        _f = f;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final f = _f;
    final editable = !_isMedia && !(f?.binary ?? false);
    void edit() => presentScreen(
          context,
          style: PanelStyle.dialog,
          dismissible: false,
          builder: (_, close) => EditorScreen(
              client: widget.client,
              path: widget.path,
              name: widget.name,
              onClose: close),
        ).then((_) => _load());
    final actions = <Widget>[
      IconBtn('download',
          tooltip: 'Download', onTap: _downloading ? null : _download),
      Builder(
        builder: (a) => IconBtn('more-horizontal',
            tooltip: 'More',
            onTap: () async {
              final pick = await showAppMenu<String>(context,
                  anchor: a,
                  below: true,
                  alignEnd: true,
                  items: [
                    appMenuItem(
                        value: 'copy', icon: 'copy', label: 'Copy path'),
                  ]);
              if (pick == 'copy' && context.mounted) {
                Clipboard.setData(ClipboardData(text: widget.path));
                toast(context, 'Path copied');
              }
            }),
      ),
      if (editable && kMobile) _EditPill(onTap: edit),
    ];
    // The Mac window bar has no file actions; other desktops get them from CardTabStrip.
    final barActions = !widget.embedded || kMacOS ? actions : const <Widget>[];
    final merged = !kMobile;
    final chrome = widget.embedded && !kMobile && widget.header;
    final meta = f == null || f.binary || _isMedia
        ? null
        : '${_controller.lineCount} lines · ${formatBytes(f.size)}${f.truncated ? ' · truncated' : ''}';
    return Scaffold(
      backgroundColor: widget.embedded && !kMobile
          ? Colors.transparent
          : AppColors.pageCanvas,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // The Mac window bar has no file actions; other desktops get them from CardTabStrip.
          if (!widget.embedded && kMobile)
            PreviewTopBar(
                client: widget.client,
                path: widget.path,
                name: widget.name,
                onClose: widget.onClose ?? () => Navigator.pop(context),
                onSave: _download,
                onEdit: editable ? edit : null),
          if (!widget.embedded && kMobile && meta != null)
            Padding(
              padding: EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, 8),
              child: Text(
                  [
                    if (languageForExt(_ext) != null) languageForExt(_ext)!,
                    meta,
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg3, tabular: true)),
            ),
          if (!widget.embedded && !kMobile)
            SnAppBar(
                title: widget.name,
                subtitle: meta == null
                    ? _homeShort(widget.path)
                    : '$meta · ${_homeShort(widget.path)}',
                onBack: widget.onClose ?? () => Navigator.pop(context),
                actions: merged ? const [] : actions),
          if (chrome) _desktopHeader(f),
          if (!chrome &&
              merged &&
              (_isMedia || f == null || f.binary) &&
              barActions.isNotEmpty)
            _FileToolbar(actions: barActions),
          if (_isPdf)
            Expanded(
                child: PdfPreview(
                    client: widget.client, path: widget.path, name: widget.name))
          else if (_isImage)
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(S.s16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(R.md),
                      child: Image(
                        image: ResizeImage.resizeIfNeeded(
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round()
                                .clamp(720, 2048),
                            null,
                            widget.client.imageProvider(widget.path)),
                        filterQuality: FilterQuality.low,
                        fit: BoxFit.contain,
                        frameBuilder: (ctx, child, frame, sync) =>
                            sync || frame != null
                                ? child
                                : Center(child: DelayedSpinner(size: 22)),
                        errorBuilder: (ctx, e, st) => EmptyState(
                            icon: 'alert-triangle',
                            title: "Can't load image",
                            body: '$e'),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else if (_isVideo && !kWindows)
            Expanded(child: _VideoView(url: widget.client.fileUrl(widget.path)))
          else if (_isVideo)
            Expanded(
              child: EmptyState(
                  icon: 'film',
                  title: 'No video preview on Windows',
                  body:
                      'Download the file and play it with your media player.'),
            )
          // Audio streams from the same `/fs/download` URL the video player uses
          // (the daemon serves Range requests), so playback starts without
          // fetching the whole file first.
          else if (_isAudio)
            Expanded(
              child: _AudioView(
                url: widget.client.fileUrl(widget.path),
                name: widget.name,
              ),
            )
          else if (_loading && kMobile)
            const Expanded(
                child: PreviewNotice(icon: 'file-text', title: 'Loading preview'))
          else if (_loading)
            Expanded(child: Center(child: DelayedSpinner(size: 22)))
          else if (_error != null && kMobile)
            Expanded(
                child: PreviewNotice(
                    icon: 'alert-triangle',
                    title: 'Could not load the preview',
                    line: 'The connection to the machine dropped. Try again.',
                    actions: [('Try again', _load, true)]))
          else if (_error != null)
            Expanded(
                child: EmptyState(
                    icon: 'alert-triangle',
                    title: 'Failed to load',
                    body: _error!))
          else if (f!.binary && kMobile)
            Expanded(
                child: PreviewNotice(
                    icon: notPreviewable(_ext).$1,
                    title: '${_ext.isEmpty ? 'File' : _ext.toUpperCase()} · ${formatBytes(f.size)}',
                    line: notPreviewable(_ext).$2,
                    actions: [
                  ('Open in…',
                      () => openPreviewFileIn(
                          context, widget.client, widget.path, widget.name),
                      true),
                  ('Share',
                      () => sharePreviewFile(
                          context, widget.client, widget.path, widget.name),
                      false),
                ]))
          else if (kMobile && f.content.isEmpty)
            const Expanded(
                child: PreviewNotice(
                    icon: 'file-text',
                    title: 'This file is empty',
                    line: 'There is nothing to show.'))
          else if (f.binary)
            Expanded(
              child: Center(
                child: EmptyState(
                  icon: 'file',
                  title: widget.name,
                  body: '${formatBytes(f.size)} · can\'t preview this file.',
                  action: Btn(
                    _downloading ? 'Downloading…' : 'Download',
                    icon: 'download',
                    disabled: _downloading,
                    onTap: _download,
                  ),
                ),
              ),
            )
          else ...[
            if (!chrome &&
                (widget.embedded || _isMarkdown || merged || _inline))
              _FileToolbar(
                leading: [
                  if (_isMarkdown) ...[
                    _modeTab('Preview', !_source,
                        () => setState(() => _source = false)),
                    SizedBox(width: S.s4),
                    _modeTab('Source', _source,
                        () => setState(() => _source = true)),
                  ],
                ],
                meta: widget.embedded ? meta : null,
                actions: [
                  if (_inline && (_dirty || _saving))
                    Padding(
                      padding: EdgeInsets.only(left: S.s8),
                      child: Btn(_saving ? 'Saving…' : 'Save',
                          small: true, disabled: _saving, onTap: _save),
                    ),
                  if (merged) ...barActions,
                ],
              ),
            if (_isMarkdown && !_source)
              Expanded(child: _markdownView(_controller.text))
            else
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                        _save,
                    const SingleActivator(LogicalKeyboardKey.keyS,
                        control: true): _save,
                  },
                  child: CodeEditor(
                    controller: _controller,
                    focusNode: _focus,
                    readOnly: !_inline,
                    wordWrap: false,
                    style: codeEditorStyle(widget.name),
                    indicatorBuilder: (context, editingController,
                        chunkController, notifier) {
                      return Row(children: [
                        DefaultCodeLineNumber(
                          controller: editingController,
                          notifier: notifier,
                          textStyle: kMobile
                              ? null
                              : codeMono(11.5,
                                  height: 1.5, color: AppColors.fg4),
                          focusedTextStyle: kMobile
                              ? null
                              : codeMono(11.5,
                                  height: 1.5, color: AppColors.fg3),
                        ),
                        if (!kMobile && _marks != null && !_marks!.isEmpty) ...[
                          SizedBox(width: S.s4),
                          _GutterMarks(notifier: notifier, marks: _marks!),
                        ],
                        DefaultCodeChunkIndicator(
                            width: 20,
                            controller: chunkController,
                            notifier: notifier),
                      ]);
                    },
                  ),
                ),
              ),
            if (!kMobile && (!_isMarkdown || _source))
              _FileStatusBar(
                  language: _languageLabel(widget.name),
                  crlf: _crlf,
                  controller: _controller,
                  marks: _marks),
          ],
        ]),
      ),
    );
  }
}

/// Streaming video player (chewie over video_player). Points at the daemon's
/// /fs/download URL, which serves a video content-type and Range requests — so
/// playback streams and seeks instead of downloading the whole file first.
class _VideoView extends StatefulWidget {
  final String url;
  const _VideoView({required this.url});
  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  VideoPlayerController? _vc;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    VideoPlayerController? vc;
    try {
      final created = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        // Mix with other audio rather than demanding exclusive audio focus — so
        // playback isn't silently blocked when something else holds focus (e.g.
        // an active phone call).
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        viewType: Platform.isAndroid
            ? VideoViewType.platformView
            : VideoViewType.textureView,
      );
      vc = created;
      // Surface a runtime playback error (decode/source failure) instead of a
      // dead play button — video_player reports these on the value, not as a throw.
      created.addListener(_onValue);
      await created.initialize();
      if (!mounted) {
        created.removeListener(_onValue);
        created.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: created,
        autoPlay: true, // a tapped video should just start
        looping: false,
        allowFullScreen: true,
        aspectRatio: created.value.aspectRatio == 0
            ? 16 / 9
            : created.value.aspectRatio,
        errorBuilder: (ctx, msg) => EmptyState(
            icon: 'alert-triangle', title: "Can't play video", body: msg),
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.accent,
          handleColor: AppColors.accent,
          bufferedColor: AppColors.surface3,
          backgroundColor: AppColors.surface2,
        ),
      );
      setState(() {
        _vc = created;
        _chewie = chewie;
      });
    } catch (e) {
      final failed = vc;
      if (failed != null) {
        failed.removeListener(_onValue);
        failed.dispose();
      }
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onValue() {
    final vc = _vc;
    if (vc != null && vc.value.hasError && _error == null && mounted) {
      setState(() => _error = vc.value.errorDescription ?? 'playback error');
    }
  }

  @override
  void dispose() {
    _vc?.removeListener(_onValue);
    _chewie?.dispose();
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (_error != null) {
      return EmptyState(
          icon: 'alert-triangle', title: "Can't play video", body: _error!);
    }
    final ch = _chewie;
    if (ch == null) {
      return Center(child: DelayedSpinner(size: 22));
    }
    // Chewie sizes the video from its own aspectRatio; letterbox on black.
    return ColoredBox(color: Colors.black, child: Chewie(controller: ch));
  }
}

/// Streaming audio player for a single file.
///
/// Deliberately its own surface rather than reusing the video player: there is
/// no picture to letterbox, so the whole pane is a transport — title, scrubber,
/// elapsed/total, play. Reuses `audioplayers`, which the composer already uses
/// for voice notes, so no new dependency.
class _AudioView extends StatefulWidget {
  final String url;
  final String name;
  const _AudioView({required this.url, required this.name});
  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  bool _ready = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      // `setSourceUrl` primes the source without starting playback, so the pane
      // shows total time before the user hits play. Loading in `initState` also
      // means a bad URL surfaces an error here rather than on first tap.
      await _player.setSourceUrl(widget.url);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  static String _clock(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (_error != null) {
      return EmptyState(
          icon: 'alert-triangle', title: "Can't play audio", body: _error!);
    }
    final total = _duration.inMilliseconds;
    final value = total <= 0
        ? 0.0
        : (_position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
    return Center(
      child: Padding(
        padding: EdgeInsets.all(S.s24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: AppIcon('music', size: 30, color: AppColors.fg3),
          ),
          SizedBox(height: S.s16),
          Text(widget.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: sans(kMobile ? 14 : 13,
                  weight: W.label, color: AppColors.fg1)),
          SizedBox(height: S.of(18)),
          // Scrubber. Seek is only offered once a duration is known, so an
          // unseekable source cannot produce a dead control.
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surface3,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accentBg,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              onChanged: total <= 0
                  ? null
                  : (v) => setState(() {
                        _position = Duration(milliseconds: (total * v).round());
                      }),
              onChangeEnd: total <= 0
                  ? null
                  : (v) =>
                      _player.seek(Duration(milliseconds: (total * v).round())),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_clock(_position), style: mono(10, color: AppColors.fg3)),
                Text(_clock(_duration), style: mono(10, color: AppColors.fg3)),
              ],
            ),
          ),
          SizedBox(height: S.of(10)),
          if (!_ready && _error == null)
            // Not `const`: `AppColors.fg3` is a theme GETTER, not a compile-time
            // constant, so it cannot appear in a const expression.
            Spinner(size: 22, color: AppColors.fg3)
          else
            IconBtn(_playing ? 'pause' : 'play',
                size: 44,
                iconSize: 22,
                tooltip: _playing ? 'Pause' : 'Play',
                onTap: _toggle),
        ]),
      ),
    );
  }
}

Future<String?> downloadRemoteFileWithCancel(
  BuildContext context,
  DaemonClient client, {
  required String path,
  required String name,
}) {
  return downloadRemoteFile(context, client, path: path, name: name);
}

/// Download a remote daemon path to the device. Used by the file viewer and by
/// agent `present_file` cards in chat. Returns a short status message, or null
/// when a modal/notification already covered the outcome.
Future<String?> downloadRemoteFile(
  BuildContext context,
  DaemonClient client, {
  required String path,
  required String name,
  bool Function()? isCancelled,
}) async {
  var cancelled = false;
  final progressId = await notifyDownloadStarted(
    name,
    onCancel: () => cancelled = true,
  );
  final tempDir = await getTemporaryDirectory();
  final tempFile = File(
      '${tempDir.path}/snippet-download-${DateTime.now().microsecondsSinceEpoch}-$name');
  try {
    await client.downloadToFile(
      path,
      tempFile,
      onProgress: (received, total) {
        if (total != null && total > 0) {
          final percent = ((received * 100) ~/ total).clamp(0, 100);
          notifyDownloadProgress(progressId, name, percent);
        } else {
          notifyDownloadProgress(progressId, name, null, received: received);
        }
      },
      isCancelled: () => cancelled || (isCancelled?.call() ?? false),
    );

    if (kMobile) {
      final supportFile =
          File('${(await getApplicationSupportDirectory()).path}/$name');
      await supportFile.parent.create(recursive: true);
      await tempFile.copy(supportFile.path);
      Future<String?> shareIt() async {
        final res = await SharePlus.instance
            .share(ShareParams(files: [XFile(supportFile.path, name: name)]));
        return res.status == ShareResultStatus.success ? 'Saved $name' : null;
      }

      if (Platform.isAndroid) {
        var saved = false;
        try {
          await MediaStore.ensureInitialized();
          MediaStore.appFolder = 'Snippet';
          final info = await MediaStore().saveFile(
            tempFilePath: tempFile.path,
            dirType: DirType.download,
            dirName: DirName.download,
            relativePath: FilePath.root,
          );
          saved = info != null;
        } catch (_) {
          saved = false;
        }
        if (saved) {
          await notifyDownload(name, supportFile.path, id: progressId);
          if (context.mounted) {
            await _downloadDoneSheetFor(context, name, supportFile.path);
          }
          return null;
        }
        await notifyDownloadFailure(
            progressId, name, 'Could not save to Downloads; sharing instead.');
        return shareIt();
      }
      await notifyDownload(name, supportFile.path, id: progressId);
      return shareIt();
    }

    final saved = await saveLocalFile(
        fileName: name, bytes: await tempFile.readAsBytes());
    if (saved == null) return null;
    await notifyDownload(name, saved, id: progressId);
    return 'Downloaded $name';
  } on DownloadCancelled {
    await notifyDownloadCancelled(progressId);
    return 'Download cancelled.';
  } catch (e) {
    await notifyDownloadFailure(progressId, name, e);
    rethrow;
  } finally {
    unregisterDownloadCancel(progressId);
    try {
      if (await tempFile.exists()) await tempFile.delete();
    } catch (_) {}
  }
}

Future<void> _downloadDoneSheetFor(
    BuildContext context, String name, String path) async {
  void shareFile() {
    SharePlus.instance.share(ShareParams(files: [XFile(path, name: name)]));
  }

  final action = await showAppSheet<String>(context,
      title: 'Saved to Downloads',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: sans(13, height: 1.4, color: AppColors.fg2)),
          SizedBox(height: S.s16),
          Btn('Open',
              icon: 'file',
              full: true,
              onTap: () => Navigator.pop(context, 'open')),
          SizedBox(height: S.s8),
          Btn('Share',
              icon: 'upload',
              variant: BtnVariant.secondary,
              full: true,
              onTap: () => Navigator.pop(context, 'share')),
          SizedBox(height: S.s4),
        ],
      ));
  if (action == 'open') {
    final opened = await openLocalFile(path);
    if (!opened) shareFile();
  } else if (action == 'share') {
    shareFile();
  }
}

/// Which new-file lines a unified diff added or changed, plus the totals.
class DiffMarks {
  const DiffMarks(
      {this.added = const {},
      this.changed = const {},
      this.add = 0,
      this.del = 0});
  final Set<int> added; // 0-based line indexes
  final Set<int> changed;
  final int add;
  final int del;
  bool get isEmpty => add == 0 && del == 0;

  static final _hunk = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)');

  factory DiffMarks.parse(String patch) {
    final added = <int>{}, changed = <int>{};
    var add = 0, del = 0, line = 0, inHunk = false;
    var run = <int>[];
    var runDel = 0;
    void flush() {
      if (run.isNotEmpty) (runDel > 0 ? changed : added).addAll(run);
      run = [];
      runDel = 0;
    }

    for (final l in patch.split('\n')) {
      final m = _hunk.firstMatch(l);
      if (m != null) {
        flush();
        inHunk = true;
        line = int.parse(m.group(1)!) - 1;
        continue;
      }
      if (!inHunk || l.isEmpty) continue;
      switch (l[0]) {
        case '+':
          run.add(line++);
          add++;
        case '-':
          runDel++;
          del++;
        case ' ':
          flush();
          line++;
      }
    }
    flush();
    return DiffMarks(added: added, changed: changed, add: add, del: del);
  }
}

String _languageLabel(String name) {
  final d = name.lastIndexOf('.');
  final ext = d >= 0 ? name.substring(d + 1).toLowerCase() : '';
  return switch (ext) {
    'dart' => 'Dart',
    'rs' => 'Rust',
    'ts' || 'tsx' => 'TypeScript',
    'js' || 'jsx' || 'mjs' => 'JavaScript',
    'py' => 'Python',
    'md' || 'markdown' || 'mdx' => 'Markdown',
    'json' => 'JSON',
    'yaml' || 'yml' => 'YAML',
    'toml' => 'TOML',
    'html' => 'HTML',
    'css' => 'CSS',
    'sh' || 'zsh' || 'bash' => 'Shell',
    'kt' => 'Kotlin',
    'swift' => 'Swift',
    'go' => 'Go',
    'java' => 'Java',
    'c' || 'h' => 'C',
    'cpp' || 'cc' || 'hpp' => 'C++',
    'sql' => 'SQL',
    '' => 'Plain text',
    _ => ext.toUpperCase(),
  };
}

/// Green and amber bars beside changed lines, in the line-number column.
/// A render object because the notifier fires during layout, where a
/// ValueListenableBuilder cannot rebuild.
class _GutterMarks extends LeafRenderObjectWidget {
  const _GutterMarks({required this.notifier, required this.marks});
  final CodeIndicatorValueNotifier notifier;
  final DiffMarks marks;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MarksRender(notifier, marks, AppColors.ok, AppColors.run);

  @override
  void updateRenderObject(BuildContext context, _MarksRender r) => r
    ..notifier = notifier
    ..marks = marks
    ..ok = AppColors.ok
    ..run = AppColors.run;
}

class _MarksRender extends RenderBox {
  _MarksRender(this._notifier, this._marks, this._ok, this._run);
  CodeIndicatorValueNotifier _notifier;
  DiffMarks _marks;
  Color _ok, _run;

  set notifier(CodeIndicatorValueNotifier v) {
    if (v == _notifier) return;
    _notifier.removeListener(markNeedsPaint);
    _notifier = v;
    if (attached) _notifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set marks(DiffMarks v) {
    _marks = v;
    markNeedsPaint();
  }

  set ok(Color v) {
    _ok = v;
    markNeedsPaint();
  }

  set run(Color v) {
    _run = v;
    markNeedsPaint();
  }

  @override
  void detach() {
    _notifier.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _notifier.addListener(markNeedsPaint);
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints c) =>
      Size(3, c.hasBoundedHeight ? c.maxHeight : 0);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final p in _notifier.value?.paragraphs ?? const []) {
      final c = _marks.added.contains(p.index)
          ? _ok
          : _marks.changed.contains(p.index)
              ? _run
              : null;
      if (c == null) continue;
      context.canvas.drawRect(
          Rect.fromLTWH(
              offset.dx, offset.dy + p.offset.dy, 3, p.paragraph.height),
          Paint()..color = c);
    }
  }
}

/// A ghost button the size of the mockup's `.btn.sm.ghost`.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton(this.label, {this.icon, this.onTap});
  final String label;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.of(6)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(6)),
          onTap: onTap,
          child: Container(
            height: PaneRow.pill,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.tint1,
              border: Border.all(color: AppColors.paneLine, width: AppColors.hairline),
              borderRadius: BorderRadius.circular(PaneRow.radius),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                AppIcon(icon!, size: 13, color: AppColors.fg2),
                const SizedBox(width: 6),
              ],
              Text(label, style: sans(12, color: AppColors.fg2)),
            ]),
          ),
        ),
      );
}

/// Breadcrumb segments for a file path: home as ~, and anything between the
/// root crumb and the last two folders folded into '…' unless [expanded].
List<String> fileCrumbs(String path, {bool expanded = false}) {
  var parts = path.split('/').where((s) => s.isNotEmpty).toList();
  // Paths come from the daemon's machine, so match its home by shape.
  if (parts.length >= 2 && (parts[0] == 'home' || parts[0] == 'Users')) {
    parts = ['~', ...parts.sublist(2)];
  } else if (parts.isNotEmpty && parts[0] == 'root') {
    parts = ['~', ...parts.sublist(1)];
  }
  if (expanded || parts.length <= 1) return parts;
  // Keep the name and up to two folders above it, stopping at an id-like one.
  final tail = <String>[parts.last];
  for (var i = parts.length - 2; i > 0 && tail.length < 3; i--) {
    if (_idLike(parts[i])) break;
    tail.insert(0, parts[i]);
  }
  final head = parts.length - tail.length;
  if (head <= 0) return parts;
  if (head == 1) return [parts.first, ...tail];
  return [parts.first, '…', ...tail];
}

bool _idLike(String s) =>
    s.length > 24 ||
    s.startsWith('-') ||
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-').hasMatch(s);

/// Breadcrumb, Modified chip and actions above an embedded file.
class _FileHeaderBar extends StatefulWidget {
  const _FileHeaderBar(
      {required this.path,
      required this.modified,
      this.leading = const [],
      this.actions = const []});
  final String path;
  final bool modified;
  final List<Widget> leading;
  final List<Widget> actions;

  @override
  State<_FileHeaderBar> createState() => _FileHeaderBarState();
}

class _FileHeaderBarState extends State<_FileHeaderBar> {
  String get path => widget.path;
  bool get modified => widget.modified;
  List<Widget> get leading => widget.leading;
  List<Widget> get actions => widget.actions;

  @override
  Widget build(BuildContext context) {
    // Header line: the file name only; the full path sits in the tooltip.
    final name = path.split('/').where((p) => p.isNotEmpty).lastOrNull ?? path;
    return Container(
      height: PaneRow.height,
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.paneLine, width: AppColors.hairline)),
      ),
      child: Row(children: [
        ...leading,
        Expanded(
          child: Row(children: [
            Flexible(
              child: Tooltip(
                message: path,
                waitDuration: const Duration(milliseconds: 500),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(PaneRow.label,
                        weight: W.label,
                        color: Color.lerp(AppColors.fg1, AppColors.fg2, 0.3))),
              ),
            ),
            if (modified) ...[
              const SizedBox(width: 8),
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: PaneRow.plate,
                    borderRadius: BorderRadius.circular(PaneRow.radius)),
                child: Text('Modified', style: sans(11, color: AppColors.fg3)),
              ),
            ],
          ]),
        ),
        for (final a in actions) ...[const SizedBox(width: 6), a],
      ]),
    );
  }
}

/// Language, encoding, line count, change totals and cursor position.
class _FileStatusBar extends StatelessWidget {
  const _FileStatusBar(
      {required this.language,
      required this.crlf,
      required this.controller,
      this.marks});
  final String language;
  final bool crlf;
  final CodeLineEditingController controller;
  final DiffMarks? marks;

  @override
  Widget build(BuildContext context) {
    final t = sans(12, color: AppColors.fg4);
    return ListenableBuilder(
      listenable: controller,
      builder: (_, __) {
        final sel = controller.selection;
        final m = marks;
        return Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.paneLine, width: AppColors.hairline))),
          child: Row(children: [
            Text(language, style: t),
            const SizedBox(width: 16),
            Text('UTF-8', style: t),
            const SizedBox(width: 16),
            Text(crlf ? 'CRLF' : 'LF', style: t),
            const SizedBox(width: 16),
            Text('${controller.lineCount} lines', style: t),
            const Spacer(),
            if (m != null && !m.isEmpty) ...[
              Text('+${m.add}', style: t.copyWith(color: AppColors.ok)),
              const SizedBox(width: 4),
              Text('−${m.del}', style: t.copyWith(color: AppColors.danger)),
              Text(' vs HEAD', style: t),
              const SizedBox(width: 16),
            ],
            Text('Ln ${sel.extentIndex + 1}, Col ${sel.extentOffset + 1}',
                style: t),
          ]),
        );
      },
    );
  }
}
