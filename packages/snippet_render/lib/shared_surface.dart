import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';

import 'snippet_render.dart';
import 'src/bindings.dart';

/// The native calls behind [SharedShaderSurface]; swapped out in tests.
abstract class SurfaceBackend {
  Future<Object?> create(String source, ShaderLang lang, int w, int h, int fps);
  int textureId(Object s);
  String? error(Object s);
  void setPaused(Object s, bool paused);
  void resize(Object s, int w, int h);
  void setShader(Object s, String source, ShaderLang lang);
  void setFps(Object s, int fps);
  void destroy(Object s);
}

class _NativeBackend implements SurfaceBackend {
  const _NativeBackend();

  Pointer<Void> _p(Object s) => Pointer<Void>.fromAddress(s as int);

  T _cstr<T>(String s, T Function(Pointer<Char>) f) {
    final p = s.toNativeUtf8();
    try {
      return f(p.cast());
    } finally {
      malloc.free(p);
    }
  }

  @override
  Future<Object?> create(
    String source,
    ShaderLang lang,
    int w,
    int h,
    int fps,
  ) async {
    final engine = await EngineContext.instance.getEngineHandle();
    final s = _cstr(source, (p) => sr_create(engine, p, lang.index, w, h, fps));
    return s == nullptr ? null : s.address;
  }

  @override
  int textureId(Object s) => sr_texture_id(_p(s));

  @override
  String? error(Object s) {
    final p = sr_error(_p(s));
    if (p == nullptr) return null;
    final e = p.cast<Utf8>().toDartString();
    sr_free_string(p);
    return e;
  }

  @override
  void setPaused(Object s, bool paused) => sr_set_paused(_p(s), paused);

  @override
  void resize(Object s, int w, int h) => sr_resize(_p(s), w, h);

  @override
  void setShader(Object s, String source, ShaderLang lang) =>
      _cstr(source, (p) => sr_set_shader(_p(s), p, lang.index));

  @override
  void setFps(Object s, int fps) => sr_set_fps(_p(s), fps);

  @override
  void destroy(Object s) => sr_destroy(_p(s));
}

/// One native renderer whose texture many [ShaderView]s paint at once.
///
/// Created when the first view is visible, paused when none is, and destroyed
/// after [idleGrace] without any mounted view.
class SharedShaderSurface extends ChangeNotifier with WidgetsBindingObserver {
  SharedShaderSurface({
    SurfaceBackend? backend,
    this.idleGrace = const Duration(seconds: 30),
    this.pollEvery = const Duration(milliseconds: 200),
  }) : _backend = backend ?? const _NativeBackend();

  static final SharedShaderSurface instance = SharedShaderSurface();

  final SurfaceBackend _backend;
  final Duration idleGrace;
  final Duration pollEvery;

  final Map<Object, bool> _views = {};
  Object? _surface;
  bool _creating = false;
  int _textureId = -1;
  (int, int) _size = (0, 0);
  Timer? _poll;
  Timer? _idle;
  String? _error;
  bool? _sentPaused;
  bool _foreground = true;
  bool _observing = false;

  String _source = '';
  ShaderLang _lang = ShaderLang.wgsl;
  int _fps = 30;
  ValueChanged<String>? _onError;

  int get textureId => _textureId;
  int get mountedViews => _views.length;
  int get visibleViews => _views.values.where((v) => v).length;
  bool get running => _surface != null;
  bool get paused => _sentPaused ?? true;

  void configure({
    required String source,
    ShaderLang lang = ShaderLang.wgsl,
    int fps = 30,
    ValueChanged<String>? onError,
  }) {
    _onError = onError;
    final s = _surface;
    if (s != null) {
      if (source != _source || lang != _lang) {
        _error = null;
        _backend.setShader(s, source, lang);
      }
      if (fps != _fps) _backend.setFps(s, fps);
    }
    _source = source;
    _lang = lang;
    _fps = fps;
  }

  /// A view reports its state on every frame it is built; [size] is in
  /// physical pixels at render scale.
  void update(Object view, {required bool visible, required (int, int) size}) {
    _views[view] = visible;
    _idle?.cancel();
    _idle = null;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    final s = _surface;
    if (s == null) {
      if (visible && !_creating && _source.isNotEmpty) _create(size);
    } else if (visible && _size != size) {
      _size = size;
      _backend.resize(s, size.$1, size.$2);
    }
    _syncPaused();
  }

  void remove(Object view) {
    if (_views.remove(view) == null) return;
    _syncPaused();
    if (_views.isEmpty && _surface != null) {
      _idle?.cancel();
      _idle = Timer(idleGrace, _destroy);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPaused();
  }

  void _syncPaused() {
    final s = _surface;
    if (s == null) return;
    final p = visibleViews == 0 || !_foreground;
    if (p == _sentPaused) return;
    _sentPaused = p;
    _backend.setPaused(s, p);
  }

  Future<void> _create((int, int) size) async {
    _creating = true;
    try {
      final s = await _backend.create(
        _source,
        _lang,
        size.$1,
        size.$2,
        _fps,
      );
      if (s == null) {
        _onError?.call('The renderer failed to start.');
        return;
      }
      if (_views.isEmpty && _idle == null) {
        _backend.destroy(s);
        return;
      }
      _surface = s;
      _size = size;
      _sentPaused = null;
      _syncPaused();
      _poll = Timer.periodic(pollEvery, (_) => _check());
    } finally {
      _creating = false;
    }
  }

  void _check() {
    final s = _surface;
    if (s == null) return;
    if (_textureId < 0) {
      final id = _backend.textureId(s);
      if (id >= 0) {
        _textureId = id;
        notifyListeners();
      }
    }
    final err = _backend.error(s);
    if (err != null && err != _error) {
      _error = err;
      _onError?.call(err);
    }
  }

  void _destroy() {
    _idle = null;
    final s = _surface;
    if (s == null || _views.isNotEmpty) return;
    _poll?.cancel();
    _poll = null;
    _backend.destroy(s);
    _surface = null;
    _sentPaused = null;
    _textureId = -1;
    _size = (0, 0);
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
    notifyListeners();
  }
}

/// Paints [surface]'s texture, filling its box with cover fit. Safe to mount
/// in several routes at once.
class ShaderView extends StatefulWidget {
  const ShaderView({
    super.key,
    required this.source,
    this.lang = ShaderLang.wgsl,
    this.fps = 30,
    this.scale = .5,
    this.onError,
    this.surface,
  });

  final String source;
  final ShaderLang lang;
  final int fps;
  final double scale;
  final ValueChanged<String>? onError;
  final SharedShaderSurface? surface;

  @override
  State<ShaderView> createState() => _ShaderViewState();
}

class _ShaderViewState extends State<ShaderView> {
  SharedShaderSurface get _s => widget.surface ?? SharedShaderSurface.instance;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final s = _s;
    s.removeListener(_changed);
    s.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!shaderSurfaceSupported) return const SizedBox.expand();
    final s = _s;
    final media = MediaQuery.of(context);
    final visible = TickerMode.valuesOf(context).enabled &&
        !media.disableAnimations;
    final dpr = media.devicePixelRatio;
    final size = (
      (media.size.width * dpr * widget.scale).round().clamp(1, 4096),
      (media.size.height * dpr * widget.scale).round().clamp(1, 4096),
    );
    s.configure(
      source: widget.source,
      lang: widget.lang,
      fps: widget.fps,
      onError: widget.onError,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) s.update(this, visible: visible, size: size);
    });
    if (s.textureId < 0) return const SizedBox.expand();
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: media.size.width,
          height: media.size.height,
          child: Texture(
            textureId: s.textureId,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    );
  }
}
