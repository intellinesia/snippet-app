import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'media_views.dart' show baseName;
import 'platform.dart';
import 'screens/file_viewer.dart' show downloadRemoteFile;
import 'tap_detector.dart';
import 'theme.dart';
import 'toast.dart';
import 'widgets.dart' show AppIcon;

/// Desktop preview canvas: the app dims and blurs behind a dot-grid ground,
/// and the content floats on it. Images get a frame with wheel zoom, drag to
/// pan and arrows through a gallery; anything else floats as a sheet.
Future<void> showPreviewCanvas(
  BuildContext context, {
  DaemonClient? client,
  List<String> images = const [],
  int initial = 0,
  Widget Function(BuildContext context, VoidCallback close)? sheet,
  double sheetWidth = 920,
}) {
  assert(images.isNotEmpty || sheet != null);
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, __, ___) => _PreviewCanvas(
      client: client,
      images: images,
      initial: initial.clamp(0, images.isEmpty ? 0 : images.length - 1),
      sheet: sheet,
      sheetWidth: sheetWidth,
    ),
    transitionsBuilder: (_, a, __, child) {
      final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
            scale: Tween(begin: 0.98, end: 1.0).animate(curve), child: child),
      );
    },
  ));
}

class _PreviewCanvas extends StatefulWidget {
  const _PreviewCanvas({
    required this.client,
    required this.images,
    required this.initial,
    required this.sheet,
    required this.sheetWidth,
  });
  final DaemonClient? client;
  final List<String> images;
  final int initial;
  final Widget Function(BuildContext, VoidCallback)? sheet;
  final double sheetWidth;

  @override
  State<_PreviewCanvas> createState() => _PreviewCanvasState();
}

class _PreviewCanvasState extends State<_PreviewCanvas> {
  late int _index = widget.initial;
  final _zoom = TransformationController();
  final _focus = FocusNode();
  bool _chrome = true;

  bool get _isImage => widget.sheet == null && widget.images.isNotEmpty;
  bool get _many => widget.images.length > 1;
  String get _path => widget.images[_index];
  double get _scale => _zoom.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
  }

  void _onZoom() => setState(() {});

  @override
  void dispose() {
    _zoom.removeListener(_onZoom);
    _zoom.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _go(int by) {
    if (!_many) return;
    setState(() {
      _index = (_index + by) % widget.images.length;
      if (_index < 0) _index += widget.images.length;
      _zoom.value = Matrix4.identity();
    });
  }

  /// Scales about the viewport centre so the middle of the image stays put.
  void _zoomTo(double target) {
    final size = MediaQuery.sizeOf(context);
    final s = target.clamp(0.25, 8.0);
    final c = Offset(size.width / 2, size.height / 2);
    final scene = _zoom.toScene(c);
    _zoom.value = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
  }

  void _fit() => _zoom.value = Matrix4.identity();

  Future<void> _download() async {
    final client = widget.client;
    if (client == null) return;
    try {
      final msg = await downloadRemoteFile(context, client,
          path: _path, name: baseName(_path));
      if (msg != null && mounted) toast(context, msg);
    } catch (_) {
      if (mounted) toast(context, "Couldn't save this image");
    }
  }

  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: _path));
    if (mounted) toast(context, 'Path copied');
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      _close();
    } else if (_isImage && k == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
    } else if (_isImage && k == LogicalKeyboardKey.arrowRight) {
      _go(1);
    } else if (_isImage &&
        (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add)) {
      _zoomTo(_scale * 1.25);
    } else if (_isImage && k == LogicalKeyboardKey.minus) {
      _zoomTo(_scale / 1.25);
    } else if (_isImage && k == LogicalKeyboardKey.digit0) {
      _fit();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: Material(
        type: MaterialType.transparency,
        child: MouseRegion(
          onHover: _isImage && !_chrome
              ? (_) => setState(() => _chrome = true)
              : null,
          child: Stack(children: [
            Positioned.fill(child: _ground()),
            Positioned.fill(child: _isImage ? _stage() : _sheet()),
            if (_isImage) ..._imageChrome(),
          ]),
        ),
      ),
    );
  }

  /// Clean dimmed backdrop behind the image. A click on it closes.
  Widget _ground() => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: ColoredBox(color: AppColors.bg.withValues(alpha: 0.90)),
          ),
        ),
      );

  Widget _stage() {
    final client = widget.client!;
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return InteractiveViewer(
      transformationController: _zoom,
      minScale: 0.25,
      maxScale: 8,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      child: TapDetector(
        // Empty canvas around the frame still closes.
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 64, 56, 36),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              onDoubleTap: () => _scale > 1.01 ? _fit() : _zoomTo(2),
              child: AnimatedSwitcher(
                duration: Motion.fast,
                child: _Frame(
                  key: ValueKey(_path),
                  child: Image(
                    image: ResizeImage.resizeIfNeeded(
                      (size.width * dpr).round().clamp(900, 3200),
                      null,
                      client.imageProvider(_path),
                    ),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    frameBuilder: (_, child, frame, sync) =>
                        sync || frame != null
                            ? child
                            : SizedBox(
                                width: 320,
                                height: 220,
                                child: Center(
                                    child: Text('Loading',
                                        style: sans(12.5,
                                            color: AppColors.fg3)))),
                    errorBuilder: (_, __, ___) => SizedBox(
                        width: 320,
                        height: 220,
                        child: Center(
                            child: Text("Can't load this image",
                                style: sans(12.5, color: AppColors.fg3)))),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheet() => LayoutBuilder(
        builder: (context, box) => TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: box.maxWidth < 900 ? 24 : 56, vertical: 36),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.sheetWidth),
                child: GestureDetector(
                  onTap: () {},
                  child: _Frame(
                    fill: AppColors.bg,
                    radius: 14,
                    child: SizedBox.expand(child: widget.sheet!(context, _close)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  List<Widget> _imageChrome() {
    final name = baseName(_path);
    return [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: Container(
          height: 44,
          padding: EdgeInsets.fromLTRB(kMacOS ? 84 : 16, 0, 12, 0),
          decoration: BoxDecoration(
            color: AppColors.surface1.withValues(alpha: 0.94),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            AppIcon('image', size: 14, color: AppColors.fg3),
            const SizedBox(width: 8),
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5, weight: W.label, color: AppColors.fg1)),
                ),
                if (_many) ...[
                  const SizedBox(width: 10),
                  Text('${_index + 1} of ${widget.images.length}',
                      style: sans(11.5, color: AppColors.fg3, tabular: true)),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            _Tool('minus',
                tooltip: 'Zoom out', onTap: () => _zoomTo(_scale / 1.25)),
            SizedBox(
              width: 46,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _fit,
                child: Text('${(_scale * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: sans(11.5, color: AppColors.fg2, tabular: true)),
              ),
            ),
            _Tool('plus',
                tooltip: 'Zoom in', onTap: () => _zoomTo(_scale * 1.25)),
            _Tool('expand', tooltip: 'Fit (0)', onTap: _fit),
            const _Rule(),
            _Tool('copy', tooltip: 'Copy path', onTap: _copyPath),
            _Tool('download', tooltip: 'Download', onTap: _download),
            const _Rule(),
            _Tool('x', tooltip: 'Close (Esc)', onTap: _close),
          ]),
        ),
      ),
      if (_many) ...[
        Positioned(
          left: 16,
          top: 44,
          bottom: 0,
          child: Center(
              child: _Round('chevron-left',
                  tooltip: 'Previous', onTap: () => _go(-1))),
        ),
        Positioned(
          right: 16,
          top: 44,
          bottom: 0,
          child: Center(
              child: _Round('chevron-right',
                  tooltip: 'Next', onTap: () => _go(1))),
        ),
      ],
    ];
  }
}

/// The floating frame: hairline edge and a long soft shadow.
class _Frame extends StatelessWidget {
  const _Frame({super.key, required this.child, this.fill, this.radius = 10});
  final Widget child;
  final Color? fill;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
              color: AppColors.fg1.withValues(alpha: 0.08),
              width: AppColors.hairline),
          boxShadow: const [
            BoxShadow(
                color: Color(0x73000000), blurRadius: 48, offset: Offset(0, 18)),
            BoxShadow(
                color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(radius), child: child),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.children, this.padding = 12});
  final List<Widget> children;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: padding),
        decoration: BoxDecoration(
          color: AppColors.surface2.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: AppColors.fg1.withValues(alpha: 0.07),
              width: AppColors.hairline),
          boxShadow: const [
            BoxShadow(
                color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
}

class _Tool extends StatefulWidget {
  const _Tool(this.icon, {required this.tooltip, required this.onTap});
  final String icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_Tool> createState() => _ToolState();
}

class _ToolState extends State<_Tool> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Motion.fast,
              width: 30,
              height: 28,
              decoration: BoxDecoration(
                color: _hover ? AppColors.hoverPlate : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                  child: AppIcon(widget.icon,
                      size: 14,
                      color: _hover ? AppColors.fg1 : AppColors.fg2)),
            ),
          ),
        ),
      );
}

class _Round extends StatefulWidget {
  const _Round(this.icon, {required this.tooltip, required this.onTap});
  final String icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_Round> createState() => _RoundState();
}

class _RoundState extends State<_Round> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Motion.fast,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _hover
                    ? AppColors.surface3
                    : AppColors.surface2.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.fg1.withValues(alpha: 0.07),
                    width: AppColors.hairline),
              ),
              child: Center(
                  child: AppIcon(widget.icon,
                      size: 15,
                      color: _hover ? AppColors.fg1 : AppColors.fg2)),
            ),
          ),
        ),
      );
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Container(
        width: AppColors.hairline,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: AppColors.fg1.withValues(alpha: 0.12),
      );
}

class _DotGrid extends CustomPainter {
  const _DotGrid(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 22.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGrid old) => old.color != color;
}
