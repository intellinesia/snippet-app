import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../media_views.dart' show DaemonScope;
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'canvas_client.dart';
import 'canvas_minimap.dart';
import 'canvas_models.dart';
import 'canvas_outline.dart';
import 'canvas_painter.dart';
import 'canvas_panels.dart';
import 'canvas_tool_rail.dart';
import 'canvas_viewport.dart';
import 'spatial_index.dart';
import 'thumb_cache.dart';

enum CanvasTool { select, pin }

enum _SidePanelMode { none, pins, pinComposer, steps }

/// In-app infinite canvas screen rendered from server PNG thumbnails.
class CanvasScreen extends StatefulWidget {
  const CanvasScreen({
    super.key,
    this.client,
    this.daemonClient,
    this.initialFrameId,
    this.initialElId,
    this.initialRev,
  });

  /// Explicit client override (useful in tests).
  final CanvasClient? client;

  /// Active daemon client used to construct [DaemonCanvasClient].
  final DaemonClient? daemonClient;

  final String? initialFrameId;
  final String? initialElId;
  final int? initialRev;

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
      _attachClient(DaemonCanvasClient(widget.daemonClient!), owns: true);
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
    _attachClient(DaemonCanvasClient(daemon), owns: true);
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

  bool _isDesktopPanelLayout(BuildContext context) =>
      !kMobile && MediaQuery.sizeOf(context).width >= 900;

  bool _isPhoneLayout(BuildContext context) =>
      kMobile || MediaQuery.sizeOf(context).width < 900;

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
    setState(() {
      _loading = _snapshot == null;
      _error = null;
    });
    try {
      final snap = await client.fetchCanvas();
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadPins() async {
    final client = _client;
    if (client == null) return;
    try {
      final list = await client.fetchPins();
      if (!mounted) return;
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
    try {
      final list = await client.fetchOps(since: since);
      if (!mounted) return;
      setState(() => _ops = list);
    } catch (_) {}
  }

  void _onRevEvent(CanvasRevEvent event) {
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
        : const EdgeInsets.fromLTRB(64, 88, 64, 48);
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
          rev: frame.rev,
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
        rev: job.frame.rev,
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
      setState(() => _selectedPinId = hitPin.id);
      _openPinsPanel();
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
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('Revert step?',
            style: sans(16, weight: W.title, color: AppColors.fg1)),
        content: Text(
          'Revert "${batch.label.isNotEmpty ? batch.label : batch.batchId}" (r${batch.rev})?',
          style: sans(13, color: AppColors.fg2),
        ),
        actions: [
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(false),
              child: Text('Cancel', style: sans(13, color: AppColors.fg2)),
            ),
          ),
          SizedBox(
            height: 44,
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
      _cacheGeneration++;
      _thumbCache.clear();
      _layouts.clear();
      _failedThumbs.clear();
      _failedLayouts.clear();
      _paintVersion++;
      await _loadCanvas();
      await _loadOps();
      await _loadPins();
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
  Widget build(BuildContext context) {
    final isPhone = _isPhoneLayout(context);
    final isDesktopPanel = _isDesktopPanelLayout(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final openPins = _pins.where((p) => !p.isResolved).length;

    final canvasArea = LayoutBuilder(
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
                        selectedFrameId: _selectedFrameId,
                        selectedElement: _selectedElement,
                        pins: _pins,
                        selectedPinId: _selectedPinId,
                        layouts: _layouts,
                        onVisibleFrames: _onVisibleFrames,
                        onTapPin: (pin) {
                          setState(() => _selectedPinId = pin.id);
                          _openPinsPanel();
                        },
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
                  style: sans(13, color: AppColors.fg3),
                ),
              ),
            if (isPhone)
              Positioned(
                top: S.s12,
                left: S.s12,
                right: S.s12,
                child: _topStatusBar(openPins),
              )
            else
              Positioned(
                top: S.s16,
                right: S.s16,
                child: _desktopStatusPill(openPins),
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
                child: _buildToolbar(isPhone: false),
              ),
              Positioned(
                top: 88,
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

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_panelMode != _SidePanelMode.none) {
            setState(() {
              _panelMode = _SidePanelMode.none;
              _pendingPin = null;
            });
          } else {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Row(
              children: [
                if (isDesktopPanel) _buildOutlineRail(),
                Expanded(child: canvasArea),
                if (isDesktopPanel && _panelMode != _SidePanelMode.none)
                  _buildDesktopSidePanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Canvas unavailable',
                  style: sans(14, weight: W.label, color: AppColors.fg1)),
              SizedBox(height: S.s6),
              Text(_error!,
                  style: sans(12, color: AppColors.fg3),
                  textAlign: TextAlign.center),
              SizedBox(height: S.s12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 44,
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

  Widget _desktopStatusPill(int openPins) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selectedElement != null) ...[
          _ChromePill(
            onTap: _copyShareLink,
            minSize: 44,
            semanticLabel: 'Copy share link for ${_selectedElement!.id}',
            child: Text(
              _selectedElement!.id,
              style: mono(11, weight: W.label, color: AppColors.fg1),
            ),
          ),
          SizedBox(width: S.s8),
        ],
        _ChromePill(
          active: _panelMode == _SidePanelMode.pins,
          minSize: 44,
          semanticLabel: 'Pins, ${_pins.length} total, $openPins open',
          onTap: _openPinsPanel,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('pin',
                  size: 14,
                  color: openPins > 0 ? AppColors.fg1 : AppColors.fg3),
              SizedBox(width: S.s6),
              Text(
                '${_pins.length}',
                style: mono(12, weight: W.label, color: AppColors.fg1),
              ),
            ],
          ),
        ),
        if (_snapshot != null) ...[
          SizedBox(width: S.s8),
          _ChromePill(
            onTap: _openStepsPanel,
            minSize: 44,
            semanticLabel: 'Steps history, revision ${_snapshot!.rev}',
            child: Text(
              'r${_snapshot!.rev}',
              style: mono(11, color: AppColors.fg3),
            ),
          ),
        ],
      ],
    );
  }

  Widget _topStatusBar(int openPins) {
    return Row(
      children: [
        _ChromePill(
          onTap: () => Navigator.of(context).maybePop(),
          minSize: 44,
          semanticLabel: _snapshot == null
              ? 'Back from canvas'
              : 'Back from canvas, revision ${_snapshot!.rev}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('arrow-left', size: 16, color: AppColors.fg1),
              SizedBox(width: S.s6),
              Text(
                _snapshot == null ? 'Canvas' : 'Canvas  r${_snapshot!.rev}',
                style: mono(12, weight: W.label, color: AppColors.fg1),
              ),
            ],
          ),
        ),
        const Spacer(),
        _ChromePill(
          onTap: _openPinsPanel,
          minSize: 44,
          semanticLabel: 'Pins, ${_pins.length} total, $openPins open',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('pin',
                  size: 15,
                  color: openPins > 0 ? AppColors.run : AppColors.fg2),
              SizedBox(width: S.s6),
              Text('${_pins.length}',
                  style: mono(12, weight: W.label, color: AppColors.fg1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar({required bool isPhone}) {
    const btnSize = 44.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isPhone ? S.s8 : S.s6,
        vertical: S.s4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: isPhone ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            isPhone ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.start,
        children: [
          if (!isPhone) ...[
            _ToolbarButton(
              icon: 'arrow-left',
              label: 'Back',
              showLabel: false,
              minSize: btnSize,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            _ToolbarDivider(),
          ],
          if (isPhone) ...[
            _ToolbarButton(
              icon: 'layers',
              label: 'Select',
              active: _tool == CanvasTool.select,
              showLabel: false,
              minSize: btnSize,
              onTap: () => setState(() => _tool = CanvasTool.select),
            ),
            _ToolbarButton(
              icon: 'pin',
              label: 'Pin',
              active: _tool == CanvasTool.pin,
              showLabel: false,
              minSize: btnSize,
              onTap: () => setState(() => _tool = CanvasTool.pin),
            ),
          ],
          _ToolbarButton(
            icon: 'expand',
            label: 'Fit',
            showLabel: !isPhone,
            minSize: btnSize,
            onTap: _fitToContent,
          ),
          _ToolbarButton(
            icon: 'history',
            label: 'Steps',
            active: _panelMode == _SidePanelMode.steps,
            showLabel: !isPhone,
            minSize: btnSize,
            onTap: _openStepsPanel,
          ),
          _ToolbarButton(
            icon: 'share',
            label: 'Share',
            showLabel: !isPhone,
            minSize: btnSize,
            onTap: _copyShareLink,
          ),
        ],
      ),
    );
  }
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
    return Semantics(
      button: true,
      selected: active,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          color: active ? AppColors.surface3 : AppColors.surface1,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.md),
            child: Container(
              constraints:
                  BoxConstraints(minHeight: minSize, minWidth: minSize),
              padding: EdgeInsets.symmetric(horizontal: S.s12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
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
    final fg = active ? AppColors.fg1 : AppColors.fg2;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: active ? AppColors.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.sm),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minWidth: minSize, minHeight: minSize),
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: showLabel ? S.s8 : S.s6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(icon, size: 16, color: fg, filled: active),
                    if (showLabel) ...[
                      SizedBox(width: S.s6),
                      Text(
                        label,
                        style: sans(
                          12,
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

class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: EdgeInsets.symmetric(horizontal: S.s4),
        color: AppColors.border,
      );
}
