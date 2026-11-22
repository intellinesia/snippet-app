import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../media_views.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

const _typeNames = {
  'png': 'PNG image',
  'jpg': 'JPEG image',
  'jpeg': 'JPEG image',
  'gif': 'GIF image',
  'webp': 'WebP image',
  'heic': 'HEIC image',
  'svg': 'SVG image',
  'pdf': 'PDF',
  'txt': 'Text',
  'md': 'Markdown',
  'json': 'JSON',
  'zip': 'ZIP archive',
  'csv': 'CSV',
};

String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Type and size line (e.g. PNG image, 1.2 MB) for the hover card; the size is left out when unknown.
String attachmentMetaLine(
    {required String name, int? sizeBytes, String? pastedText}) {
  if (pastedText != null) {
    final lines = pastedText.isEmpty ? 0 : pastedText.split('\n').length;
    return 'Text · $lines ${lines == 1 ? 'line' : 'lines'}';
  }
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  final type = _typeNames[ext] ??
      (ext.isEmpty || ext.length > 6 ? 'File' : '${ext.toUpperCase()} file');
  return sizeBytes == null ? type : '$type · ${_humanSize(sizeBytes)}';
}

/// Desktop-only hover card for a composer attachment tile.
class AttachmentHoverPreview extends StatefulWidget {
  const AttachmentHoverPreview({
    super.key,
    required this.name,
    required this.isImage,
    required this.child,
    this.localPath,
    this.sizeBytes,
    this.pastedText,
    this.imageProvider,
  });

  final String name;
  final bool isImage;
  final String? localPath;
  final int? sizeBytes;
  final String? pastedText;
  final ImageProvider? imageProvider;
  final Widget child;

  @override
  State<AttachmentHoverPreview> createState() => _AttachmentHoverPreviewState();
}

class _AttachmentHoverPreviewState extends State<AttachmentHoverPreview>
    with SingleTickerProviderStateMixin {
  static const _width = 320.0;
  static const _estHeight = 340.0;

  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final AnimationController _anim;
  Timer? _timer;
  ScrollPosition? _scroll;
  bool _below = false;
  double _dx = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: Motion.fast);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll?.removeListener(_hideNow);
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_hideNow);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll?.removeListener(_hideNow);
    _anim.dispose();
    super.dispose();
  }

  void _enter() {
    _timer?.cancel();
    if (_portal.isShowing && _anim.status != AnimationStatus.reverse) return;
    _timer = Timer(const Duration(milliseconds: 350), _show);
  }

  void _exit() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 120), _hide);
  }

  void _show() {
    final box = context.findRenderObject();
    if (!mounted || box is! RenderBox || !box.attached) return;
    final win = MediaQuery.sizeOf(context);
    final origin = box.localToGlobal(Offset.zero);
    _below = origin.dy < _estHeight;
    _dx = (win.width - 8 - _width - origin.dx).clamp(-origin.dx + 8, 0.0);
    if (!_portal.isShowing) _portal.show();
    if (reduceMotion(context)) {
      _anim.value = 1;
    } else {
      _anim.duration = Motion.fast;
      _anim.forward();
    }
  }

  void _hide() {
    _timer?.cancel();
    if (!_portal.isShowing) return;
    if (reduceMotion(context)) {
      _anim.value = 0;
      _portal.hide();
      return;
    }
    _anim.reverse().whenComplete(() {
      if (mounted && _anim.isDismissed && _portal.isShowing) _portal.hide();
    });
  }

  void _hideNow() {
    _timer?.cancel();
    if (!_portal.isShowing) return;
    _anim.value = 0;
    _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    if (kMobile) return widget.child;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) => CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: _below ? Alignment.bottomLeft : Alignment.topLeft,
        followerAnchor: _below ? Alignment.topLeft : Alignment.bottomLeft,
        offset: Offset(_dx, _below ? 8 : -8),
        child: Align(
          alignment: _below ? Alignment.topLeft : Alignment.bottomLeft,
          child: MouseRegion(
            onEnter: (_) => _timer?.cancel(),
            onExit: (_) => _exit(),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, child) => Opacity(
                opacity: Curves.easeOut.transform(_anim.value),
                child: Transform.translate(
                  offset: Offset(0, (1 - _anim.value) * (_below ? -4 : 4)),
                  child: child,
                ),
              ),
              child: _HoverCard(
                name: widget.name,
                isImage: widget.isImage,
                localPath: widget.localPath,
                sizeBytes: widget.sizeBytes,
                pastedText: widget.pastedText,
                imageProvider: widget.imageProvider,
              ),
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _exit(),
          child: Listener(
            onPointerDown: (_) => _hideNow(),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _HoverCard extends StatelessWidget {
  const _HoverCard({
    required this.name,
    required this.isImage,
    this.localPath,
    this.sizeBytes,
    this.pastedText,
    this.imageProvider,
  });

  final String name;
  final bool isImage;
  final String? localPath;
  final int? sizeBytes;
  final String? pastedText;
  final ImageProvider? imageProvider;

  int? _size() {
    if (pastedText != null) return utf8.encode(pastedText!).length;
    if (sizeBytes != null) return sizeBytes;
    final p = localPath;
    if (p == null) return null;
    try {
      return File(p).lengthSync();
    } catch (_) {
      return null;
    }
  }

  ImageProvider? _provider() {
    final p = localPath;
    try {
      if (p != null && File(p).existsSync()) return FileImage(File(p));
    } catch (_) {}
    return imageProvider;
  }

  Widget _box(Widget child, {double h = 120}) => SizedBox(
      width: 296, height: h, child: Center(child: child));

  Widget _content() {
    final text = pastedText;
    if (text != null) {
      final head = text.split('\n').take(12).join('\n');
      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.7, 1],
        ).createShader(r),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Text(head,
              maxLines: 12,
              overflow: TextOverflow.clip,
              style: codeMono(12, color: AppColors.fg2)),
        ),
      );
    }
    final provider = isImage ? _provider() : null;
    if (provider != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(R.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 296, maxHeight: 220),
          child: Image(
            image: provider,
            fit: BoxFit.contain,
            frameBuilder: (_, child, frame, sync) => sync || frame != null
                ? child
                : _box(Spinner(size: 16, color: AppColors.fg3)),
            errorBuilder: (_, __, ___) => _box(
                Text('Could not load image',
                    style: sans(12, color: AppColors.fg3)),
                h: 48),
          ),
        ),
      );
    }
    final kind = mediaKindOf(name);
    return _box(
        AppIcon(kind == MediaKind.pdf ? 'pdf' : 'file',
            size: 32, color: AppColors.fg2),
        h: 72);
  }

  @override
  Widget build(BuildContext context) {
    final meta = attachmentMetaLine(
        name: name, sizeBytes: _size(), pastedText: pastedText);
    return Container(
      width: 320,
      padding: EdgeInsets.all(S.s12),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        border: Border.all(color: AppColors.border2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: overlayShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _content(),
          SizedBox(height: S.s8),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, weight: W.label, color: AppColors.fg1)),
          SizedBox(height: S.s2),
          Text(meta, style: sans(11, color: AppColors.fg3)),
        ],
      ),
    );
  }
}
