import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../file_actions.dart';
import '../file_icons.dart';
import '../glass.dart';
import '../media_views.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// What the preview needs to know about one composer attachment.
class PreviewAttachment {
  const PreviewAttachment({
    required this.name,
    this.isImage = false,
    this.isAudio = false,
    this.localPath,
    this.pastedText,
    this.imageProvider,
  });

  final String name;
  final bool isImage;
  final bool isAudio;
  final String? localPath;
  final String? pastedText;

  /// Stands in for the local file, e.g. the uploaded copy of a restored draft.
  final ImageProvider? imageProvider;

  MediaKind get kind => pastedText != null
      ? MediaKind.text
      : isAudio
          ? MediaKind.audio
          : isImage
              ? MediaKind.image
              : mediaKindOf(name);

  bool get isPasted => pastedText != null;
  bool get hasFile => localPath != null && File(localPath!).existsSync();

  ImageProvider? get image =>
      hasFile ? FileImage(File(localPath!)) : imageProvider;
}

typedef PreviewAction = void Function(PreviewAttachment a);
typedef PreviewTextAction = void Function(PreviewAttachment a, String text);

/// Open the preview for [attachments][[initialIndex]]: a draggable sheet on
/// phones, a centred panel on desktop. Images swipe (phone) or arrow-key
/// (desktop) between each other. Edits to pasted text are saved on any close.
Future<void> showAttachmentPreview(
  BuildContext context,
  List<PreviewAttachment> attachments,
  int initialIndex, {
  PreviewAction? onRemove,
  PreviewTextAction? onEditText,
  PreviewTextAction? onInsertText,
}) async {
  if (attachments.isEmpty) return;
  final current = attachments[initialIndex.clamp(0, attachments.length - 1)];
  final group = current.kind == MediaKind.image
      ? [
          for (final a in attachments)
            if (a.kind == MediaKind.image) a
        ]
      : [current];
  final session = _Session(group, group.indexOf(current));
  final calm = reduceMotion(context);
  if (kMobile) {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: false,
      enableDrag: false,
      sheetAnimationStyle: calm
          ? AnimationStyle(
              duration: Duration.zero, reverseDuration: Duration.zero)
          : sheetMotion,
      builder: (_) => _PhoneSheet(
        session: session,
        onRemove: onRemove,
        onInsert: onInsertText,
      ),
    );
  } else {
    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Close preview',
      barrierColor: AppColors.glassScrim,
      transitionDuration: calm ? Motion.quick : Motion.open,
      pageBuilder: (_, __, ___) => _DesktopPanel(
        session: session,
        onRemove: onRemove,
        onInsert: onInsertText,
      ),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Motion.exit);
        return FadeTransition(
          opacity: curved,
          child: calm
              ? child
              : SlideTransition(
                  position:
                      Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                          .animate(curved),
                  child: child),
        );
      },
    );
  }
  if (onEditText != null) {
    for (final entry in session.texts.entries) {
      if (entry.value != entry.key.pastedText &&
          !session.consumed.contains(entry.key)) {
        onEditText(entry.key, entry.value);
      }
    }
  }
}

class _Session {
  _Session(this.items, this.index);
  final List<PreviewAttachment> items;
  int index;
  final texts = <PreviewAttachment, String>{};
  final consumed = <PreviewAttachment>{};
}

class _PhoneSheet extends StatefulWidget {
  const _PhoneSheet({required this.session, this.onRemove, this.onInsert});
  final _Session session;
  final PreviewAction? onRemove;
  final PreviewTextAction? onInsert;

  @override
  State<_PhoneSheet> createState() => _PhoneSheetState();
}

class _PhoneSheetState extends State<_PhoneSheet> {
  bool _full = false;
  double? _drag;

  void _end(double velocity, double height, double screen, double full) {
    final collapsed = screen * 0.6;
    var wantFull = _full;
    if (velocity > 700) {
      if (_full) {
        wantFull = false;
      } else {
        Navigator.of(context).pop();
        return;
      }
    } else if (velocity < -700) {
      wantFull = true;
    } else if (height < collapsed * 0.75) {
      Navigator.of(context).pop();
      return;
    } else {
      wantFull = height > (collapsed + full) / 2;
    }
    setState(() {
      _full = wantFull;
      _drag = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final screen = media.size.height;
    final full = screen - media.padding.top - S.s8;
    final base = _full ? full : screen * 0.6;
    var height = (_drag ?? base).clamp(120.0, full);
    if (keyboard > 0) {
      height = height.clamp(120.0, screen - keyboard - media.padding.top);
    }
    final calm = reduceMotion(context);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedContainer(
            duration: _drag != null || calm ? Duration.zero : Motion.base,
            curve: Motion.exit,
            height: height,
            child: ClipRRect(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
              child: ColoredBox(
                color: AppColors.raised,
                child: _PreviewContent(
                  session: widget.session,
                  onRemove: widget.onRemove,
                  onInsert: widget.onInsert,
                  bottomInset: keyboard > 0 ? 0 : media.padding.bottom,
                  wrapHeader: (header) => GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragUpdate: (d) =>
                        setState(() => _drag = (_drag ?? base) - d.delta.dy),
                    onVerticalDragEnd: (d) => _end(
                        d.velocity.pixelsPerSecond.dy,
                        _drag ?? base,
                        screen,
                        full),
                    onTap: () => setState(() => _full = !_full),
                    child: header,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({required this.session, this.onRemove, this.onInsert});
  final _Session session;
  final PreviewAction? onRemove;
  final PreviewTextAction? onInsert;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.s24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: h * 0.7),
          child: Glass(
            radius: const BorderRadius.all(Radius.circular(R.lg)),
            border: false,
            tint: AppColors.windowBg,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: _PreviewContent(
                  session: session,
                  onRemove: onRemove,
                  onInsert: onInsert,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta {
  int? bytes;
  ui.Size? dims;
  Duration? duration;
}

class _PreviewContent extends StatefulWidget {
  const _PreviewContent({
    required this.session,
    this.onRemove,
    this.onInsert,
    this.wrapHeader,
    this.bottomInset = 0,
  });

  final _Session session;
  final PreviewAction? onRemove;
  final PreviewTextAction? onInsert;
  final Widget Function(Widget header)? wrapHeader;
  final double bottomInset;

  @override
  State<_PreviewContent> createState() => _PreviewContentState();
}

class _PreviewContentState extends State<_PreviewContent> {
  late final PageController _pages =
      PageController(initialPage: widget.session.index);
  final _meta = <PreviewAttachment, _Meta>{};
  final _controllers = <PreviewAttachment, TextEditingController>{};
  bool _zoomed = false;

  _Session get s => widget.session;
  bool get _sheet => widget.wrapHeader != null;
  PreviewAttachment get _cur => s.items[s.index];
  _Meta _metaOf(PreviewAttachment a) => _meta.putIfAbsent(a, _Meta.new);

  @override
  void initState() {
    super.initState();
    for (final a in s.items) {
      unawaited(_loadSize(a));
    }
  }

  Future<void> _loadSize(PreviewAttachment a) async {
    final m = _metaOf(a);
    if (a.pastedText != null) {
      m.bytes = utf8.encode(a.pastedText!).length;
    } else if (a.hasFile) {
      m.bytes = await File(a.localPath!).length();
    }
    if (mounted) setState(() {});
  }

  TextEditingController _controllerFor(PreviewAttachment a) =>
      _controllers.putIfAbsent(a, () {
        final c = TextEditingController(text: a.pastedText ?? '');
        s.texts[a] = c.text;
        return c;
      });

  @override
  void dispose() {
    _pages.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _remove() {
    final a = _cur;
    s.consumed.add(a);
    widget.onRemove?.call(a);
    if (s.items.length == 1) {
      _close();
      return;
    }
    setState(() {
      s.items.remove(a);
      s.index = s.index.clamp(0, s.items.length - 1);
      _zoomed = false;
    });
    _pages.jumpToPage(s.index);
  }

  void _insert() {
    final a = _cur;
    s.consumed.add(a);
    widget.onInsert?.call(a, _controllerFor(a).text);
    _close();
  }

  void _step(int by) {
    final next = s.index + by;
    if (next < 0 || next >= s.items.length) return;
    _pages.animateToPage(next,
        duration: reduceMotion(context) ? Duration.zero : Motion.base,
        curve: Motion.exit);
  }

  String _kindLabel(PreviewAttachment a) => a.isPasted
      ? 'Pasted text'
      : switch (a.kind) {
          MediaKind.image => 'Image',
          MediaKind.video => 'Video',
          MediaKind.audio => 'Audio',
          MediaKind.pdf => 'PDF',
          MediaKind.archive => 'Archive',
          MediaKind.code => 'Code',
          MediaKind.text => 'Text file',
          MediaKind.other => 'File',
        };

  static int _lines(String t) =>
      t.isEmpty ? 0 : '\n'.allMatches(t.trimRight()).length + 1;

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _clock(Duration d) => d.inHours > 0
      ? '${d.inHours}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}'
      : '${d.inMinutes}:${_two(d.inSeconds % 60)}';

  String _metaLine() {
    final a = _cur;
    final m = _metaOf(a);
    final parts = <String>[if (!a.isPasted) _kindLabel(a)];
    if (a.isPasted) {
      final n = _lines(s.texts[a] ?? a.pastedText ?? '');
      parts.add('$n ${n == 1 ? 'line' : 'lines'}');
    }
    if (m.bytes != null) parts.add(formatBytes(m.bytes));
    if (m.dims != null) {
      parts.add('${m.dims!.width.round()} × ${m.dims!.height.round()}');
    }
    if (m.duration != null) parts.add(_clock(m.duration!));
    if (s.items.length > 1) parts.add('${s.index + 1} of ${s.items.length}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final a = _cur;
    final ctl = a.isPasted ? _controllerFor(a) : null;
    final desktop = !_sheet;
    final iconSize = kMobile ? 44.0 : 28.0;
    final pasted = ctl != null;
    Widget roundBtn(String icon, String tip, VoidCallback onTap) =>
        DecoratedBox(
          decoration:
              BoxDecoration(color: AppColors.tint1, shape: BoxShape.circle),
          child: IconBtn(icon,
              tooltip: tip, size: iconSize, iconSize: 16, onTap: onTap),
        );
    Widget header = Padding(
      padding: EdgeInsets.fromLTRB(S.s16, desktop ? S.s12 : S.s4,
          pasted ? S.s12 : S.s8, desktop ? S.s12 : S.s8),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pasted ? 'Pasted text' : (a.isAudio ? 'Voice note' : a.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pasted
                      ? sans(15, weight: W.label, color: AppColors.fg1)
                      : TS.rowTitle()),
              Text(_metaLine(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.meta()),
            ],
          ),
        ),
        if (widget.onRemove != null) ...[
          pasted
              ? roundBtn('trash', 'Remove', _remove)
              : IconBtn('trash',
                  tooltip: 'Remove',
                  size: iconSize,
                  iconSize: 16,
                  onTap: _remove),
          if (pasted && desktop) const SizedBox(width: S.s4),
        ],
        if (!(pasted && _sheet))
          pasted
              ? roundBtn('x', 'Close', _close)
              : IconBtn('x',
                  tooltip: 'Close',
                  size: iconSize,
                  iconSize: 16,
                  onTap: _close),
      ]),
    );
    if (_sheet) {
      header =
          widget.wrapHeader!(Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetGrabHandle(),
        header,
      ]));
    }

    final body = switch (a.kind) {
      _ when a.isPasted => _textBody(a, ctl!),
      MediaKind.image => _imageBody(),
      MediaKind.video when a.hasFile => _VideoBody(
          key: ValueKey(a.localPath),
          attachment: a,
          onDuration: (d) => setState(() => _metaOf(a).duration = d)),
      MediaKind.text || MediaKind.code when a.hasFile => _FileText(a),
      _ => _FileCard(a),
    };

    final footer = ctl == null ? null : _footer(ctl);
    final content = Column(mainAxisSize: MainAxisSize.max, children: [
      header,
      if (!pasted) Container(height: 1, color: AppColors.border),
      Expanded(child: body),
      if (footer != null) footer,
      if (_sheet && footer == null) SizedBox(height: widget.bottomInset),
    ]);

    final keys = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): _close,
      if (a.kind == MediaKind.image && s.items.length > 1) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
      },
    };
    final shrink = desktop &&
        ctl == null &&
        a.kind != MediaKind.image &&
        a.kind != MediaKind.video;
    return CallbackShortcuts(
      bindings: keys,
      child: Focus(
        autofocus: ctl == null,
        child: shrink
            ? SizedBox(height: 360, child: content)
            : SizedBox(height: desktop ? 640 : double.infinity, child: content),
      ),
    );
  }

  Widget _textBody(PreviewAttachment a, TextEditingController c) => Container(
        margin: const EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s8),
        padding: const EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s12),
        decoration: BoxDecoration(
            color: AppColors.tint1,
            borderRadius: BorderRadius.circular(R.card)),
        child: TextField(
          controller: c,
          autofocus: !_sheet,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          cursorColor: AppColors.accent,
          onChanged: (t) => setState(() => s.texts[a] = t),
          style: TS.code(AppColors.fg1),
          decoration: InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            hintText: 'Empty. Done removes it.',
            hintStyle: TS.code(AppColors.fg4),
          ),
        ),
      );

  Widget _footer(TextEditingController c) {
    final insert = Btn('Insert as text',
        variant: BtnVariant.surface,
        small: !kMobile,
        full: kMobile,
        onTap: _insert);
    final done = Btn('Done', small: !kMobile, full: kMobile, onTap: _close);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          S.s16, S.s4, S.s16, kMobile ? S.s12 + widget.bottomInset : S.s16),
      child: kMobile
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: insert),
                const SizedBox(width: S.s8),
                Expanded(child: done),
              ]),
            ])
          : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              insert,
              const SizedBox(width: S.s8),
              done,
            ]),
    );
  }

  Widget _imageBody() {
    final multi = s.items.length > 1;
    final pager = PageView.builder(
      key: ValueKey(s.items.length),
      controller: _pages,
      physics: _zoomed || !multi
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      itemCount: s.items.length,
      onPageChanged: (i) => setState(() {
        s.index = i;
        _zoomed = false;
      }),
      itemBuilder: (_, i) {
        final item = s.items[i];
        return _ZoomImage(
          key: ValueKey(item),
          provider: item.image,
          onSize: (sz) {
            final m = _metaOf(item);
            if (m.dims == sz) return;
            m.dims = sz;
            if (mounted) setState(() {});
          },
          onZoom: (z) {
            if (z != _zoomed && item == _cur) setState(() => _zoomed = z);
          },
        );
      },
    );
    if (!multi || kMobile) return ColoredBox(color: AppColors.bg, child: pager);
    Widget arrow(String icon, String tip, int by, bool on, Alignment at) =>
        Align(
          alignment: at,
          child: Padding(
            padding: const EdgeInsets.all(S.s8),
            child: on
                ? DecoratedBox(
                    decoration: BoxDecoration(
                        color: AppColors.surface2.withValues(alpha: 0.85),
                        shape: BoxShape.circle),
                    child: IconBtn(icon,
                        tooltip: tip,
                        size: 32,
                        iconSize: 16,
                        onTap: () => _step(by)))
                : const SizedBox(width: 32, height: 32),
          ),
        );
    return ColoredBox(
      color: AppColors.bg,
      child: Stack(children: [
        pager,
        arrow('chevron-left', 'Previous image', -1, s.index > 0,
            Alignment.centerLeft),
        arrow('chevron-right', 'Next image', 1, s.index < s.items.length - 1,
            Alignment.centerRight),
      ]),
    );
  }
}

class _ZoomImage extends StatefulWidget {
  const _ZoomImage(
      {super.key, this.provider, required this.onSize, required this.onZoom});
  final ImageProvider? provider;
  final ValueChanged<ui.Size> onSize;
  final ValueChanged<bool> onZoom;

  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage> {
  final _tc = TransformationController();
  Offset _tap = Offset.zero;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    final size =
        ui.Size(info.image.width.toDouble(), info.image.height.toDouble());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSize(size);
    });
  });

  @override
  void initState() {
    super.initState();
    _tc.addListener(() => widget.onZoom(_tc.value.getMaxScaleOnAxis() > 1.02));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream?.removeListener(_listener);
    _stream = widget.provider?.resolve(createLocalImageConfiguration(context))
      ?..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _tc.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_tc.value.getMaxScaleOnAxis() > 1.02) {
      _tc.value = Matrix4.identity();
    } else {
      const z = 2.5;
      _tc.value = Matrix4.identity()
        ..translateByDouble(-_tap.dx * (z - 1), -_tap.dy * (z - 1), 0, 1)
        ..scaleByDouble(z, z, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    if (p == null) {
      return Center(child: AppIcon('image', size: 28, color: AppColors.fg4));
    }
    return GestureDetector(
      onDoubleTapDown: (d) => _tap = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: Image(
            image: p,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                AppIcon('image', size: 28, color: AppColors.fg4),
          ),
        ),
      ),
    );
  }
}

class _VideoBody extends StatefulWidget {
  const _VideoBody(
      {super.key, required this.attachment, required this.onDuration});
  final PreviewAttachment attachment;
  final ValueChanged<Duration> onDuration;

  @override
  State<_VideoBody> createState() => _VideoBodyState();
}

class _VideoBodyState extends State<_VideoBody> {
  VideoPlayerController? _vc;
  ChewieController? _chewie;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final vc = VideoPlayerController.file(
        File(widget.attachment.localPath!),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        viewType: Platform.isAndroid
            ? VideoViewType.platformView
            : VideoViewType.textureView,
      );
      await vc.initialize();
      if (!mounted) {
        await vc.dispose();
        return;
      }
      widget.onDuration(vc.value.duration);
      setState(() {
        _vc = vc;
        _chewie = ChewieController(
          videoPlayerController: vc,
          autoPlay: false,
          allowFullScreen: false,
          aspectRatio:
              vc.value.aspectRatio == 0 ? 16 / 9 : vc.value.aspectRatio,
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.accent,
            handleColor: AppColors.accent,
            bufferedColor: AppColors.surface3,
            backgroundColor: AppColors.surface2,
          ),
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _FileCard(widget.attachment,
          note: 'Playback is not available here.');
    }
    final ch = _chewie;
    if (ch == null) return Center(child: DelayedSpinner(size: 22));
    return ColoredBox(color: Colors.black, child: Chewie(controller: ch));
  }
}

class _FileText extends StatelessWidget {
  const _FileText(this.attachment);
  final PreviewAttachment attachment;

  Future<String> _read() async {
    final f = File(attachment.localPath!);
    final bytes = await f
        .openRead(0, 256 * 1024)
        .fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _read(),
        builder: (_, snap) {
          if (!snap.hasData) return Center(child: DelayedSpinner(size: 20));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(S.s16),
            child: SelectableText(snap.data!, style: TS.code(AppColors.fg1)),
          );
        },
      );
}

class _FileCard extends StatelessWidget {
  const _FileCard(this.attachment, {this.note});
  final PreviewAttachment attachment;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final (icon, tint) = a.isAudio
        ? (fileIconFor('x.mp3').$1, AppColors.accent)
        : fileIconFor(a.name);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.s24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.lg)),
            child: Icon(icon, size: 28, color: tint),
          ),
          const SizedBox(height: S.s12),
          Text(
              note ??
                  (a.kind == MediaKind.pdf
                      ? 'PDF preview is not available here.'
                      : 'No preview for this file type.'),
              textAlign: TextAlign.center,
              style: TS.meta()),
          if (a.hasFile) ...[
            const SizedBox(height: S.s16),
            Btn('Open',
                variant: BtnVariant.surface,
                small: !kMobile,
                icon: 'external-link',
                onTap: () => unawaited(openLocalFile(a.localPath!))),
          ],
        ]),
      ),
    );
  }
}
