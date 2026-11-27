import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'chat/desktop_rich_cards.dart';
import 'gesture_physics.dart';
import 'platform.dart';
import 'preview_canvas.dart' show showPreviewCanvas;
import 'screens/file_viewer.dart';
import 'theme.dart';
import 'tool_sheet.dart';
import 'widgets.dart';
import 'tap_detector.dart';

/// The daemon a subtree talks to, so media deep in the transcript (tool
/// panels, message attachments) can load files without threading a client
/// through every row.
class DaemonScope extends InheritedWidget {
  final DaemonClient client;

  /// Opens a file in a tab (desktop), when the host has tabs.
  final void Function(String path, String name)? onOpenFile;

  /// The session's folder, for resolving relative file links in messages.
  final String? workspace;

  /// Shows a tool batch in the desktop side pane, when the host has one.
  final void Function(ValueListenable<ToolBatch> batch)? onOpenTools;
  const DaemonScope({
    super.key,
    required this.client,
    this.onOpenFile,
    this.onOpenTools,
    this.workspace,
    required super.child,
  });

  static DaemonClient? current;

  static DaemonClient? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DaemonScope>()?.client;

  static DaemonScope? scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DaemonScope>();

  @override
  bool updateShouldNotify(DaemonScope old) =>
      old.client != client ||
      old.onOpenFile != onOpenFile ||
      old.workspace != workspace ||
      old.onOpenTools != onOpenTools;
}

/// What a file is, for choosing its preview and icon.
enum MediaKind { image, audio, video, pdf, archive, code, text, other }

MediaKind mediaKindOf(String path) {
  final ext =
      path.split('.').length > 1 ? path.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'heic' ||
    'svg' =>
      MediaKind.image,
    'aac' ||
    'flac' ||
    'm4a' ||
    'mp3' ||
    'oga' ||
    'ogg' ||
    'opus' ||
    'wav' ||
    'webm' =>
      MediaKind.audio,
    'mp4' || 'mov' || 'mkv' || 'avi' || 'm4v' => MediaKind.video,
    'pdf' => MediaKind.pdf,
    'zip' ||
    'tar' ||
    'gz' ||
    'tgz' ||
    'bz2' ||
    'xz' ||
    '7z' ||
    'rar' =>
      MediaKind.archive,
    'rs' ||
    'dart' ||
    'ts' ||
    'tsx' ||
    'js' ||
    'jsx' ||
    'py' ||
    'go' ||
    'java' ||
    'kt' ||
    'swift' ||
    'c' ||
    'h' ||
    'cpp' ||
    'rb' ||
    'php' ||
    'sh' ||
    'json' ||
    'yaml' ||
    'yml' ||
    'toml' ||
    'html' ||
    'css' ||
    'sql' =>
      MediaKind.code,
    'txt' || 'md' || 'log' || 'csv' || 'rtf' => MediaKind.text,
    _ => MediaKind.other,
  };
}

String _iconFor(MediaKind kind) => switch (kind) {
      MediaKind.image => 'image',
      MediaKind.audio => 'music',
      MediaKind.video => 'film',
      MediaKind.pdf => 'pdf',
      MediaKind.archive => 'archive',
      MediaKind.code => 'file-code',
      MediaKind.text => 'file-text',
      MediaKind.other => 'file',
    };

String baseName(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// An attachment the user sent, parsed from the marker the client appends.
class SentAttachment {
  final String path;
  final MediaKind kind;
  const SentAttachment(this.path, this.kind);
}

final RegExp _markerRe =
    RegExp(r'\[attached (image|file)(?: —[^\]/]*)?:?\s*(/[^\]]+)\]');

List<SentAttachment> parseSentAttachments(String text) => [
      for (final m in _markerRe.allMatches(text))
        SentAttachment(
          m.group(2)!.trim(),
          m.group(1) == 'image'
              ? MediaKind.image
              : mediaKindOf(m.group(2)!.trim()),
        ),
    ];

/// Open a file the way the platform wants: on desktop on the preview canvas,
/// on phones images in the full-screen viewer and everything else in the file
/// viewer.
void openMedia(BuildContext context, DaemonClient client, String path,
    {List<String>? gallery}) {
  if (!kMobile) {
    // Images float on the preview canvas, with their neighbours as a gallery.
    if (mediaKindOf(path) == MediaKind.image) {
      final images = [
        for (final p in gallery ?? const <String>[])
          if (mediaKindOf(p) == MediaKind.image) p
      ];
      final all = images.contains(path) ? images : [path];
      showPreviewCanvas(context,
          client: client, images: all, initial: all.indexOf(path));
      return;
    }
    presentFileOnDesktop(context,
        client: client, path: path, name: baseName(path));
    return;
  }
  if (mediaKindOf(path) == MediaKind.image) {
    showImageViewer(context, client: client, path: path, gallery: gallery);
    return;
  }
  pushFileViewerRoute(context,
      client: client, path: path, name: baseName(path));
}

/// A rounded image thumbnail with a quiet placeholder while it loads and a
/// clear state when it can't. Tapping opens the image viewer.
class ImageThumb extends StatelessWidget {
  final DaemonClient client;
  final String path;
  final double width;
  final double height;
  final BoxFit fit;

  /// Decode width in physical pixels; defaults to the displayed width.
  final int? cacheWidth;

  final List<String>? gallery;
  const ImageThumb({
    super.key,
    required this.client,
    required this.path,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.gallery,
  });

  @override
  Widget build(BuildContext context) => _ImageThumbContent(
        client: client,
        path: path,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        gallery: gallery,
      );
}

class _ImageThumbContent extends StatefulWidget {
  final DaemonClient client;
  final String path;
  final double width;
  final double height;
  final BoxFit fit;
  final int? cacheWidth;
  final List<String>? gallery;

  const _ImageThumbContent({
    required this.client,
    required this.path,
    required this.width,
    required this.height,
    required this.fit,
    this.cacheWidth,
    this.gallery,
  });

  @override
  State<_ImageThumbContent> createState() => _ImageThumbContentState();
}

class _ImageThumbContentState extends State<_ImageThumbContent> {
  int _retry = 0;
  bool _hover = false;

  Widget _loading() {
    if (kMobile) return LoadingBlock(color: AppColors.surface2);
    return ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Spinner(size: 14, color: AppColors.fg3),
          if (widget.height >= 52) ...[
            const SizedBox(height: 6),
            Text('Loading', style: sans(11, color: AppColors.fg3)),
          ],
        ]),
      ),
    );
  }

  Future<void> _retryLoad() async {
    final base = widget.client.imageProvider(widget.path);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final resized = ResizeImage.resizeIfNeeded(
      widget.cacheWidth ?? (widget.width * dpr).round(),
      null,
      base,
    );
    await resized.evict();
    await base.evict();
    if (mounted) setState(() => _retry++);
  }

  Widget _error() {
    if (kMobile) {
      return ColoredBox(
        color: AppColors.surface2,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('image', size: 16, color: AppColors.fg3),
              const SizedBox(width: 4),
              AppIcon('x', size: 14, color: AppColors.fg2),
            ]),
            if (widget.height >= 72) ...[
              const SizedBox(height: 6),
              Text('Could not load',
                  textAlign: TextAlign.center,
                  style: sans(13, color: AppColors.fg2)),
            ],
            if (widget.height >= 116) ...[
              const SizedBox(height: 6),
              DesktopRichButton('Retry',
                  variant: DesktopRichButtonVariant.secondary,
                  parentSurface: 2,
                  onTap: _retryLoad),
            ],
          ]),
        ),
      );
    }
    return ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('image', size: 14, color: AppColors.fg2),
              const SizedBox(width: 4),
              AppIcon('x', size: 12, color: AppColors.fg2),
            ]),
            if (widget.height >= 64) ...[
              const SizedBox(height: 4),
              Text('Could not load',
                  textAlign: TextAlign.center,
                  style: sans(11.5, color: AppColors.fg2)),
            ],
            if (widget.height >= 104) ...[
              const SizedBox(height: 6),
              DesktopRichButton('Retry',
                  variant: DesktopRichButtonVariant.secondary,
                  parentSurface: 2,
                  onTap: _retryLoad),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final provider = ResizeImage.resizeIfNeeded(
      widget.cacheWidth ?? (widget.width * dpr).round(),
      null,
      widget.client.imageProvider(widget.path),
    );
    final image = Image(
      key: ValueKey('${widget.path}:$_retry'),
      image: provider,
      fit: widget.fit,
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, sync) =>
          sync || frame != null ? child : _loading(),
      errorBuilder: (_, __, ___) => _error(),
    );
    final showAffordance = kMobile
        ? widget.width >= 120 && widget.height >= 72
        : _hover && widget.width >= 112 && widget.height >= 48;
    return Semantics(
      image: true,
      label: baseName(widget.path),
      button: true,
      child: TapDetector(
        onTap: () => openMedia(context, widget.client, widget.path,
            gallery: widget.gallery),
        child: MouseRegion(
          onEnter: !kMobile ? (_) => setState(() => _hover = true) : null,
          onExit: !kMobile ? (_) => setState(() => _hover = false) : null,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kMobile ? 8 : 6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              image,
              Positioned(
                right: 8,
                bottom: 8,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showAffordance ? 1 : 0,
                    duration: Motion.quick,
                    child: Container(
                      width: kMobile ? 111 : null,
                      height: kMobile ? 36 : 28,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(kMobile ? 22 : 14),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AppIcon('eye', size: kMobile ? 14 : 13, color: AppColors.fg1),
                        const SizedBox(width: 5),
                        Text(kMobile ? 'Tap to view' : 'Click to view',
                            style: sans(kMobile ? 13 : 12,
                                weight: FontWeight.w500,
                                height: 1,
                                color: AppColors.fg1)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Images laid out for a message: one image large, several as a tidy grid.
class ImageGallery extends StatelessWidget {
  final DaemonClient client;
  final List<String> paths;
  final double maxWidth;
  const ImageGallery({
    super.key,
    required this.client,
    required this.paths,
    this.maxWidth = 280,
  });

  @override
  Widget build(BuildContext context) {
    if (paths.length == 1) {
      return SingleImage(client: client, path: paths.first);
    }
    if (kMobile) {
      return LayoutBuilder(builder: (_, c) {
        final w = (c.maxWidth.isFinite ? c.maxWidth : maxWidth)
            .clamp(0.0, 361.0)
            .toDouble();
        Widget thumb(String path, double tw, double th, {int overflow = 0}) {
          final tile = ImageThumb(
              client: client, path: path, width: tw, height: th, gallery: paths);
          if (overflow <= 0) return tile;
          return TapDetector(
            onTap: () => openMedia(context, client, path, gallery: paths),
            child: SizedBox(
              width: tw,
              height: th,
              child: Stack(fit: StackFit.expand, children: [
                tile,
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: const Color(0xFF121211).withValues(alpha: 0.74),
                    child: Center(
                      child: Text('+$overflow',
                          style: sans(17,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                    ),
                  ),
                ),
              ]),
            ),
          );
        }

        const gap = 5.0;
        if (paths.length == 2) {
          final tw = ((w - gap) / 2).clamp(0.0, 178.5).toDouble();
          return Row(children: [
            thumb(paths[0], tw, 150),
            const SizedBox(width: gap),
            thumb(paths[1], tw, 150),
          ]);
        }
        if (paths.length == 3) {
          final bigW = w * (214 / 361);
          final sideW = w - bigW - 4;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            thumb(paths[0], bigW, 150),
            const SizedBox(width: 4),
            Column(children: [
              thumb(paths[1], sideW, 73),
              const SizedBox(height: 4),
              thumb(paths[2], sideW, 73),
            ]),
          ]);
        }
        final tw = ((w - gap) / 2).clamp(0.0, 178.5).toDouble();
        final shown = paths.take(4).toList();
        Widget gridTile(int i) => thumb(shown[i], tw, 73,
            overflow: i == 3 && paths.length > 4 ? paths.length - 4 : 0);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            gridTile(0),
            const SizedBox(width: gap),
            gridTile(1),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            gridTile(2),
            const SizedBox(width: gap),
            gridTile(3),
          ]),
        ]);
      });
    }
    final width = maxWidth.clamp(220.0, 420.0);
    Widget tile(String path) => LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : width / 2;
          final h = c.maxHeight.isFinite ? c.maxHeight : 124.0;
          return ImageThumb(
            client: client,
            path: path,
            width: w,
            height: h,
            gallery: paths,
          );
        });
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopImageGalleryGrid(
            tiles: [for (final path in paths) tile(path)],
            overflowCount: paths.length > 4 ? paths.length - 4 : 0,
            onOverflowTap: paths.length > 4
                ? () => openMedia(context, client, paths[4], gallery: paths)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${paths.length} images',
                style: sans(11, height: 1, color: AppColors.fg3)),
          ),
        ],
      ),
    );
  }
}

/// A file as a compact card: its kind, its name and a type label. Tapping opens it.
/// One image on its own, at its own aspect ratio: a fixed crop box chopped
/// screenshots and tall photos alike. Sized to fit the bounds once the
/// image's dimensions are known; a neutral box holds the space until then.
class SingleImage extends StatefulWidget {
  final DaemonClient client;
  final String path;
  final double? maxWidth;
  final double? maxHeight;
  final List<String>? gallery;
  const SingleImage({
    super.key,
    required this.client,
    required this.path,
    this.maxWidth,
    this.maxHeight,
    this.gallery,
  });

  @override
  State<SingleImage> createState() => _SingleImageState();
}

class _SingleImageState extends State<SingleImage> {
  double get _maxHeight => widget.maxHeight ?? (kMobile ? 240.0 : 320.0);
  static const _minSide = 72.0;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(SingleImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.client != widget.client) {
      _size = null;
      _resolve();
    }
  }

  double get _maxWidth =>
      widget.maxWidth ??
      (MediaQuery.sizeOf(context).width - 32)
          .clamp(160.0, kMobile ? 361.0 : 420.0);

  // The same decode the thumb shows, so the image is fetched once.
  int get _cacheWidth =>
      (_maxWidth * MediaQuery.devicePixelRatioOf(context)).round();

  void _resolve() {
    final stream = ResizeImage.resizeIfNeeded(
            _cacheWidth, null, widget.client.imageProvider(widget.path))
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _unlisten();
    final listener = ImageStreamListener((info, _) {
      final size =
          Size(info.image.width.toDouble(), info.image.height.toDouble());
      info.dispose();
      if (mounted && size != _size) setState(() => _size = size);
    }, onError: (_, __) {});
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  void _unlisten() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = _maxWidth;
    final size = _size;
    final maxHeight =
        kMobile ? _maxHeight : math.min(_maxHeight, maxWidth * 0.7);
    var w = (kMobile ? 174.5 : 260.0).clamp(0.0, maxWidth);
    var h = kMobile ? 174.0 : math.min(180.0, maxHeight);
    if (size != null && size.width > 0 && size.height > 0) {
      final scale = [maxWidth / size.width, maxHeight / size.height, 1.0]
          .reduce((a, b) => a < b ? a : b);
      w = (size.width * scale).clamp(_minSide, maxWidth);
      h = (size.height * scale).clamp(_minSide, maxHeight);
    }
    final thumb = ImageThumb(
        client: widget.client,
        path: widget.path,
        width: w,
        height: h,
        fit: BoxFit.contain,
        cacheWidth: _cacheWidth,
        gallery: widget.gallery);
    return AnimatedSize(
      duration: Motion.quick,
      alignment: Alignment.topLeft,
      // The image speaks for itself; no filename caption under it.
      child: thumb,
    );
  }
}

class FileChip extends StatelessWidget {
  final DaemonClient? client;
  final String path;
  final String? name;
  final int? sizeBytes;
  final VoidCallback? onTap;
  final Widget? trailing;
  const FileChip({
    super.key,
    required this.path,
    this.client,
    this.name,
    this.sizeBytes,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final kind = mediaKindOf(path);
    final label = name ?? baseName(path);
    final tap = onTap ??
        (client == null ? null : () => openMedia(context, client!, path));
    if (!kMobile) {
      var bytes = sizeBytes;
      if (bytes == null) {
        try {
          final file = File(path);
          if (file.existsSync()) bytes = file.lengthSync();
        } catch (_) {}
      }
      return DesktopFileChip(
        icon: _iconFor(kind),
        name: label,
        sizeLabel: bytes == null ? '' : desktopFileSizeLabel(bytes),
        onTap: tap,
        trailing: trailing,
      );
    }
    var bytes = sizeBytes;
    if (bytes == null) {
      try {
        final file = File(path);
        if (file.existsSync()) bytes = file.lengthSync();
      } catch (_) {}
    }
    final size = bytes == null ? '' : desktopFileSizeLabel(bytes);
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 36,
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(_iconFor(kind), size: 14, color: AppColors.fg2),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13.5, height: 1, color: AppColors.fg1)),
            ),
            if (size.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(size,
                  maxLines: 1,
                  style: sans(12, height: 1, color: AppColors.fg2)),
            ],
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ]),
        ),
      ),
    );
  }
}

/// A voice note: play/pause, progress and time, with its transcript beneath.
/// The audio is only fetched when first played, so a long chat full of voice
/// notes costs nothing until one is opened.
class VoiceNote extends StatefulWidget {
  final DaemonClient client;
  final String path;
  final String? url;
  final Duration? duration;
  final Widget? transcript;

  /// Text colour of the bubble it sits in; controls and wave follow it.
  final Color? ink;
  const VoiceNote(
      {super.key,
      required this.client,
      this.path = '',
      this.url,
      this.duration,
      this.transcript,
      this.ink});

  @override
  State<VoiceNote> createState() => _VoiceNoteState();
}

/// One player for every voice note, so playback survives the transcript
/// rebuilding the card, and starting another note stops the last.
class VoicePlayback extends ChangeNotifier {
  VoicePlayback._();
  static final instance = VoicePlayback._();

  AudioPlayer? _player;
  String? source;
  bool playing = false;
  bool loading = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? failed;

  AudioPlayer _ensure() {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    p.onPlayerStateChanged.listen((s) {
      playing = s == PlayerState.playing;
      if (s == PlayerState.completed) position = Duration.zero;
      notifyListeners();
    });
    p.onPositionChanged.listen((d) {
      position = d;
      notifyListeners();
    });
    p.onDurationChanged.listen((d) {
      duration = d;
      notifyListeners();
    });
    return _player = p;
  }

  Future<void> toggle(String src) async {
    final p = _ensure();
    try {
      if (source == src && playing) {
        await p.pause();
      } else if (source == src && p.state == PlayerState.paused) {
        await p.resume();
      } else {
        await p.stop();
        source = src;
        failed = null;
        position = Duration.zero;
        duration = Duration.zero;
        loading = true;
        notifyListeners();
        await p.play(UrlSource(src));
      }
    } catch (_) {
      failed = src;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> seek(String src, double fraction) async {
    final p = _player;
    if (p == null || source != src || duration == Duration.zero) return;
    await p.seek(duration * fraction.clamp(0.0, 1.0));
  }
}

class _VoiceNoteState extends State<VoiceNote> {
  VoicePlayback get _pb => VoicePlayback.instance;

  String get _src {
    final u = widget.url;
    return (u != null && u.isNotEmpty) ? u : widget.client.fileUrl(widget.path);
  }

  bool get _mine => _pb.source == _src;
  bool get _playing => _mine && _pb.playing;
  bool get _loading => _mine && _pb.loading;
  Duration get _position => _mine ? _pb.position : Duration.zero;
  Duration get _duration {
    if (_mine && _pb.duration > Duration.zero) return _pb.duration;
    final d = widget.duration;
    return d != null && d > Duration.zero ? d : Duration.zero;
  }

  String? get _error =>
      _pb.failed == _src ? "Couldn't play this voice note" : null;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _pb.addListener(_changed);
  }

  @override
  void dispose() {
    _pb.removeListener(_changed);
    super.dispose();
  }

  Future<void> _toggle() => _pb.toggle(_src);

  Future<void> _seekTo(double fraction) => _pb.seek(_src, fraction);

  static String _clock(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _mobile(double progress) {
    final active = _playing || _position > Duration.zero;
    final time = _error ??
        (_duration == Duration.zero
            ? (active ? _clock(_position) : '--:--')
            : active && _position > Duration.zero
                ? '${_clock(_position)} / ${_clock(_duration)}'
                : _clock(_duration));
    return Container(
      width: double.infinity,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: _playing ? 'Pause voice note' : 'Play voice note',
          child: Material(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: _error == null ? _toggle : null,
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 44,
                height: 36,
                child: Center(
                  child: _loading
                      ? Spinner(size: 14, color: AppColors.fg1)
                      : Padding(
                          padding: EdgeInsets.only(left: _playing ? 0 : 1.5),
                          child: AppIcon(_playing ? 'pause' : 'play',
                              size: 14, color: AppColors.fg1),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_error != null) ...[
          Expanded(
            child: Text('Could not play voice note',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg2)),
          ),
          SizedBox(
            width: 55,
            child: DesktopRichButton('Retry',
                variant: DesktopRichButtonVariant.secondary,
                parentSurface: 1,
                onTap: _toggle),
          ),
          const SizedBox(width: 8),
        ] else ...[
          Expanded(
            child: LayoutBuilder(builder: (_, box) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seekTo(
                    (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                onHorizontalDragUpdate: (d) => _seekTo(
                    (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                child: SizedBox(
                  height: 42,
                  child: CustomPaint(
                    painter: _NoteWave(
                      seed: (widget.url ?? widget.path).hashCode,
                      progress: progress,
                      played: AppColors.fg1,
                      rest: AppColors.fg3,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 8),
          Text(time,
              maxLines: 1,
              style: sans(13, tabular: true, color: AppColors.fg2)),
          const SizedBox(width: 12),
        ],
      ]),
    );
  }


  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds;
    final progress =
        total <= 0 ? 0.0 : (_position.inMilliseconds / total).clamp(0.0, 1.0);
    if (!kMobile) {
      final active = _playing || _position > Duration.zero;
      final state = _error != null
          ? DesktopVoiceNoteState.failed
          : _loading
              ? DesktopVoiceNoteState.loading
              : _playing
                  ? DesktopVoiceNoteState.playing
                  : _position > Duration.zero
                      ? DesktopVoiceNoteState.paused
                      : DesktopVoiceNoteState.idle;
      final duration = _duration == Duration.zero
          ? (active ? _clock(_position) : '--:--')
          : _clock(active ? _position : _duration);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopVoiceNoteRow(
            durationLabel: duration,
            state: state,
            progress: progress,
            seed: (widget.url ?? widget.path).hashCode,
            onToggle: _toggle,
            onSeek: _seekTo,
            onRetry: _toggle,
          ),
          if (_error != null && widget.transcript != null) ...[
            SizedBox(height: S.s6),
            widget.transcript!,
          ],
        ],
      );
    }
    return _mobile(progress);
  }
}

class WaveBuffer {
  final List<double> samples = [];
  int total = 0;

  void add(double level) {
    samples.add(level);
    total++;
    if (samples.length > 180) samples.removeAt(0);
  }

  void clear() {
    samples.clear();
    total = 0;
  }
}

class LiveRecordingWave extends StatefulWidget {
  const LiveRecordingWave(
      {super.key,
      required this.buffer,
      this.live = true,
      this.progress,
      this.interval = const Duration(milliseconds: 120)});

  final WaveBuffer buffer;
  final bool live;
  final double? progress;
  final Duration interval;

  @override
  State<LiveRecordingWave> createState() => _LiveRecordingWaveState();
}

class _LiveRecordingWaveState extends State<LiveRecordingWave>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _phase = ValueNotifier<double>(1);
  int _seen = -1;
  Duration _stamp = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.live) _ticker.start();
  }

  @override
  void didUpdateWidget(LiveRecordingWave old) {
    super.didUpdateWidget(old);
    if (widget.live && !_ticker.isActive) {
      _seen = -1;
      _ticker.start();
    } else if (!widget.live && _ticker.isActive) {
      _ticker.stop();
      _phase.value = 1;
    }
  }

  void _tick(Duration elapsed) {
    final total = widget.buffer.total;
    if (total != _seen) {
      _seen = total;
      _stamp = elapsed;
    }
    _phase.value =
        ((elapsed - _stamp).inMicroseconds / widget.interval.inMicroseconds)
            .clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SmoothWave(widget.buffer, _phase,
              live: widget.live, progress: widget.progress),
        ),
      );
}

class _SmoothWave extends CustomPainter {
  _SmoothWave(this.buffer, this.phase, {required this.live, this.progress})
      : total = buffer.total,
        super(repaint: phase);

  final WaveBuffer buffer;
  final ValueNotifier<double> phase;
  final bool live;
  final double? progress;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 5.0;
    final samples = buffer.samples;
    if (samples.isEmpty || size.width <= 0) return;
    canvas.clipRect(Offset.zero & size);
    final f = live ? phase.value : 1.0;
    final eased = Curves.easeOutCubic.transform(f);
    final count = (size.width / step).ceil() + 1;
    final start = math.max(0, samples.length - count);
    final n = samples.length - start;
    final shift = (1 - eased) * step;
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final x = size.width - (n - 1 - i) * step - step / 2 + shift;
      if (x < -step) continue;
      var level = samples[start + i].clamp(0.06, 1.0);
      if (live && i == n - 1) level = 0.06 + (level - 0.06) * eased;
      final half = (size.height * 0.48 * level).clamp(1.5, size.height * 0.48);
      final played = progress == null || (i / n) <= progress!;
      paint.color = played ? AppColors.accent : AppColors.fg4;
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothWave old) =>
      old.total != total ||
      old.progress != progress ||
      old.live != live ||
      old.buffer != buffer;
}

/// A still waveform for a voice note that has no playback position yet.
class NoteWaveStrip extends StatelessWidget {
  const NoteWaveStrip({super.key, required this.seed, this.height = 22});

  final int seed;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _NoteWave(
              seed: seed,
              progress: 0,
              played: AppColors.accent,
              rest: AppColors.fg3),
        ),
      );
}

class _NoteWave extends CustomPainter {
  final int seed;
  final double progress;
  final Color played;
  final Color rest;
  const _NoteWave(
      {required this.seed,
      required this.progress,
      required this.played,
      required this.rest});

  @override
  void paint(Canvas canvas, Size size) {
    final bar = kMobile ? 2.0 : 3.0;
    const gap = 2.0;
    final count = ((size.width + gap) / (bar + gap)).floor();
    if (count <= 0) return;
    final rnd = math.Random(seed);
    final paint = Paint()
      ..strokeWidth = bar
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    var prev = 0.5;
    for (var i = 0; i < count; i++) {
      final t = i / count;
      final envelope = 0.45 + 0.55 * math.sin(math.pi * (0.05 + t * 0.9));
      prev = (prev * 0.35 + rnd.nextDouble() * 0.65).clamp(0.12, 1.0);
      final h = math.max(bar, (size.height - bar) * envelope * prev);
      final x = i * (bar + gap) + bar / 2;
      paint.color = t < progress ? played : rest;
      canvas.drawLine(Offset(x, mid - h / 2 + bar / 2),
          Offset(x, mid + h / 2 - bar / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_NoteWave old) =>
      old.progress != progress ||
      old.seed != seed ||
      old.played != played ||
      old.rest != rest;
}

/// Full-screen image viewer: black backdrop, pinch to zoom, tap or swipe down
/// to close.
Future<void> showImageViewer(
  BuildContext context, {
  required DaemonClient client,
  required String path,
  List<String>? gallery,
}) {
  final paths = gallery != null && gallery.contains(path) ? gallery : [path];
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: kMobile ? null : const Color(0xFF0E0E0D),
    transitionDuration: Motion.fast,
    reverseTransitionDuration: Motion.quick,
    pageBuilder: (_, __, ___) => _ImageViewer(
        client: client, paths: paths, initial: paths.indexOf(path)),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

class _ImageViewer extends StatefulWidget {
  final DaemonClient client;
  final List<String> paths;
  final int initial;
  const _ImageViewer(
      {required this.client, required this.paths, required this.initial});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _pages = PageController(initialPage: _index);
  late int _index = widget.initial;
  final Map<int, TransformationController> _zooms = {};
  late final AnimationController _dragC =
      AnimationController.unbounded(vsync: this)
        ..addListener(() => setState(() {}));
  double get _dragY => _dragC.value;
  bool _chrome = true;
  bool _busy = false;

  String get _path => widget.paths[_index];

  TransformationController _zoomFor(int i) =>
      _zooms.putIfAbsent(i, TransformationController.new);

  bool get _zoomed => _zoomFor(_index).value.getMaxScaleOnAxis() > 1.01;

  // A second finger means a pinch: drop the dismiss drag and the page swipe
  // so they leave the gesture arena before they can move the image.
  int _fingers = 0;
  bool get _locked => _zoomed || _fingers > 1;
  bool _wasZoomed = false;

  void _finger(int by) {
    final was = _fingers > 1;
    _fingers = (_fingers + by).clamp(0, 10);
    if (was == _fingers > 1) return;
    if (_fingers > 1 && _dragY != 0) springTo(_dragC, 0, 0);
    setState(() {});
  }

  @override
  void dispose() {
    _dragC.dispose();
    _pages.dispose();
    for (final z in _zooms.values) {
      z.dispose();
    }
    super.dispose();
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final name = baseName(_path);
      final bytes = await widget.client.downloadFile(_path);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/snippet-share-$name');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance
          .share(ShareParams(files: [XFile(file.path, name: name)]));
    } catch (_) {
      if (mounted) toast(context, "Couldn't share this image");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final msg = await downloadRemoteFile(context, widget.client,
          path: _path, name: baseName(_path));
      if (msg != null && mounted) toast(context, msg);
    } catch (_) {
      if (mounted) toast(context, "Couldn't save this image");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: _path));
    if (mounted) toast(context, 'Path copied');
  }

  Widget _page(int i, Size size, double dpr) {
    final zoom = _zoomFor(i);
    return InteractiveViewer(
      transformationController: zoom,
      minScale: 1,
      maxScale: 6,
      onInteractionUpdate: (_) {
        if (_zoomed != _wasZoomed) setState(() => _wasZoomed = _zoomed);
      },
      onInteractionEnd: (_) => setState(() => _wasZoomed = _zoomed),
      // At rest the image sits between the top bar and the home indicator.
      child: Padding(
        padding: kMobile
            ? EdgeInsets.fromLTRB(
                0,
                MediaQuery.viewPaddingOf(context).top + 56,
                0,
                MediaQuery.viewPaddingOf(context).bottom +
                    (widget.paths.length > 1 ? 72 : 16))
            : MediaQuery.viewPaddingOf(context),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kMobile ? R.of(10) : 0),
            child: Image(
              image: ResizeImage.resizeIfNeeded(
                (size.width * dpr).round().clamp(720, 2400),
                null,
                widget.client.imageProvider(widget.paths[i]),
              ),
              fit: BoxFit.contain,
              // The client fetch reports no progress, so wait on the first frame.
              frameBuilder: (_, child, frame, sync) => sync || frame != null
                  ? child
                  : Center(
                      child: Text('Loading image',
                          style: sans(13, color: _ink.withValues(alpha: 0.7)))),
              errorBuilder: (_, __, ___) => Text("Can't load this image",
                  style: sans(13, color: _ink.withValues(alpha: 0.7))),
            ),
          ),
        ),
      ),
    );
  }

  /// V1: the viewer keeps the app ground on the phone, so nothing flashes.
  Color get _ink => AppColors.fg1;

  void _toggleZoom() {
    final z = _zoomFor(_index);
    z.value = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()..scaleByDouble(2.0, 2.0, 1.0, 1.0));
    setState(() => _wasZoomed = _zoomed);
  }

  void _zoomBy(double factor) {
    final z = _zoomFor(_index);
    final scale = (z.value.getMaxScaleOnAxis() * factor).clamp(1.0, 6.0);
    z.value = Matrix4.identity()..scaleByDouble(scale, scale, 1.0, 1.0);
    setState(() => _wasZoomed = _zoomed);
  }

  void _fitZoom() {
    _zoomFor(_index).value = Matrix4.identity();
    setState(() => _wasZoomed = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fade = (1 - _dragY.abs() / (size.height * .5)).clamp(0.0, 1.0);
    final many = widget.paths.length > 1;
    final showChrome = _chrome && _dragY == 0;
    final stack = Stack(children: [
      Positioned.fill(
        child: Listener(
          onPointerDown: (_) => _finger(1),
          onPointerUp: (_) => _finger(-1),
          onPointerCancel: (_) => _finger(-1),
          child: GestureDetector(
            onTap: kMobile
                ? () => setState(() => _chrome = !_chrome)
                : () => Navigator.of(context).pop(),
            onDoubleTap: kMobile ? _toggleZoom : null,
            onVerticalDragStart: _locked ? null : (_) => _dragC.stop(),
            onVerticalDragUpdate:
                _locked ? null : (d) => _dragC.value += d.delta.dy,
            onVerticalDragEnd: _locked
                ? null
                : (d) {
                    final v = d.primaryVelocity ?? 0;
                    final dir = _dragY == 0 ? v.sign : _dragY.sign;
                    if (dragDismisses(
                        distance: _dragY.abs(),
                        velocity: v * dir,
                        distanceThreshold: 120,
                        velocityThreshold: 900)) {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                      springTo(_dragC, _dragY + dir * size.height * .5,
                          v * dir > 0 ? v : 0);
                    } else {
                      springTo(_dragC, 0, v);
                    }
                  },
            onVerticalDragCancel: _locked ? null : () => springTo(_dragC, 0, 0),
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.paths.length,
                physics: _locked
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (i) {
                  _zooms[_index]?.value = Matrix4.identity();
                  setState(() => _index = i);
                },
                itemBuilder: (_, i) => _page(i, size, dpr),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: !showChrome,
          child: AnimatedOpacity(
            opacity: showChrome ? 1 : 0,
            duration: Motion.quick,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, S.s8),
                child: Row(children: [
                  _bar('x', 'Close', () => Navigator.of(context).pop()),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(baseName(_path),
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: sans(kMobile ? 15 : 12.5,
                              height: 20 / (kMobile ? 15 : 12.5),
                              weight: W.label,
                              color: _ink)),
                    ),
                  ),
                  _bar('share', 'Share', _share),
                  Builder(
                      builder: (a) => _bar('more-horizontal', 'More', () async {
                            final pick = await showAppMenu<String>(
                              context,
                              anchor: a,
                              below: true,
                              alignEnd: true,
                              items: [
                                appMenuItem(
                                    value: 'save',
                                    icon: 'download',
                                    label: 'Save to device'),
                                appMenuItem(
                                    value: 'copy',
                                    icon: 'copy',
                                    label: 'Copy path'),
                              ],
                            );
                            if (pick == 'save') _save();
                            if (pick == 'copy') _copyPath();
                          })),
                ]),
              ),
            ),
          ),
        ),
      ),
      if (!kMobile)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !showChrome,
            child: AnimatedOpacity(
              opacity: showChrome ? 1 : 0,
              duration: Motion.quick,
              child: Container(
                height: 40,
                color: AppColors.surface2,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  Text(
                    many ? '${_index + 1} of ${widget.paths.length}' : '',
                    style: sans(11.5, color: AppColors.fg3),
                  ),
                  const Spacer(),
                  DesktopCardIconButton('minus',
                      tooltip: 'Zoom out', onTap: () => _zoomBy(1 / 1.25)),
                  DesktopCardIconButton('plus',
                      tooltip: 'Zoom in', onTap: () => _zoomBy(1.25)),
                  DesktopCardIconButton('wrap',
                      tooltip: 'Fit to window', onTap: _fitZoom),
                  DesktopCardIconButton('share',
                      tooltip: 'Share', onTap: _share),
                ]),
              ),
            ),
          ),
        ),
      if (many && kMobile)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !showChrome,
            child: AnimatedOpacity(
              opacity: showChrome ? 1 : 0,
              duration: Motion.quick,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: S.s12),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < widget.paths.length; i++)
                          GestureDetector(
                            onTap: () => _pages.animateToPage(i,
                                duration: Motion.quick, curve: Curves.easeOut),
                            child: Container(
                              width: 44,
                              height: 44,
                              margin: EdgeInsets.symmetric(horizontal: S.s4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(R.of(8)),
                                border: Border.all(
                                    color:
                                        i == _index ? _ink : Colors.transparent,
                                    width: 2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(R.of(6)),
                                child: Image(
                                  image: ResizeImage.resizeIfNeeded(
                                      120,
                                      null,
                                      widget.client
                                          .imageProvider(widget.paths[i])),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
    if (!kMobile) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E0E0D).withValues(alpha: fade),
        body: stack,
      );
    }
    // Full screen straight away on the app ground (V1); the gesture hint
    // is spoken, never printed.
    return Scaffold(
      backgroundColor: AppColors.bg.withValues(alpha: fade),
      body: Semantics(
        hint: 'Pinch or double-tap to zoom, swipe down to close',
        child: stack,
      ),
    );
  }

  Widget _bar(String icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _busy ? null : onTap,
          child: SizedBox(
              width: kMobile ? 48 : 28,
              height: kMobile ? 48 : 28,
              child: Center(
                  child: AppIcon(icon, size: kMobile ? 22 : 14, color: _ink))),
        ),
      );
}

/// Pasted text as it travels in a message: inline, so the agent reads it
/// directly, between markers the transcript collapses into a card.
String pastedTextBlock(String text) {
  final body = text.trimRight();
  final lines = '\n'.allMatches(body).length + 1;
  return '[pasted text — $lines lines]\n$body\n[/pasted text]';
}

final RegExp _pastedRe = RegExp(
  r'\[pasted text — \d+ lines?\]\n([\s\S]*?)\n\[/pasted text\]',
);

/// The pasted blocks in [text], and the text with them removed.
(List<String>, String) splitPastedBlocks(String text) {
  final blocks = [for (final m in _pastedRe.allMatches(text)) m.group(1)!];
  return (blocks, text.replaceAll(_pastedRe, '').trim());
}

/// A pasted block in the transcript: collapsed to a few lines with its size,
/// expandable to the full text, with copy.
class PastedTextCard extends StatefulWidget {
  final String text;
  const PastedTextCard({super.key, required this.text});

  @override
  State<PastedTextCard> createState() => _PastedTextCardState();
}

class _PastedTextCardState extends State<PastedTextCard> {
  bool _open = false;

  Widget _phone() {
    final lines = widget.text.split('\n');
    final lineCount = lines.length;
    final collapsed = lines.take(3).join('\n');
    final expandedLines = lines.take(9).toList();
    final bodyText = _open ? expandedLines.join('\n') : collapsed;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  AppIcon('file-text', size: 14, color: AppColors.fg2),
                  const SizedBox(width: 8),
                  Text('Pasted text',
                      style: sans(15,
                          weight: FontWeight.w500, color: AppColors.fg1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('$lineCount lines',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg3)),
                  ),
                  AppIcon(_open ? 'chevron-up' : 'chevron-down',
                      size: 14, color: AppColors.fg2),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              height: _open ? 178 : 70,
              padding: const EdgeInsets.all(8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                physics: _open
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: SelectableText(
                  bodyText,
                  style: codeMono(12, height: 18 / 12, color: AppColors.fg2),
                ),
              ),
            ),
          ),
          if (_open)
            SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      'Showing ${expandedLines.length} of $lineCount lines',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3),
                    ),
                  ),
                  DesktopRichButton('Collapse',
                      variant: DesktopRichButtonVariant.secondary,
                      parentSurface: 1,
                      onTap: () => setState(() => _open = false)),
                ]),
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kMobile) return _phone();
    return DesktopPastedTextCard(text: widget.text);
  }
}
