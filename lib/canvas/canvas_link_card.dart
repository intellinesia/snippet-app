import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api.dart' show DaemonClient;
import '../components.dart' show LoadingBlock, Spinner;
import '../media_views.dart' show DaemonScope;
import '../platform.dart';
import '../theme.dart';
import '../chat/desktop_rich_cards.dart';
import '../widgets.dart' show AppIcon;
import 'canvas_card_client.dart';
import 'canvas_client.dart' show DaemonCanvasClient;
import 'canvas_link.dart';
import 'canvas_models.dart' show CanvasRevEvent, formatCanvasRelativeTime;
import 'canvas_nav.dart';

const double _kMaxThumbHeight = 84;
const double _kThumbWidth = 128;
const double _kThumbRadius = 10;

/// Compact Quiet v10 preview card for a `[title](canvas:...)` markdown link.
class CanvasLinkCard extends StatefulWidget {
  const CanvasLinkCard({
    super.key,
    required this.title,
    required this.canvasRef,
    this.client,
    this.daemonClient,
    this.inline = false,
  });

  final String title;
  final CanvasRef canvasRef;
  final CanvasCardClient? client;
  final DaemonClient? daemonClient;

  /// When true, the surrounding paragraph already shows the markdown link text,
  /// so an unreachable-backend fallback collapses cleanly instead of repeating.
  final bool inline;

  @override
  State<CanvasLinkCard> createState() => _CanvasLinkCardState();
}

enum _CardPhase { loading, ready, unavailable, unreachable }

class _CanvasLinkCardState extends State<CanvasLinkCard>
    with WidgetsBindingObserver {
  CanvasCardClient? _client;
  StreamSubscription<CanvasRevEvent>? _revSub;
  StreamSubscription<void>? _reconnectSub;
  _CardPhase _phase = _CardPhase.loading;
  CanvasLinkMeta? _meta;
  CanvasLayout? _layout;
  CanvasCardActivity? _activity;
  int? _liveRev;
  Size? _decodedImageSize;
  bool _imageFailed = false;
  bool _staleWhileHidden = false;
  bool _wasTickerEnabled = true;
  bool _appResumed = true;
  int _loadSeq = 0;

  CanvasCardClient? _resolveClient(BuildContext context) {
    final override = widget.client ?? CanvasCardClientScope.maybeOf(context);
    if (override != null) return override;
    final daemon = widget.daemonClient ??
        DaemonScope.maybeOf(context) ??
        DaemonScope.current;
    if (daemon == null) return null;
    return DaemonCanvasClient.forDaemon(daemon);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextClient = _resolveClient(context);
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final becameVisible = !_wasTickerEnabled && tickerEnabled;
    _wasTickerEnabled = tickerEnabled;

    if (!identical(nextClient, _client)) {
      _client = nextClient;
      _subscribeRevEvents();
      _load();
    } else if (becameVisible && _staleWhileHidden) {
      _staleWhileHidden = false;
      _refreshLive();
    }
  }

  @override
  void didUpdateWidget(CanvasLinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canvasRef != widget.canvasRef ||
        oldWidget.client != widget.client ||
        oldWidget.daemonClient != widget.daemonClient) {
      _client = _resolveClient(context);
      _liveRev = null;
      _decodedImageSize = null;
      _imageFailed = false;
      _staleWhileHidden = false;
      _subscribeRevEvents();
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed && !_appResumed && _staleWhileHidden) {
      _staleWhileHidden = false;
      _refreshLive();
    }
    _appResumed = resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revSub?.cancel();
    _reconnectSub?.cancel();
    super.dispose();
  }

  void _subscribeRevEvents() {
    _revSub?.cancel();
    _revSub = null;
    _reconnectSub?.cancel();
    _reconnectSub = null;
    if (!widget.canvasRef.isLive) return;
    final client = _client;
    if (client == null) return;
    _revSub = client.revEvents.listen((event) {
      if (!mounted) return;
      if (!event.affectsFrame(
        widget.canvasRef.frameId,
        canvasId: widget.canvasRef.canvasId,
      )) {
        return;
      }
      final visible = _wasTickerEnabled && _appResumed;
      if (!visible) {
        _staleWhileHidden = true;
        return;
      }
      _liveRev = event.rev;
      _refreshLive();
    });
    _reconnectSub = client.onReconnected.listen((_) {
      if (!mounted) return;
      final visible = _wasTickerEnabled && _appResumed;
      if (!visible) {
        _staleWhileHidden = true;
        return;
      }
      _refreshLive();
    });
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) {
      if (mounted) setState(() => _phase = _CardPhase.unreachable);
      return;
    }
    setState(() {
      _phase = _CardPhase.loading;
      _imageFailed = false;
    });
    await _fetchMetaAndLayout(client);
  }

  Future<void> _refreshLive() async {
    final client = _client;
    if (client == null || !mounted) return;
    await _fetchMetaAndLayout(client, keepCurrentOnError: true);
  }

  Future<void> _fetchMetaAndLayout(
    CanvasCardClient client, {
    bool keepCurrentOnError = false,
  }) async {
    final seq = ++_loadSeq;
    try {
      final meta = await client.resolveLink(widget.canvasRef);
      if (!mounted || seq != _loadSeq) return;
      final elId = widget.canvasRef.elId ?? meta.elId;
      final frameId =
          meta.frameId.isNotEmpty ? meta.frameId : widget.canvasRef.frameId;
      CanvasLayout? layout;
      if (elId != null &&
          elId.isNotEmpty &&
          frameId != null &&
          frameId.isNotEmpty) {
        try {
          layout = await client.fetchCardLayout(
            frameId,
            canvasId: meta.canvasId.isNotEmpty
                ? meta.canvasId
                : widget.canvasRef.canvasId,
            rev: meta.rev,
          );
        } catch (_) {
          // Selection box is best-effort; still show the frame thumbnail.
        }
      }
      if (!mounted || seq != _loadSeq) return;
      final activity = await client
          .fetchCardActivity(widget.canvasRef, meta.rev)
          .catchError((_) => null);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _meta = meta;
        _activity = activity ?? _activity;
        _layout = layout;
        _liveRev = widget.canvasRef.isLive ? meta.rev : null;
        _imageFailed = false;
        _phase = _CardPhase.ready;
      });
    } on CanvasUnreachableException {
      if (!mounted || seq != _loadSeq || keepCurrentOnError) return;
      setState(() => _phase = _CardPhase.unreachable);
    } on CanvasUnavailableException {
      if (!mounted || seq != _loadSeq || keepCurrentOnError) return;
      setState(() => _phase = _CardPhase.unavailable);
    } catch (_) {
      if (!mounted || seq != _loadSeq || keepCurrentOnError) return;
      setState(() => _phase = _CardPhase.unavailable);
    }
  }

  String get _displayTitle {
    final metaTitle = _meta?.title.trim() ?? '';
    if (metaTitle.isNotEmpty) return metaTitle;
    final linkTitle = widget.title.trim();
    if (linkTitle.isNotEmpty) return linkTitle;
    return widget.canvasRef.frameId ?? widget.canvasRef.canvasId;
  }

  int? get _effectiveRev => widget.canvasRef.rev ?? _liveRev ?? _meta?.rev;

  double get _aspectRatio {
    final metaAspect = _meta?.aspectRatio;
    if (metaAspect != null) return metaAspect;
    final lw = _layout?.frameWidth;
    final lh = _layout?.frameHeight;
    if (lw != null && lh != null && lw > 0 && lh > 0) return lw / lh;
    final decoded = _decodedImageSize;
    if (decoded != null && decoded.width > 0 && decoded.height > 0) {
      return decoded.width / decoded.height;
    }
    return 16 / 10;
  }

  void _handleTap(BuildContext context) {
    final meta = _meta;
    openCanvas(
      context,
      title: _displayTitle,
      canvasId: meta?.canvasId.isNotEmpty == true
          ? meta!.canvasId
          : widget.canvasRef.canvasId,
      // Canvas-only links open fitted rather than zooming into the preview frame.
      frameId: widget.canvasRef.frameId == null
          ? null
          : ((meta?.frameId.isNotEmpty ?? false)
              ? meta!.frameId
              : widget.canvasRef.frameId),
      elId: widget.canvasRef.elId ?? meta?.elId,
      rev: widget.canvasRef.rev ?? meta?.rev,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (kMobile) return _buildPhone(context);
    if (_phase == _CardPhase.unreachable) {
      if (widget.inline) return const SizedBox.shrink();
      if (!kMobile) {
        return Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            AppIcon('x', size: 13, color: AppColors.fg1),
            const SizedBox(width: 7),
            Expanded(
              child: Text('Canvas unreachable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, height: 18 / 13, color: AppColors.fg1)),
            ),
            DesktopRichButton('Retry',
                variant: DesktopRichButtonVariant.secondary,
                parentSurface: 1,
                onTap: _load),
          ]),
        );
      }
      return _PlainLinkFallback(
        title:
            widget.title.isNotEmpty ? widget.title : widget.canvasRef.format(),
        onTap: () => _handleTap(context),
      );
    }

    final maxWidth = kMobile ? double.infinity : 400.0;
    final revLabel = _effectiveRev != null ? ', revision $_effectiveRev' : '';
    final liveLabel = widget.canvasRef.isLive ? ', live' : '';
    return Semantics(
      button: true,
      label: 'Open canvas frame $_displayTitle$revLabel$liveLabel',
      child: Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(kMobile ? R.of(14) : 8),
              border: kMobile ? Border.all(color: AppColors.border) : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => _handleTap(context),
                child: Padding(
                  padding: EdgeInsets.all(S.s8),
                  child: LayoutBuilder(builder: (context, box) {
                    // Narrow bubbles drop the thumbnail so the text keeps room.
                    final compact = box.maxWidth < 300;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (!compact) ...[
                          SizedBox(
                            width: _kThumbWidth,
                            child: _buildThumbnailArea(context),
                          ),
                          SizedBox(width: S.s12),
                        ],
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: sans(
                                  kMobile ? 14 : 13,
                                  weight: W.label,
                                  height: 1.3,
                                  color: AppColors.fg1,
                                ),
                              ),
                              SizedBox(height: S.s2),
                              _buildSecondaryLine(),
                              _buildActivityLine(),
                            ],
                          ),
                        ),
                        SizedBox(width: S.s8),
                        _buildOpenAction(context),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhone(BuildContext context) {
    if (_phase == _CardPhase.unreachable && widget.inline) {
      return const SizedBox.shrink();
    }
    final title = _displayTitle;
    final isReady = _phase == _CardPhase.ready && !_imageFailed;
    final isLoading = _phase == _CardPhase.loading;
    final isUnreachable = _phase == _CardPhase.unreachable;
    final meta = _meta;

    Widget thumbIcon(Widget child) => Container(
          width: 56,
          height: 62,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(child: child),
        );

    Widget thumb;
    if (isReady &&
        meta != null &&
        meta.thumbUrl.isNotEmpty &&
        _client != null) {
      thumb = Container(
        width: 56,
        height: 62,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: _CanvasThumbImage(
          provider: _client!.imageProvider(meta.thumbUrl, rev: _effectiveRev),
          onDecodedSize: (_) {},
          onError: () {
            if (!mounted || _imageFailed) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_imageFailed) setState(() => _imageFailed = true);
            });
          },
        ),
      );
    } else if (isLoading) {
      thumb = thumbIcon(Spinner(size: 16, color: AppColors.fg3));
    } else if (isUnreachable) {
      thumb = thumbIcon(AppIcon('wifi-off', size: 16, color: AppColors.fg2));
    } else {
      thumb = thumbIcon(AppIcon('grid', size: 16, color: AppColors.fg3));
    }

    final lines = switch (_phase) {
      _CardPhase.loading => (
          title,
          'Loading canvas metadata...',
          '',
          AppColors.fg2,
          AppColors.fg3,
        ),
      _CardPhase.unreachable => (
          'Canvas unreachable',
          'Server timed out${_effectiveRev != null ? ' - v$_effectiveRev' : ''}',
          '',
          AppColors.fg1,
          AppColors.fg3,
        ),
      _CardPhase.unavailable => (
          '$title (unavailable)',
          'Canvas was archived or deleted',
          '',
          AppColors.fg2,
          AppColors.fg3,
        ),
      _ => (
          title,
          [
            'Canvas',
            if (_effectiveRev != null) 'v$_effectiveRev',
            if (meta?.frameCount != null)
              '${meta!.frameCount} ${meta.frameCount == 1 ? 'frame' : 'frames'}',
          ].join(' - '),
          _activity?.author?.isNotEmpty == true
              ? '${_activity!.author}${_activity!.editedAt != null ? ' - ${formatCanvasRelativeTime(_activity!.editedAt!)}' : ''}'
              : '',
          AppColors.fg1,
          AppColors.fg2,
        ),
    };

    return Semantics(
      button: true,
      label: 'Open canvas frame $title',
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: isUnreachable ? null : () => _handleTap(context),
          child: SizedBox(
            width: double.infinity,
            height: 82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Row(children: [
                thumb,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (isReady) ...[
                          AppIcon('grid', size: 12, color: AppColors.fg2),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(lines.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(14,
                                  weight: FontWeight.w500,
                                  height: 18.9 / 14,
                                  color: lines.$4)),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      Text(lines.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12,
                              height: 16.2 / 12,
                              color: lines.$5,
                              tabular: true)),
                      if (lines.$3.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(lines.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12,
                                height: 16.2 / 12,
                                color: AppColors.fg3,
                                tabular: true)),
                      ],
                    ],
                  ),
                ),
                if (isUnreachable) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 68,
                    child: DesktopRichButton('Retry',
                        variant: DesktopRichButtonVariant.secondary,
                        parentSurface: 1,
                        onTap: _load),
                  ),
                ] else ...[
                  const SizedBox(width: 8),
                  AppIcon('chevron-right', size: 13, color: AppColors.fg3),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpenAction(BuildContext context) {
    if (!kMobile) {
      return DesktopRichButton('Open',
          variant: DesktopRichButtonVariant.ghost,
          onTap: () => _handleTap(context));
    }
    return Semantics(
      button: true,
      label: 'Open canvas',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: S.s8),
        child: Text('Open',
            style: sans(13, weight: W.label, color: AppColors.accent)),
      ),
    );
  }

  Widget _buildActivityLine() {
    final a = _activity;
    if (_phase != _CardPhase.ready || a == null) return const SizedBox.shrink();
    final parts = <String>[
      if (a.author != null && a.author!.isNotEmpty)
        'Edited by ${a.author}'
            '${a.editedAt != null ? ', ${formatCanvasRelativeTime(a.editedAt!)}' : ''}',
      if (a.comments > 0)
        '${a.comments} ${a.comments == 1 ? 'comment' : 'comments'}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: S.s2),
      child: Text(
        parts.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: sans(12, height: 1.35, color: AppColors.fg3, tabular: true),
      ),
    );
  }

  Widget _buildThumbnailArea(BuildContext context) {
    if (_phase == _CardPhase.loading) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_kThumbRadius),
        child: const SizedBox(
          height: 72,
          width: double.infinity,
          child: LoadingBlock(radius: _kThumbRadius, spinner: true),
        ),
      );
    }

    if (_phase == _CardPhase.unavailable || _imageFailed || _meta == null) {
      return Container(
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(_kThumbRadius),
        ),
        alignment: Alignment.center,
        child: AppIcon('image', size: 22, color: AppColors.fg3),
      );
    }

    final meta = _meta!;
    final client = _client!;
    final rev = _effectiveRev;
    final provider = client.imageProvider(meta.thumbUrl, rev: rev);
    final elId = widget.canvasRef.elId ?? meta.elId;
    final box = (elId != null && _layout != null) ? _layout![elId] : null;
    final logicalW =
        _layout?.frameWidth ?? meta.width ?? _decodedImageSize?.width;
    final logicalH =
        _layout?.frameHeight ?? meta.height ?? _decodedImageSize?.height;

    return LayoutBuilder(builder: (context, constraints) {
      final aspect = _aspectRatio.clamp(0.25, 4.0);
      final availW =
          constraints.maxWidth.isFinite ? constraints.maxWidth : 340.0;
      var renderW = availW;
      var renderH = renderW / aspect;
      if (renderH > _kMaxThumbHeight) {
        renderH = _kMaxThumbHeight;
        renderW = (renderH * aspect).clamp(1.0, availW);
      }

      final imageWidget = SizedBox(
        width: renderW,
        height: renderH,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kThumbRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CanvasThumbImage(
                provider: provider,
                onDecodedSize: (size) {
                  if (!mounted || _decodedImageSize == size) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _decodedImageSize != size) {
                      setState(() => _decodedImageSize = size);
                    }
                  });
                },
                onError: () {
                  if (!mounted || _imageFailed) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_imageFailed) {
                      setState(() => _imageFailed = true);
                    }
                  });
                },
              ),
              if (box != null &&
                  logicalW != null &&
                  logicalH != null &&
                  logicalW > 0 &&
                  logicalH > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SelectionRectPainter(
                        box: box,
                        frameWidth: logicalW,
                        frameHeight: logicalH,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

      // Center narrow portrait frames on a subtle rounded-10 mat so the card
      // stays visually balanced without cropping the frame.
      if (renderW < availW - 1) {
        return Container(
          width: availW,
          height: renderH,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(_kThumbRadius),
          ),
          alignment: Alignment.center,
          child: imageWidget,
        );
      }
      return imageWidget;
    });
  }

  Widget _buildSecondaryLine() {
    final style = sans(12, height: 1.35, color: AppColors.fg3, tabular: true);
    if (_phase == _CardPhase.unavailable || _imageFailed) {
      return Text('Frame unavailable', maxLines: 1, style: style);
    }
    if (_phase == _CardPhase.loading) {
      final rev = widget.canvasRef.rev;
      final label = rev != null ? 'Canvas · rev $rev' : 'Canvas · loading…';
      return Text(label, maxLines: 1, style: style);
    }
    final rev = _effectiveRev ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'Canvas · rev $rev',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (widget.canvasRef.isLive) ...[
          Text(' · ', style: style),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.ok,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text('live', style: style),
        ],
      ],
    );
  }
}

class _CanvasThumbImage extends StatefulWidget {
  const _CanvasThumbImage({
    required this.provider,
    required this.onDecodedSize,
    required this.onError,
  });

  final ImageProvider provider;
  final ValueChanged<Size> onDecodedSize;
  final VoidCallback onError;

  @override
  State<_CanvasThumbImage> createState() => _CanvasThumbImageState();
}

class _CanvasThumbImageState extends State<_CanvasThumbImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_CanvasThumbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      PaintingBinding.instance.imageCache.evict(oldWidget.provider);
      _resolve();
    }
  }

  void _resolve() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    final stream =
        widget.provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        final ui.Image img = info.image;
        widget.onDecodedSize(
          Size(img.width.toDouble(), img.height.toDouble()),
        );
      },
      onError: (_, __) => widget.onError(),
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: widget.provider,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) {
        if (sync || frame != null) return child;
        return const LoadingBlock(radius: _kThumbRadius, spinner: true);
      },
      errorBuilder: (_, __, ___) {
        widget.onError();
        return Container(
          color: AppColors.surface1,
          alignment: Alignment.center,
          child: AppIcon('image', size: 22, color: AppColors.fg3),
        );
      },
    );
  }
}

class _SelectionRectPainter extends CustomPainter {
  const _SelectionRectPainter({
    required this.box,
    required this.frameWidth,
    required this.frameHeight,
    required this.color,
  });

  final CanvasElementBox box;
  final double frameWidth;
  final double frameHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / frameWidth;
    final sy = size.height / frameHeight;
    final rect = Rect.fromLTWH(
      box.x * sx,
      box.y * sy,
      box.w * sx,
      box.h * sy,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SelectionRectPainter old) =>
      old.box != box ||
      old.frameWidth != frameWidth ||
      old.frameHeight != frameHeight ||
      old.color != color;
}

class _PlainLinkFallback extends StatelessWidget {
  const _PlainLinkFallback({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open canvas link $title',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 44 : 0),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              title,
              style: TS.body(AppColors.accent).copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.accent.withValues(alpha: 0.5),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
