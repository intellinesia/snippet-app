import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../media_views.dart' show DaemonScope;
import '../notification_sync.dart' show foregroundNotifications;
import '../platform.dart';
import '../theme.dart';
import '../toast_avoid.dart';
import '../widgets.dart';
import 'canvas_client.dart';
import 'canvas_minimap.dart';
import 'canvas_models.dart';
import 'canvas_outline.dart';
import 'canvas_pin_thread.dart';
import 'canvas_painter.dart';
import 'canvas_panels.dart';
import 'canvas_tool_rail.dart';
import 'canvas_viewport.dart';
import 'spatial_index.dart';
import 'thumb_cache.dart';

enum CanvasTool { select, pin }

enum _SidePanelMode { none, pins, pinThread, pinComposer, steps }

/// In-app infinite canvas screen rendered from server PNG thumbnails.
/// A readable reason a canvas failed to load; Retry stays on the error state.
String canvasLoadMessage(Object e) => e is TimeoutException
    ? 'The daemon took too long to send this canvas. Check the connection and retry.'
    : e is SocketException
        ? 'Could not reach the daemon. Check the connection and retry.'
        : '$e';

/// Title for the top bar: the frame under the viewport centre, the only
/// visible frame, else [fallback] (the canvas title) when several compete.
String canvasBarTitle(List<CanvasFrame> frames, Rect world, String fallback) {
  final visible = [
    for (final f in frames)
      if (f.bounds.overlaps(world)) f
  ];
  CanvasFrame? pick;
  for (final f in visible) {
    if (f.bounds.contains(world.center)) pick = f;
  }
  pick ??= visible.length == 1 ? visible.first : null;
  final t = pick?.title.trim() ?? '';
  return t.isEmpty ? fallback : t;
}

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({
    super.key,
    this.client,
    this.daemonClient,
    this.initialFrameId,
    this.initialElId,
    this.initialRev,
    this.canvasId,
    this.title,
    this.onClose,
  });

  /// Explicit client override (useful in tests).
  final CanvasClient? client;

  /// Active daemon client used to construct [DaemonCanvasClient].
  final DaemonClient? daemonClient;

  final String? initialFrameId;
  final String? initialElId;
  final int? initialRev;

  /// Canvas to open; null opens the workspace canvas.
  final String? canvasId;

  /// Display title for the phone top bar; falls back to "Canvas".
  final String? title;

  /// Set when hosted as a shell tab: closes the tab instead of popping a route.
  final VoidCallback? onClose;

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CanvasClient? _client;
  bool _ownsClient = false;
  late final CanvasViewportController _viewport;
  final CanvasSpatialIndex _index = CanvasSpatialIndex(cellSize: 1024.0);
  late final ThumbLruCache<ui.Image> _thumbCache;

  late final AnimationController _animController;
  Matrix4? _animFrom;
  Matrix4? _animTo;

  CanvasSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  CanvasTool _tool = CanvasTool.select;
  bool _isInteracting = false;
  Size _viewportSize = Size.zero;
  bool _didInitialFit = false;
  int _paintVersion = 0;
  int _cacheGeneration = 0;

  // Selection state.
  String? _selectedFrameId;
  CanvasElementRect? _selectedElement;
  final Map<String, List<CanvasElementRect>> _layouts = {};
  final Map<String, Future<List<CanvasElementRect>?>> _inFlightLayouts = {};
  final Map<String, DateTime> _failedLayouts = {};

  // Pins state.
  List<CanvasPin> _pins = const <CanvasPin>[];
  String? _selectedPinId;
  PendingPinAnchor? _pendingPin;
  _SidePanelMode _panelMode = _SidePanelMode.none;

  // Steps history state.
  List<CanvasOpBatch> _ops = const <CanvasOpBatch>[];
  String? _revertingBatchId;
  int? _previewRev;

  // Thumbnail fetch queue.
  final Set<ThumbCacheKey> _inFlightThumbs = <ThumbCacheKey>{};
  final Map<ThumbCacheKey, DateTime> _failedThumbs = {};
  int _activeThumbFetches = 0;
  static const int _maxConcurrentThumbFetches = 6;
  static const Duration _retryCooldown = Duration(seconds: 15);
  final List<_ThumbFetchJob> _pendingThumbQueue = <_ThumbFetchJob>[];

  // Trackpad / pinch gesture state.
  Offset _lastFocal = Offset.zero;
  double _lastScale = 1.0;
  double _lastTrackpadScale = 1.0;
  Offset? _lastTapDownPos;
  Set<String> _lastQueuedVisibleIds = const <String>{};
  double _lastQueuedScaleBucket = -1;
  int _lastQueuedCacheGen = -1;

  // Visibility-aware live refresh state.
  StreamSubscription<CanvasRevEvent>? _revSub;
  StreamSubscription<void>? _reconnectSub;
  bool _wasTickerEnabled = true;
  bool _appResumed = true;
  bool _staleWhileHidden = false;
  final Set<String> _pendingInvalidations = <String>{};
  int _canvasLoadSeq = 0;
  int _pinsLoadSeq = 0;
  int _opsLoadSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewport = CanvasViewportController();
    _thumbCache = ThumbLruCache<ui.Image>(
      maxBytes: kMobile
          ? ThumbLruCache.phoneBudgetBytes
          : ThumbLruCache.desktopBudgetBytes,
      onEvict: (_, img) => img.dispose(),
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_onAnimTick);

    if (widget.client != null) {
      _attachClient(widget.client!, owns: false);
    } else if (widget.daemonClient != null) {
      _attachClient(
          DaemonCanvasClient(widget.daemonClient!, canvasId: widget.canvasId),
          owns: true);
    } else {
      _loading = false;
      _error = 'Connect to a daemon to view Canvas.';
    }

    if (_client != null) {
      _loadCanvas(fitAfterLoad: true);
      _loadPins();
      _loadOps();
    }
  }

  void _attachClient(CanvasClient client, {required bool owns}) {
    _revSub?.cancel();
    _reconnectSub?.cancel();
    if (_ownsClient) {
      _client?.dispose();
    }
    _client = client;
    _ownsClient = owns;
    _revSub = client.revEvents.listen(_onRevEvent);
    _reconnectSub = client.onReconnected.listen((_) => _onReconnected());
  }

  bool _tryAttachDaemonFromScope() {
    if (_client != null) return true;
    final daemon = widget.daemonClient ??
        DaemonScope.maybeOf(context) ??
        DaemonScope.current;
    if (daemon == null) return false;
    _attachClient(DaemonCanvasClient(daemon, canvasId: widget.canvasId),
        owns: true);
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final becameVisible = !_wasTickerEnabled && tickerEnabled;
    _wasTickerEnabled = tickerEnabled;

    if (_client == null && _tryAttachDaemonFromScope()) {
      _loadCanvas(fitAfterLoad: true);
      _loadPins();
      _loadOps();
      return;
    }
    if (becameVisible && _staleWhileHidden) {
      _flushStaleRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed && !_appResumed && _staleWhileHidden) {
      _flushStaleRefresh();
    }
    _appResumed = resumed;
  }

  void _flushStaleRefresh() {
    _staleWhileHidden = false;
    for (final id in _pendingInvalidations) {
      _thumbCache.invalidateFrame(id);
      _layouts.remove(id);
      _failedLayouts.remove(id);
    }
    _pendingInvalidations.clear();
    _failedThumbs.clear();
    _paintVersion++;
    _loadCanvas();
    _loadPins();
    _loadOps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revSub?.cancel();
    _reconnectSub?.cancel();
    _animController.dispose();
    _viewport.dispose();
    _thumbCache.clear();
    if (_ownsClient) {
      _client?.dispose();
    }
    super.dispose();
  }

  /// Width this screen is laid out in. It can be a narrow shell pane, so
  /// layout follows it rather than the window.
  double _contentWidth = 1200;
  bool? _outlineOpen;

  /// Docked side panels (pins, steps) need room beside the canvas.
  bool _isDesktopPanelLayout(BuildContext context) =>
      !kMobile && _contentWidth >= 900;

  /// Below this the canvas drops the rails and uses the phone dock.
  bool _isPhoneLayout(BuildContext context) =>
      kMobile || _contentWidth < _kWideMin;

  static const double _kWideMin = 560;
  static const double _kOutlineMinCanvas = 480;

  void _onAnimTick() {
    final from = _animFrom;
    final to = _animTo;
    if (from == null || to == null) return;
    final t = Curves.easeOutCubic.transform(_animController.value);
    final next = Matrix4.identity();
    for (var i = 0; i < 16; i++) {
      next.storage[i] = ui.lerpDouble(from.storage[i], to.storage[i], t)!;
    }
    _viewport.setTransform(next);
  }

  void _animateTo(Matrix4 target) {
    _animFrom = _viewport.transform.clone();
    _animTo = target.clone();
    _animController
      ..reset()
      ..forward();
  }

  Future<void> _loadCanvas({bool fitAfterLoad = false}) async {
    if (_client == null && !_tryAttachDaemonFromScope()) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connect to a daemon to view Canvas.';
        });
      }
      return;
    }
    final client = _client!;
    final seq = ++_canvasLoadSeq;
    setState(() {
      _loading = _snapshot == null;
      _error = null;
    });
    try {
      final snap = await client.fetchCanvas();
      if (!mounted || seq != _canvasLoadSeq) return;
      _index.rebuild(snap.frames);
      final liveIds = {for (final f in snap.frames) f.id};
      _layouts.removeWhere((id, _) => !liveIds.contains(id));
      _failedLayouts.removeWhere((id, _) => !liveIds.contains(id));
      if (_selectedFrameId != null && !liveIds.contains(_selectedFrameId)) {
        _selectedFrameId = null;
        _selectedElement = null;
      }
      _paintVersion++;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
      if (fitAfterLoad || !_didInitialFit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _viewportSize.isEmpty) return;
          _fitInitialTarget();
        });
      }
    } catch (e) {
      if (!mounted || seq != _canvasLoadSeq) return;
      setState(() {
        _error = canvasLoadMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadPins() async {
    final client = _client;
    if (client == null) return;
    final seq = ++_pinsLoadSeq;
    try {
      final list = await client.fetchPins();
      if (!mounted || seq != _pinsLoadSeq) return;
      _paintVersion++;
      setState(() => _pins = list);
      for (final p in list) {
        if (p.elId != null && p.elId!.isNotEmpty) {
          _ensureLayoutLoaded(p.frameId);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadOps({int since = 0}) async {
    final client = _client;
    if (client == null) return;
    final seq = ++_opsLoadSeq;
    try {
      final list = await client.fetchOps(since: since);
      if (!mounted || seq != _opsLoadSeq) return;
      setState(() => _ops = list);
    } catch (_) {}
  }

  void _onRevEvent(CanvasRevEvent event) {
    final cid = widget.canvasId;
    if (cid != null && event.canvasId != null && event.canvasId != cid) return;
    if (!(_wasTickerEnabled && _appResumed)) {
      _staleWhileHidden = true;
      _pendingInvalidations.addAll(event.frameIds);
      return;
    }
    for (final id in event.frameIds) {
      _thumbCache.invalidateFrame(id, keepRev: event.rev);
      _layouts.remove(id);
      _failedLayouts.remove(id);
      _failedThumbs.removeWhere((k, _) => k.frameId == id);
    }
    _paintVersion++;
    _loadCanvas();
    _loadPins();
    _loadOps();
  }

  void _onReconnected() {
    if (!(_wasTickerEnabled && _appResumed)) {
      _staleWhileHidden = true;
      return;
    }
    _failedThumbs.clear();
    _failedLayouts.clear();
    _loadCanvas();
    _loadPins();
    _loadOps();
  }

  Future<void> _fitInitialTarget() async {
    _didInitialFit = true;
    final snap = _snapshot;
    final requestedRev = widget.initialRev;
    if (requestedRev != null && snap != null && snap.rev != requestedRev) {
      _showToast('Showing latest r${snap.rev} (link was r$requestedRev)');
    }
    final targetId = widget.initialFrameId;
    if (targetId != null && targetId.isNotEmpty) {
      final frame = _index.frameById(targetId);
      if (frame != null) {
        setState(() => _selectedFrameId = frame.id);
        _viewport.fitRect(frame.bounds, _viewportSize, padding: _fitPadding());
        final rects = await _ensureLayoutLoaded(frame.id);
        if (!mounted || _selectedFrameId != frame.id) return;
        final initialEl = widget.initialElId;
        if (initialEl != null && initialEl.isNotEmpty && rects != null) {
          final match = rects.where((r) => r.id == initialEl).firstOrNull;
          if (match != null) {
            setState(() => _selectedElement = match);
          }
        }
        return;
      }
    }
    _fitToContent(animate: false);
  }

  EdgeInsets _fitPadding() {
    final isPhone = _isPhoneLayout(context);
    return isPhone
        ? const EdgeInsets.fromLTRB(24, 72, 24, 96)
        : const EdgeInsets.fromLTRB(64, 32, 64, 48);
  }

  void _fitToContent({bool animate = true}) {
    final bounds = _index.contentBounds;
    if (bounds == null || _viewportSize.isEmpty) return;
    final target = _viewport.computeFitTransform(
      bounds,
      _viewportSize,
      padding: _fitPadding(),
      maxFitScale: 1.5,
    );
    if (animate) {
      _animateTo(target);
    } else {
      _viewport.setTransform(target);
    }
  }

  void _fitFrame(CanvasFrame frame, {bool animate = true}) {
    if (_viewportSize.isEmpty) return;
    final target = _viewport.computeFitTransform(
      frame.bounds,
      _viewportSize,
      padding: _fitPadding(),
      maxFitScale: 2.5,
    );
    if (animate) {
      _animateTo(target);
    } else {
      _viewport.setTransform(target);
    }
  }

  Future<List<CanvasElementRect>?> _ensureLayoutLoaded(
    String frameId, {
    bool respectCooldown = false,
  }) {
    final cached = _layouts[frameId];
    if (cached != null) return Future.value(cached);
    final inFlight = _inFlightLayouts[frameId];
    if (inFlight != null) return inFlight;
    final client = _client;
    if (client == null) return Future.value(null);
    if (respectCooldown) {
      final failedAt = _failedLayouts[frameId];
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < _retryCooldown) {
        return Future.value(null);
      }
    }

    final frame = _index.frameById(frameId);
    final future = () async {
      try {
        final rects = await client.fetchLayout(frameId, rev: frame?.rev);
        if (!mounted) return rects;
        _failedLayouts.remove(frameId);
        _paintVersion++;
        setState(() => _layouts[frameId] = rects);
        return rects;
      } catch (_) {
        _failedLayouts[frameId] = DateTime.now();
        return null;
      } finally {
        _inFlightLayouts.remove(frameId);
      }
    }();
    _inFlightLayouts[frameId] = future;
    return future;
  }

  void _onVisibleFrames(List<CanvasFrame> visible, double scaleBucket) {
    final zoom = _viewport.scale;
    var sameVisible = _lastQueuedScaleBucket == scaleBucket &&
        _lastQueuedCacheGen == _cacheGeneration &&
        _lastQueuedVisibleIds.length == visible.length;
    if (sameVisible) {
      for (final f in visible) {
        if (!_lastQueuedVisibleIds.contains(f.id)) {
          sameVisible = false;
          break;
        }
      }
    }

    if (!sameVisible) {
      _lastQueuedScaleBucket = scaleBucket;
      _lastQueuedCacheGen = _cacheGeneration;
      _lastQueuedVisibleIds = {for (final f in visible) f.id};
      final now = DateTime.now();
      _pendingThumbQueue.clear();
      for (final frame in visible) {
        final key = ThumbCacheKey(
          frameId: frame.id,
          rev: canvasEffectiveRev(frame, _previewRev),
          scale: scaleBucket,
        );
        final failedAt = _failedThumbs[key];
        final inCooldown =
            failedAt != null && now.difference(failedAt) < _retryCooldown;
        if (!_thumbCache.containsKey(key) &&
            !_inFlightThumbs.contains(key) &&
            !inCooldown) {
          _pendingThumbQueue.add(_ThumbFetchJob(frame: frame, key: key));
        }
      }
      if (_pendingThumbQueue.isNotEmpty) {
        scheduleMicrotask(_pumpThumbQueue);
      }
    }

    for (final frame in visible) {
      if (frame.w * zoom > 400 &&
          !_layouts.containsKey(frame.id) &&
          !_inFlightLayouts.containsKey(frame.id)) {
        scheduleMicrotask(
          () => _ensureLayoutLoaded(frame.id, respectCooldown: true),
        );
      }
    }
  }

  void _pumpThumbQueue() {
    while (_activeThumbFetches < _maxConcurrentThumbFetches &&
        _pendingThumbQueue.isNotEmpty) {
      final job = _pendingThumbQueue.removeAt(0);
      if (_thumbCache.containsKey(job.key) ||
          _inFlightThumbs.contains(job.key)) {
        continue;
      }
      _inFlightThumbs.add(job.key);
      _activeThumbFetches++;
      _fetchAndDecodeThumb(job);
    }
  }

  Future<void> _fetchAndDecodeThumb(_ThumbFetchJob job) async {
    final client = _client;
    if (client == null) {
      _inFlightThumbs.remove(job.key);
      _activeThumbFetches = math.max(0, _activeThumbFetches - 1);
      return;
    }
    final gen = _cacheGeneration;
    try {
      final bytes = await client.fetchThumbPng(
        job.frame.id,
        job.key.scale,
        rev: job.key.rev,
      );
      if (!mounted || gen != _cacheGeneration) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo;
      try {
        frameInfo = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
      if (!mounted || gen != _cacheGeneration) {
        frameInfo.image.dispose();
        return;
      }
      final img = frameInfo.image;
      final estimatedBytes = img.width * img.height * 4;
      _thumbCache.put(job.key, img, estimatedBytes);
      _failedThumbs.remove(job.key);
      _viewport.markNeedsPaint();
    } catch (_) {
      _lastQueuedCacheGen = -1;
      _failedThumbs[job.key] = DateTime.now();
    } finally {
      _inFlightThumbs.remove(job.key);
      _activeThumbFetches = math.max(0, _activeThumbFetches - 1);
      if (mounted && _pendingThumbQueue.isNotEmpty) {
        _pumpThumbQueue();
      }
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    _animController.stop();
    if (event is PointerScaleEvent) {
      _viewport.zoomAt(event.scale, event.localPosition);
      return;
    }
    if (event is PointerScrollEvent) {
      final isModifierZoom = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      final isTrackpad = event.kind == PointerDeviceKind.trackpad;
      if (isTrackpad && !isModifierZoom) {
        _viewport.panBy(-event.scrollDelta);
      } else {
        final factor = math.exp(-event.scrollDelta.dy * 0.0022);
        _viewport.zoomAt(factor, event.localPosition);
      }
    }
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _animController.stop();
    _lastTrackpadScale = 1.0;
    if (!_isInteracting) {
      setState(() => _isInteracting = true);
    }
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.localPanDelta != Offset.zero) {
      _viewport.panBy(event.localPanDelta);
    }
    if (_lastTrackpadScale > 0 && event.scale > 0) {
      final stepScale = event.scale / _lastTrackpadScale;
      if ((stepScale - 1.0).abs() > 1e-4) {
        _lastTrackpadScale = event.scale;
        _viewport.zoomAt(stepScale, event.localPosition);
      }
    }
  }

  void _handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    if (_isInteracting) {
      setState(() => _isInteracting = false);
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _animController.stop();
    _lastFocal = details.localFocalPoint;
    _lastScale = 1.0;
    if (!_isInteracting) {
      setState(() => _isInteracting = true);
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final focalDelta = details.localFocalPoint - _lastFocal;
    _lastFocal = details.localFocalPoint;
    if (focalDelta != Offset.zero) {
      _viewport.panBy(focalDelta);
    }
    if (_lastScale > 0 && details.scale > 0) {
      final stepScale = details.scale / _lastScale;
      if ((stepScale - 1.0).abs() > 1e-4) {
        _lastScale = details.scale;
        _viewport.zoomAt(stepScale, details.localFocalPoint);
      }
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_isInteracting) {
      setState(() => _isInteracting = false);
    }
  }

  CanvasPin? _hitTestPin(Offset screenPos) {
    final baseRadius = _isPhoneLayout(context) ? 22.0 : 18.0;
    final hitRadius =
        math.max(12.0, baseRadius * canvasChromeScale(_viewport.scale));
    for (var i = _pins.length - 1; i >= 0; i--) {
      final pin = _pins[i];
      final frame = _index.frameById(pin.frameId);
      if (frame == null) continue;
      final anchor = pinWorldAnchor(pin, frame, _layouts);
      final screenAnchor = _viewport.worldToScreen(anchor);
      if ((screenAnchor - screenPos).distance <= hitRadius) {
        return pin;
      }
    }
    return null;
  }

  Future<void> _handleTapUp(TapUpDetails details) async {
    final pos = details.localPosition;
    final hitPin = _hitTestPin(pos);
    if (hitPin != null) {
      _openPinThread(hitPin);
      return;
    }

    final world = _viewport.screenToWorld(pos);
    final frame = _index.hitTestFrame(world.dx, world.dy);
    if (frame == null) {
      setState(() {
        _selectedFrameId = null;
        _selectedElement = null;
        _selectedPinId = null;
      });
      return;
    }

    if (_tool == CanvasTool.pin) {
      await _startPinAt(frame, world);
      return;
    }

    final screenFrameW = frame.w * _viewport.scale;
    setState(() {
      _selectedFrameId = frame.id;
      _selectedPinId = null;
      if (screenFrameW <= 400) {
        _selectedElement = null;
      }
    });

    if (screenFrameW > 400) {
      await _selectElementAt(frame, world);
    }
  }

  Future<void> _selectElementAt(CanvasFrame frame, Offset worldPos) async {
    final local = Offset(worldPos.dx - frame.x, worldPos.dy - frame.y);
    final rects = await _ensureLayoutLoaded(frame.id);
    if (!mounted || _selectedFrameId != frame.id) return;
    if (rects != null && rects.isNotEmpty) {
      final hit = hitTestCanvasElements(rects, local);
      setState(() => _selectedElement = hit);
      return;
    }
    final client = _client;
    if (client == null) return;
    try {
      final elId = await client.hitTestRemote(frame.id, local.dx, local.dy);
      if (!mounted ||
          _selectedFrameId != frame.id ||
          elId == null ||
          elId.isEmpty) {
        return;
      }
      setState(() {
        _selectedElement = CanvasElementRect(
          id: elId,
          x: 0,
          y: 0,
          w: frame.w,
          h: frame.h,
        );
      });
    } catch (_) {}
  }

  void _handleDoubleTap() {
    final pos = _lastTapDownPos;
    if (pos == null) return;
    final world = _viewport.screenToWorld(pos);
    final frame = _index.hitTestFrame(world.dx, world.dy);
    if (frame == null) {
      _fitToContent();
      return;
    }
    setState(() {
      _selectedFrameId = frame.id;
      _selectedElement = null;
    });
    _fitFrame(frame);
    _ensureLayoutLoaded(frame.id);
  }

  Future<void> _handleLongPress(LongPressStartDetails details) async {
    final world = _viewport.screenToWorld(details.localPosition);
    final frame = _index.hitTestFrame(world.dx, world.dy);
    if (frame == null) return;
    await _startPinAt(frame, world);
  }

  Future<void> _startPinAt(CanvasFrame frame, Offset worldPos) async {
    final local = Offset(worldPos.dx - frame.x, worldPos.dy - frame.y);
    final rects = await _ensureLayoutLoaded(frame.id);
    if (!mounted) return;
    final el = rects != null ? hitTestCanvasElements(rects, local) : null;

    double dx;
    double dy;
    if (el != null && el.w > 0 && el.h > 0) {
      dx = ((local.dx - el.x) / el.w).clamp(0.0, 1.0);
      dy = ((local.dy - el.y) / el.h).clamp(0.0, 1.0);
    } else {
      dx = (local.dx / math.max(1.0, frame.w)).clamp(0.0, 1.0);
      dy = (local.dy / math.max(1.0, frame.h)).clamp(0.0, 1.0);
    }

    final anchor = PendingPinAnchor(
      frame: frame,
      element: el,
      dx: dx,
      dy: dy,
    );
    setState(() {
      _selectedFrameId = frame.id;
      _selectedElement = el;
      _pendingPin = anchor;
    });

    if (_isDesktopPanelLayout(context)) {
      setState(() => _panelMode = _SidePanelMode.pinComposer);
    } else {
      await _showPinComposerSheet(anchor);
    }
  }

  Future<bool> _submitPendingPin(PendingPinAnchor anchor, String text) async {
    final client = _client;
    if (client == null) {
      _showToast('Connect to a daemon to place pins.');
      return false;
    }
    try {
      final created = await client.createPin(
        frameId: anchor.frame.id,
        elId: anchor.element?.id,
        dx: anchor.dx,
        dy: anchor.dy,
        text: text,
      );
      if (!mounted) return false;
      _paintVersion++;
      setState(() {
        _pins = [..._pins, created];
        _selectedPinId = created.id;
        _pendingPin = null;
        _tool = CanvasTool.select;
        if (_panelMode == _SidePanelMode.pinComposer) {
          _panelMode = _SidePanelMode.pins;
        }
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showToast('Could not save pin: $e');
      return false;
    }
  }

  Future<void> _togglePinResolve(CanvasPin pin) async {
    final client = _client;
    if (client == null) return;
    final nextStatus = pin.isResolved ? 'open' : 'resolved';
    try {
      final updated = await client.patchPin(pin.id, status: nextStatus);
      if (!mounted) return;
      _paintVersion++;
      setState(() {
        _pins = [
          for (final p in _pins)
            if (p.id == updated.id) updated else p,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      _showToast('Could not update pin: $e');
    }
  }

  void _focusPin(CanvasPin pin) {
    final frame = _index.frameById(pin.frameId);
    setState(() {
      _selectedPinId = pin.id;
      if (frame != null) _selectedFrameId = frame.id;
    });
    if (frame != null) {
      _fitFrame(frame);
    }
    _openPinThread(pin);
  }

  Widget _pinThreadBody(CanvasPin pin, {VoidCallback? onChanged}) {
    final frame = _index.frameById(pin.frameId);
    final at = pin.createdAt;
    final pinRev = at == null ? 0 : canvasRevAt(_ops, at);
    final touching = pinRev > 0
        ? canvasStepsTouching(_ops, pin.frameId, pinRev)
        : const <CanvasOpBatch>[];
    final changed = touching.isNotEmpty && frame != null;
    return PinThreadView(
      pin: pin,
      frameTitle:
          frame == null || frame.title.isEmpty ? pin.frameId : frame.title,
      client: _client,
      beforeRev: changed ? pinRev : null,
      afterRev: changed ? frame.rev : null,
      revertBusy: _revertingBatchId != null,
      onRevert: changed
          ? () => _confirmAndRevert(touching.first, onBusyChanged: onChanged)
          : null,
      onApprove: () async {
        await _togglePinResolve(pin);
        onChanged?.call();
      },
    );
  }

  void _openPinThread(CanvasPin pin) {
    setState(() {
      _selectedPinId = pin.id;
      _pendingPin = null;
    });
    if (_isDesktopPanelLayout(context)) {
      setState(() => _panelMode = _SidePanelMode.pinThread);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface1,
      barrierColor: AppColors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final live = _pins.where((p) => p.id == pin.id).firstOrNull ?? pin;
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.75,
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(S.s16, S.s12, S.s8, S.s8),
                    child: Row(
                      children: [
                        Text('Pin thread',
                            style: sans(15,
                                weight: W.label, color: AppColors.fg1)),
                        const Spacer(),
                        CanvasCloseButton(
                            onPressed: () => Navigator.of(sheetCtx).pop()),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: AppColors.border),
                  Expanded(
                    child: _pinThreadBody(live, onChanged: () {
                      if (sheetCtx.mounted) setSheetState(() {});
                    }),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openPinsPanel() {
    if (_isDesktopPanelLayout(context)) {
      setState(() {
        _panelMode = _panelMode == _SidePanelMode.pins
            ? _SidePanelMode.none
            : _SidePanelMode.pins;
      });
    } else {
      _showPinsSheet();
    }
  }

  Future<void> _openStepsPanel() async {
    await _loadOps();
    if (!mounted) return;
    if (_isDesktopPanelLayout(context)) {
      setState(() {
        _panelMode = _panelMode == _SidePanelMode.steps
            ? _SidePanelMode.none
            : _SidePanelMode.steps;
      });
    } else {
      await _showStepsSheet();
    }
  }

  Future<void> _confirmAndRevert(
    CanvasOpBatch batch, {
    VoidCallback? onBusyChanged,
  }) async {
    final client = _client;
    if (client == null || _revertingBatchId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.modalScrim,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kMobile ? R.md : R.of(10)),
          side: BorderSide(
              color: kMobile ? AppColors.border : AppColors.paneLine),
        ),
        title: Text('Revert step?',
            style: sans(16,
                weight: W.title,
                color: Color.lerp(AppColors.fg1, AppColors.fg2, 0.3))),
        content: Text(
          'Revert "${batch.label.isNotEmpty ? batch.label : batch.batchId}" (r${batch.rev})?',
          style: sans(13, color: AppColors.fg2),
        ),
        actions: [
          SizedBox(
            height: kMobile ? kTapTarget : 32,
            child: TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(false),
              child: Text('Cancel', style: sans(13, color: AppColors.fg2)),
            ),
          ),
          SizedBox(
            height: kMobile ? kTapTarget : 32,
            child: TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(true),
              child: Text('Revert',
                  style: sans(13, weight: W.label, color: AppColors.danger)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revertingBatchId = batch.batchId);
    onBusyChanged?.call();
    try {
      final nextRev = await client.revertBatch(batch.batchId);
      if (!mounted) return;
      await _refreshAfterHistoryChange();
      if (!mounted) return;
      _showToast(
          'Reverted. Canvas is now at r${nextRev > 0 ? nextRev : (_snapshot?.rev ?? 0)}');
    } catch (e) {
      if (!mounted) return;
      _showToast('Revert failed: $e');
    } finally {
      if (mounted) setState(() => _revertingBatchId = null);
      onBusyChanged?.call();
    }
  }

  Future<void> _refreshAfterHistoryChange() async {
    _previewRev = null;
    _cacheGeneration++;
    _thumbCache.clear();
    _layouts.clear();
    _failedThumbs.clear();
    _failedLayouts.clear();
    _lastQueuedCacheGen = -1;
    _paintVersion++;
    await _loadCanvas();
    await _loadOps();
    await _loadPins();
  }

  /// Shows the canvas as it was at [batch]; null returns to the latest.
  void _previewStep(CanvasOpBatch? batch) {
    final rev = batch?.rev;
    final latest = _snapshot?.rev ?? 0;
    setState(() {
      _previewRev = (rev == null || rev >= latest) ? null : rev;
      _lastQueuedCacheGen = -1;
      _paintVersion++;
    });
  }

  Future<void> _restorePreview() async {
    final client = _client;
    final target = _previewRev;
    if (client == null || target == null || _revertingBatchId != null) return;
    final newer = [
      for (final b in _ops)
        if (b.rev > target) b,
    ]..sort((a, b) => b.rev.compareTo(a.rev));
    if (newer.isEmpty) {
      _previewStep(null);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.modalScrim,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kMobile ? R.md : R.of(10)),
          side: BorderSide(
              color: kMobile ? AppColors.border : AppColors.paneLine),
        ),
        title: Text('Restore r$target?',
            style: sans(16,
                weight: W.title,
                color: Color.lerp(AppColors.fg1, AppColors.fg2, 0.3))),
        content: Text(
          'This undoes ${newer.length} ${newer.length == 1 ? 'step' : 'steps'} as new steps. Nothing is lost.',
          style: sans(13, color: AppColors.fg2),
        ),
        actions: [
          SizedBox(
            height: kMobile ? kTapTarget : 32,
            child: TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(false),
              child: Text('Cancel', style: sans(13, color: AppColors.fg2)),
            ),
          ),
          SizedBox(
            height: kMobile ? kTapTarget : 32,
            child: TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(true),
              child: Text('Restore',
                  style: sans(13, weight: W.label, color: AppColors.danger)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revertingBatchId = newer.first.batchId);
    try {
      for (final b in newer) {
        await client.revertBatch(b.batchId);
        if (!mounted) return;
      }
      await _refreshAfterHistoryChange();
      if (!mounted) return;
      _showToast('Restored r$target. Canvas is now at r${_snapshot?.rev ?? 0}');
    } catch (e) {
      if (!mounted) return;
      await _refreshAfterHistoryChange();
      if (mounted) _showToast('Restore stopped: $e');
    } finally {
      if (mounted) setState(() => _revertingBatchId = null);
    }
  }

  Widget _previewBanner() {
    final rev = _previewRev!;
    final batch = _ops.where((b) => b.rev == rev).firstOrNull;
    final label = batch == null
        ? 'Previewing r$rev'
        : 'Previewing r$rev · ${batch.author}, ${batch.label.isNotEmpty ? batch.label : batch.batchId}';
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s8, S.s8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(kMobile ? R.md : R.of(10)),
        border:
            Border.all(color: kMobile ? AppColors.border : AppColors.paneLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(13,
                    color: Color.lerp(AppColors.fg1, AppColors.fg2, 0.3))),
          ),
          SizedBox(width: S.s12),
          SizedBox(
            height: kMobile ? kTapTarget : 32,
            child: FilledButton(
              onPressed: _restorePreview,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.accentFg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kMobile ? R.sm : R.of(7)),
                ),
              ),
              child: Text('Restore this version',
                  style: sans(13, weight: W.label, color: AppColors.accentFg)),
            ),
          ),
          SizedBox(width: S.s4),
          CanvasCloseButton(onPressed: () => _previewStep(null)),
        ],
      ),
    );
  }

  Future<void> _copyShareLink() async {
    final snap = _snapshot;
    if (snap == null || _index.frames.isEmpty) {
      _showToast('Nothing to share yet');
      return;
    }
    final frame = (_selectedFrameId != null
            ? _index.frameById(_selectedFrameId!)
            : null) ??
        _index.frames.first;

    final el = _selectedFrameId == frame.id ? _selectedElement : null;
    final baseTitle = frame.title.isNotEmpty ? frame.title : frame.id;
    final title =
        (el != null && el.id.isNotEmpty) ? '$baseTitle (${el.id})' : baseTitle;
    final rev = frame.rev > 0 ? frame.rev : snap.rev;
    final link = formatCanvasMarkdownLink(
      title: title,
      canvasId: snap.canvasId,
      frameId: frame.id,
      elId: el?.id,
      rev: rev,
    );
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _showToast('Copied link: $link');
  }

  void _showToast(String message) {
    // Phones raise it in the shared top band, never over the canvas surface.
    if (kMobile) {
      // "Could not save pin: detail" becomes a title line and a body line.
      final cut = message.indexOf(': ');
      foregroundNotifications.add({
        'title': cut > 0 ? message.substring(0, cut) : message,
        if (cut > 0) 'body': message.substring(cut + 2),
        'kind': 'canvas.notice',
      });
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface2,
          content: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: sans(12, color: AppColors.fg1),
          ),
        ),
      );
  }

  Future<void> _showPinComposerSheet(PendingPinAnchor anchor) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface1,
      barrierColor: AppColors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(S.s16, S.s12, S.s8, 0),
                child: Row(
                  children: [
                    Text('New pin',
                        style: sans(15, weight: W.label, color: AppColors.fg1)),
                    const Spacer(),
                    CanvasCloseButton(
                        onPressed: () => Navigator.of(sheetCtx).pop()),
                  ],
                ),
              ),
              PinComposerView(
                anchor: anchor,
                onCancel: () => Navigator.of(sheetCtx).pop(),
                onSubmit: (text) async {
                  final saved = await _submitPendingPin(anchor, text);
                  if (saved && sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() => _pendingPin = null);
    }
  }

  Future<void> _showPinsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface1,
      barrierColor: AppColors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final titles = {for (final f in _index.frames) f.id: f.title};
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.65,
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(S.s16, S.s12, S.s8, S.s8),
                    child: Row(
                      children: [
                        Text('Pins (${_pins.length})',
                            style: sans(15,
                                weight: W.label, color: AppColors.fg1)),
                        const Spacer(),
                        CanvasCloseButton(
                            onPressed: () => Navigator.of(sheetCtx).pop()),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: AppColors.border),
                  Expanded(
                    child: PinsListView(
                      pins: _pins,
                      frameTitles: titles,
                      selectedPinId: _selectedPinId,
                      onSelectPin: (pin) {
                        Navigator.of(sheetCtx).pop();
                        _focusPin(pin);
                      },
                      onToggleResolve: (pin) async {
                        await _togglePinResolve(pin);
                        setSheetState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showStepsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface1,
      barrierColor: AppColors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.65,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(S.s16, S.s12, S.s8, S.s8),
                  child: Row(
                    children: [
                      Text('Steps (${_ops.length})',
                          style:
                              sans(15, weight: W.label, color: AppColors.fg1)),
                      const Spacer(),
                      CanvasCloseButton(
                          onPressed: () => Navigator.of(sheetCtx).pop()),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: AppColors.border),
                Expanded(
                  child: StepsHistoryView(
                    ops: _ops,
                    currentRev: _snapshot?.rev ?? 0,
                    revertingBatchId: _revertingBatchId,
                    frameTitles: {for (final f in _index.frames) f.id: f.title},
                    previewRev: _previewRev,
                    onPreview: (batch) {
                      Navigator.of(sheetCtx).pop();
                      _previewStep(batch);
                    },
                    onRevert: (batch) => _confirmAndRevert(
                      batch,
                      onBusyChanged: () {
                        if (sheetCtx.mounted) setSheetState(() {});
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          _contentWidth = c.maxWidth.isFinite ? c.maxWidth : 1200;
          return _buildBody(context);
        },
      );

  Widget _buildBody(BuildContext context) {
    final isPhone = _isPhoneLayout(context);
    final isDesktopPanel = _isDesktopPanelLayout(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final openPins = _pins.where((p) => !p.isResolved).length;

    final canvasViewport = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _viewportSize) {
          final previous = _viewportSize;
          _viewportSize = size;
          // A side panel opening or closing resizes the canvas from the right:
          // move by half the change so the content stays centred in what is visible.
          if (_didInitialFit && !previous.isEmpty && !size.isEmpty) {
            final shift = Offset(
              (size.width - previous.width) / 2,
              (size.height - previous.height) / 2,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _viewport.panBy(shift);
            });
          }
          if (!_didInitialFit && _snapshot != null && !size.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_didInitialFit) _fitInitialTarget();
            });
          }
        }

        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: _handlePointerSignal,
                onPointerPanZoomStart: _handlePointerPanZoomStart,
                onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
                onPointerPanZoomEnd: _handlePointerPanZoomEnd,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _lastTapDownPos = d.localPosition,
                  onTapUp: _handleTapUp,
                  onDoubleTapDown: (d) => _lastTapDownPos = d.localPosition,
                  onDoubleTap: _handleDoubleTap,
                  onLongPressStart: _handleLongPress,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onScaleEnd: _handleScaleEnd,
                  // Frames pan past the surface edge; clip so they never paint
                  // over the top-band toast above the page.
                  child: ClipRect(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: InfiniteCanvasPainter(
                          viewport: _viewport,
                          index: _index,
                          cache: _thumbCache,
                          devicePixelRatio: dpr,
                          isInteracting: _isInteracting,
                          isPhone: isPhone,
                          paintVersion: _paintVersion,
                          previewRev: _previewRev,
                          selectedFrameId: _selectedFrameId,
                          selectedElement: _selectedElement,
                          pins: _pins,
                          selectedPinId: _selectedPinId,
                          layouts: _layouts,
                          onVisibleFrames: _onVisibleFrames,
                          onTapPin: _openPinThread,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_loading) const Center(child: DelayedSpinner(size: 22)),
            if (_error != null) _errorBanner(),
            if (!_loading &&
                _error == null &&
                _snapshot != null &&
                _index.length == 0)
              Center(
                child: Text(
                  'No frames on this canvas yet.',
                  style: sans(12, color: AppColors.fg4),
                ),
              ),
            if (isPhone)
              Positioned(
                top: S.s12,
                left: S.s12,
                right: S.s12,
                child: _topStatusBar(openPins),
              ),
            if (_previewRev != null)
              Positioned(
                left: S.s12,
                right: S.s12,
                bottom: isPhone ? 76 : S.s16,
                child: Center(child: _previewBanner()),
              ),
            if (isPhone)
              Positioned(
                left: S.s12,
                right: S.s12,
                bottom: S.s12,
                child: _buildToolbar(isPhone: true),
              )
            else ...[
              Positioned(
                top: S.s16,
                left: S.s16,
                child: CanvasToolRail(tools: _railTools()),
              ),
              Positioned(
                right: S.s16,
                bottom: S.s16,
                child: CanvasMinimap(
                  frames: _index.frames,
                  contentBounds: _index.contentBounds,
                  viewport: _viewport,
                  viewportSize: _viewportSize,
                  selectedFrameId: _selectedFrameId,
                ),
              ),
            ],
          ],
        );
      },
    );

    final canvasArea = isPhone
        ? canvasViewport
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _desktopHeader(openPins),
              Expanded(child: canvasViewport),
            ],
          );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_panelMode != _SidePanelMode.none) {
            setState(() {
              _panelMode = _SidePanelMode.none;
              _pendingPin = null;
            });
          } else if (widget.onClose == null) {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
              child: _buildShellBody(canvasArea, isPhone, isDesktopPanel)),
        ),
      ),
    );
  }

  Widget _buildShellBody(Widget canvasArea, bool isPhone, bool isDesktopPanel) {
    final panel = isDesktopPanel && _panelMode != _SidePanelMode.none
        ? _buildDesktopSidePanel()
        : null;
    if (isPhone) {
      return Row(
          children: [Expanded(child: canvasArea), if (panel != null) panel]);
    }
    final open = _outlineOpen ?? (_contentWidth >= 900);
    final room = _contentWidth -
        kCanvasOutlineWidth -
        (panel != null ? kCanvasSidePanelWidth : 0);
    final inline = open && room >= _kOutlineMinCanvas;
    final overlay = open && !inline;
    return Stack(
      children: [
        Row(
          children: [
            if (inline) _buildOutlineRail() else _outlineStrip(),
            Expanded(child: canvasArea),
            if (panel != null) panel,
          ],
        ),
        if (overlay)
          Positioned(left: 0, top: 0, bottom: 0, child: _buildOutlineRail()),
      ],
    );
  }

  Widget _outlineStrip() => Container(
        width: 40,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border(right: BorderSide(color: AppColors.paneLine)),
        ),
        alignment: Alignment.topCenter,
        padding: EdgeInsets.only(top: S.s8),
        child: Semantics(
          button: true,
          label: 'Show outline',
          excludeSemantics: true,
          child: IconBtn('panel-left',
              size: 28,
              iconSize: 13,
              tooltip: 'Show outline',
              onTap: () => setState(() => _outlineOpen = true)),
        ),
      );

  List<CanvasRailTool> _railTools() {
    const hint = 'Frames, text and shapes are made by agents. Ask in chat.';
    return [
      CanvasRailTool(
        icon: 'corner-up-left',
        label: 'Select',
        active: _tool == CanvasTool.select,
        onTap: () => setState(() => _tool = CanvasTool.select),
      ),
      const CanvasRailTool(icon: 'scan', label: 'Frame', disabledHint: hint),
      const CanvasRailTool(
          icon: 'file-type', label: 'Text', disabledHint: hint),
      const CanvasRailTool(icon: 'circle', label: 'Shape', disabledHint: hint),
      CanvasRailTool(
        icon: 'pin',
        label: 'Pin',
        active: _tool == CanvasTool.pin,
        onTap: () => setState(() => _tool = CanvasTool.pin),
      ),
    ];
  }

  Widget _buildOutlineRail() {
    final id = _selectedFrameId;
    if (id != null && !_layouts.containsKey(id)) {
      scheduleMicrotask(() => _ensureLayoutLoaded(id, respectCooldown: true));
    }
    return CanvasOutlineRail(
      frames: _index.frames,
      selectedFrameId: id,
      selectedElementId: _selectedElement?.id,
      layers: id == null ? null : _layouts[id],
      layersLoading: id != null && _inFlightLayouts.containsKey(id),
      onCollapse: () => setState(() => _outlineOpen = false),
      onSelectFrame: (frame) {
        setState(() {
          _selectedFrameId = frame.id;
          _selectedElement = null;
          _selectedPinId = null;
        });
        _fitFrame(frame);
        _ensureLayoutLoaded(frame.id);
      },
      onSelectElement: (el) {
        final frame = _selectedFrameId == null
            ? null
            : _index.frameById(_selectedFrameId!);
        setState(() => _selectedElement = el);
        if (frame != null && frame.w * _viewport.scale <= 400) {
          _fitFrame(frame);
        }
      },
    );
  }

  Widget _buildDesktopSidePanel() {
    if (_panelMode == _SidePanelMode.pinComposer && _pendingPin != null) {
      return CanvasSidePanel(
        title: 'New pin',
        subtitle: _pendingPin!.element?.id ?? _pendingPin!.frame.title,
        onClose: () => setState(() {
          _pendingPin = null;
          _panelMode = _SidePanelMode.none;
        }),
        child: SingleChildScrollView(
          child: PinComposerView(
            anchor: _pendingPin!,
            onCancel: () => setState(() {
              _pendingPin = null;
              _panelMode = _SidePanelMode.none;
            }),
            onSubmit: (text) async {
              await _submitPendingPin(_pendingPin!, text);
            },
          ),
        ),
      );
    }

    if (_panelMode == _SidePanelMode.pinThread) {
      final pin = _pins.where((p) => p.id == _selectedPinId).firstOrNull;
      if (pin != null) {
        final n = _pins.indexOf(pin) + 1;
        final frame = _index.frameById(pin.frameId);
        return CanvasSidePanel(
          title: 'Pin $n',
          subtitle: [
            if (frame != null && frame.title.isNotEmpty) frame.title,
            if (pin.elId != null) pin.elId!,
          ].join(' · '),
          onBack: () => setState(() => _panelMode = _SidePanelMode.pins),
          onClose: () => setState(() => _panelMode = _SidePanelMode.none),
          child: _pinThreadBody(pin, onChanged: () => setState(() {})),
        );
      }
    }

    if (_panelMode == _SidePanelMode.steps) {
      return CanvasSidePanel(
        title: 'Steps',
        subtitle: _snapshot != null ? 'rev ${_snapshot!.rev}' : null,
        onClose: () => setState(() => _panelMode = _SidePanelMode.none),
        child: StepsHistoryView(
          ops: _ops,
          currentRev: _snapshot?.rev ?? 0,
          revertingBatchId: _revertingBatchId,
          onRevert: _confirmAndRevert,
          frameTitles: {for (final f in _index.frames) f.id: f.title},
          previewRev: _previewRev,
          onPreview: _previewStep,
        ),
      );
    }

    final titles = {for (final f in _index.frames) f.id: f.title};
    return CanvasSidePanel(
      title: 'Pins',
      subtitle: '${_pins.length} total',
      onClose: () => setState(() => _panelMode = _SidePanelMode.none),
      child: PinsListView(
        pins: _pins,
        frameTitles: titles,
        selectedPinId: _selectedPinId,
        onSelectPin: _focusPin,
        onToggleResolve: _togglePinResolve,
      ),
    );
  }

  Widget _errorBanner() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: EdgeInsets.all(S.s16),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(kMobile ? R.md : R.of(10)),
            border: Border.all(
                color: kMobile ? AppColors.border : AppColors.paneLine),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Canvas unavailable',
                  style: sans(14,
                      weight: W.label,
                      color: Color.lerp(AppColors.fg1, AppColors.fg2, 0.3))),
              SizedBox(height: S.s6),
              Text(_error!,
                  style: sans(12, color: AppColors.fg4),
                  textAlign: TextAlign.center),
              SizedBox(height: S.s12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: kMobile ? kTapTarget : 32,
                    child: TextButton(
                      onPressed: () {
                        _failedThumbs.clear();
                        _failedLayouts.clear();
                        _loadCanvas(fitAfterLoad: true);
                        _loadPins();
                        _loadOps();
                      },
                      child: Text('Retry',
                          style: sans(13,
                              weight: W.label, color: AppColors.accent)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopHeader(int openPins) {
    return Container(
      height: PaneRow.height,
      padding: EdgeInsets.symmetric(horizontal: S.of(10)),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.paneLine)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildToolbar(isPhone: false),
            ),
          ),
          SizedBox(width: S.s8),
          _desktopStatusPill(openPins),
        ],
      ),
    );
  }

  Widget _desktopStatusPill(int openPins) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selectedElement != null) ...[
          _ChromePill(
            onTap: _copyShareLink,
            minSize: PaneRow.pill,
            semanticLabel: 'Copy share link for ${_selectedElement!.id}',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                _selectedElement!.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(12, weight: W.label, color: PaneRow.labelOn),
              ),
            ),
          ),
          SizedBox(width: S.s4),
        ],
        _ChromePill(
          active: _panelMode == _SidePanelMode.pins,
          minSize: PaneRow.pill,
          semanticLabel: 'Pins, ${_pins.length} total, $openPins open',
          onTap: _openPinsPanel,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('pin',
                  size: 13,
                  color: openPins > 0 ? PaneRow.labelOn : AppColors.fg4),
              SizedBox(width: S.s6),
              Text(
                '${_pins.length}',
                style: mono(12, weight: W.label, color: PaneRow.labelOn),
              ),
            ],
          ),
        ),
        if (_snapshot != null) ...[
          SizedBox(width: S.s4),
          _ChromePill(
            active: _panelMode == _SidePanelMode.steps,
            onTap: _openStepsPanel,
            minSize: PaneRow.pill,
            semanticLabel: 'Steps history, revision ${_snapshot!.rev}',
            child: Text(
              'r${_snapshot!.rev}',
              style: mono(12, color: AppColors.fg4),
            ),
          ),
        ],
      ],
    );
  }

  String get _topTitle {
    final t = widget.title?.trim();
    return (t == null || t.isEmpty) ? 'Canvas' : t;
  }

  Widget _topStatusBar(int openPins) {
    return ToastAvoid(
        child: Row(
      children: [
        Expanded(
            child: Align(
                alignment: Alignment.centerLeft,
                child: IntrinsicWidth(
                    child: _ChromePill(
                  onTap: () => Navigator.of(context).maybePop(),
                  minSize: kTapTarget,
                  semanticLabel: _snapshot == null
                      ? 'Back from canvas'
                      : 'Back from canvas, revision ${_snapshot!.rev}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon('arrow-left', size: 16, color: AppColors.fg1),
                      SizedBox(width: S.s6),
                      Flexible(
                        child: ListenableBuilder(
                          listenable: _viewport,
                          builder: (_, __) => Text(
                            _snapshot == null || _viewportSize.isEmpty
                                ? _topTitle
                                : canvasBarTitle(
                                    _snapshot!.frames,
                                    _viewport.worldViewport(_viewportSize),
                                    _topTitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                sans(13, weight: W.label, color: AppColors.fg1),
                          ),
                        ),
                      ),
                      if (_snapshot != null) ...[
                        SizedBox(width: S.s8),
                        Text('r${_snapshot!.rev}',
                            style: mono(11, color: AppColors.fg3)),
                      ],
                    ],
                  ),
                )))),
        SizedBox(width: S.s8),
        _ChromePill(
          onTap: _openPinsPanel,
          minSize: kTapTarget,
          semanticLabel: 'Pins, ${_pins.length} total, $openPins open',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('pin',
                  size: 15,
                  color: openPins > 0 ? AppColors.fg1 : AppColors.fg3),
              SizedBox(width: S.s6),
              Text('${_pins.length}',
                  style: mono(12, weight: W.label, color: AppColors.fg1)),
            ],
          ),
        ),
      ],
    ));
  }

  Widget _buildToolbar({required bool isPhone}) {
    final items = <_ToolbarItem>[
      if (!isPhone && widget.onClose == null)
        _ToolbarItem(
            'arrow-left', 'Back', () => Navigator.of(context).maybePop(),
            showLabel: false),
      if (isPhone) ...[
        _ToolbarItem(
            'layers', 'Select', () => setState(() => _tool = CanvasTool.select),
            active: _tool == CanvasTool.select, showLabel: false),
        _ToolbarItem('pin', 'Pin', () => setState(() => _tool = CanvasTool.pin),
            active: _tool == CanvasTool.pin, showLabel: false),
      ],
      _ToolbarItem('expand', 'Fit', _fitToContent, showLabel: !isPhone),
      _ToolbarItem('history', 'Steps', _openStepsPanel,
          active: _panelMode == _SidePanelMode.steps, showLabel: !isPhone),
      _ToolbarItem('share', 'Share', _copyShareLink, showLabel: !isPhone),
    ];
    final bar = _OverflowToolbar(
      items: items,
      spread: isPhone,
      target: isPhone ? kTapTarget : PaneRow.pill,
    );
    if (!isPhone) return bar;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: bar,
    );
  }
}

class _ToolbarItem {
  const _ToolbarItem(this.icon, this.label, this.onTap,
      {this.active = false, this.showLabel = true});
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool showLabel;

  double width(double target) {
    if (!showLabel) return target;
    final compact = target < kTapTarget;
    return (compact ? 34 : kTapTarget) + label.length * (compact ? 6.5 : 7.0);
  }
}

/// Toolbar buttons that fit; the rest move into a menu instead of being clipped.
class _OverflowToolbar extends StatelessWidget {
  const _OverflowToolbar(
      {required this.items, required this.spread, required this.target});

  final List<_ToolbarItem> items;
  final bool spread;
  final double target;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final avail = c.maxWidth.isFinite ? c.maxWidth : double.infinity;
          var total = 0.0;
          for (final i in items) {
            total += i.width(target);
          }
          var shown = items.length;
          if (total > avail) {
            var used = target;
            shown = 0;
            for (final i in items) {
              if (used + i.width(target) > avail) break;
              used += i.width(target);
              shown++;
            }
            if (shown == 0) shown = 1;
          }
          final hidden = items.sublist(shown);
          return Row(
            mainAxisSize:
                spread && hidden.isEmpty ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: spread && hidden.isEmpty
                ? MainAxisAlignment.spaceEvenly
                : MainAxisAlignment.start,
            children: [
              for (final i in items.take(shown))
                _ToolbarButton(
                  icon: i.icon,
                  label: i.label,
                  active: i.active,
                  showLabel: i.showLabel,
                  minSize: target,
                  onTap: i.onTap,
                ),
              if (hidden.isNotEmpty)
                Builder(
                  builder: (menuContext) => Semantics(
                    button: true,
                    label: 'More canvas actions',
                    excludeSemantics: true,
                    child: IconBtn('ellipsis',
                        size: target,
                        iconSize: target < kTapTarget ? 13 : 18,
                        tooltip: 'More', onTap: () async {
                      final picked = await showAppMenu<int>(
                        menuContext,
                        anchor: menuContext,
                        below: true,
                        minWidth: 180,
                        maxWidth: 220,
                        items: [
                          for (var n = 0; n < hidden.length; n++)
                            appMenuItem(
                              value: n,
                              icon: hidden[n].icon,
                              label: hidden[n].label,
                              height: target < kTapTarget ? 28 : 30,
                            ),
                        ],
                      );
                      if (picked != null) hidden[picked].onTap();
                    }),
                  ),
                ),
            ],
          );
        },
      );
}

class _ThumbFetchJob {
  const _ThumbFetchJob({required this.frame, required this.key});
  final CanvasFrame frame;
  final ThumbCacheKey key;
}

class _ChromePill extends StatelessWidget {
  const _ChromePill({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.active = false,
    this.minSize = 36,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool active;
  final double minSize;

  @override
  Widget build(BuildContext context) {
    final compact = !kMobile;
    final radius = compact ? PaneRow.radius : R.md;
    return Semantics(
      button: true,
      selected: active,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          color: active
              ? (compact ? PaneRow.plate : AppColors.surface3)
              : (compact ? Colors.transparent : AppColors.surface1),
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radius),
            child: Container(
              constraints:
                  BoxConstraints(minHeight: minSize, minWidth: minSize),
              padding: EdgeInsets.symmetric(horizontal: compact ? S.s8 : S.s12),
              decoration: compact
                  ? null
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: active ? AppColors.accentLine : AppColors.border,
                      ),
                    ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.minSize,
    this.active = false,
    this.showLabel = true,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final double minSize;
  final bool active;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final compact = !kMobile;
    final fg = active
        ? (compact ? PaneRow.labelOn : AppColors.fg1)
        : (compact ? PaneRow.labelOff : AppColors.fg2);
    final radius = compact ? PaneRow.radius : R.sm;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: active
              ? (compact ? PaneRow.plate : AppColors.surface3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radius),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minWidth: minSize, minHeight: minSize),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: showLabel ? (compact ? 7 : S.s8) : S.s6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(icon,
                        size: compact ? 13 : 16, color: fg, filled: active),
                    if (showLabel) ...[
                      SizedBox(width: S.s6),
                      Text(
                        label,
                        style: sans(
                          compact ? PaneRow.label : 12,
                          weight: active ? W.label : W.body,
                          color: fg,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
