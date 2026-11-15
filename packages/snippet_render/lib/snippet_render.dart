import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';

import 'src/bindings.dart';

export 'shared_surface.dart';

/// `wgsl` shaders define `fn main_image(p: vec2<f32>) -> vec4<f32>` and read
/// `u.time` and `u.resolution`; `glsl` shaders are Shadertoy's `mainImage`
/// with `iTime` and `iResolution`.
enum ShaderLang { wgsl, glsl }

bool get shaderSurfaceSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isLinux || Platform.isMacOS);

String? _take(Pointer<Char> p) {
  if (p == nullptr) return null;
  final s = p.cast<Utf8>().toDartString();
  sr_free_string(p);
  return s;
}

T _withCstr<T>(String s, T Function(Pointer<Char>) f) {
  final p = s.toNativeUtf8();
  try {
    return f(p.cast());
  } finally {
    malloc.free(p);
  }
}

/// The compiler's message, or null when [source] compiles (or when there is
/// no native renderer on this platform).
String? checkShader(String source, ShaderLang lang) => shaderSurfaceSupported
    ? _take(_withCstr(source, (p) => sr_check(p, lang.index)))
    : null;

/// Draws [source] with the native GPU renderer, filling its box.
class ShaderSurface extends StatefulWidget {
  final String source;
  final ShaderLang lang;
  final int fps;

  /// Render resolution as a share of the box's physical pixels.
  final double scale;
  final bool paused;
  final ValueChanged<String>? onError;

  const ShaderSurface({
    super.key,
    required this.source,
    this.lang = ShaderLang.wgsl,
    this.fps = 20,
    this.scale = .5,
    this.paused = false,
    this.onError,
  });

  @override
  State<ShaderSurface> createState() => _ShaderSurfaceState();

  static final _live = <_ShaderSurfaceState>{};

  /// Draws every running surface now, so it shares a redraw with the caller's.
  static void kickAll() {
    for (final s in _live) {
      s._kick();
    }
  }
}

class _ShaderSurfaceState extends State<ShaderSurface>
    with WidgetsBindingObserver {
  Pointer<Void> _surface = nullptr;
  int _textureId = -1;
  bool _creating = false;
  (int, int) _size = (0, 0);
  Timer? _poll;
  String? _error;
  bool _foreground = true;
  bool? _sentPaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShaderSurface._live.add(this);
  }

  void _kick() {
    if (_surface != nullptr && _sentPaused == false) sr_kick(_surface);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPaused();
  }

  bool get _shouldPause =>
      widget.paused ||
      !_foreground ||
      !TickerMode.valuesOf(context).enabled ||
      MediaQuery.maybeDisableAnimationsOf(context) == true;

  void _syncPaused() {
    if (_surface == nullptr || !mounted) return;
    final p = _shouldPause;
    if (p == _sentPaused) return;
    _sentPaused = p;
    sr_set_paused(_surface, p);
  }

  Future<void> _create((int, int) size) async {
    _creating = true;
    final engine = await EngineContext.instance.getEngineHandle();
    if (!mounted) return;
    _surface = _withCstr(
      widget.source,
      (p) =>
          sr_create(engine, p, widget.lang.index, size.$1, size.$2, widget.fps),
    );
    if (_surface == nullptr) {
      widget.onError?.call('The renderer failed to start.');
      return;
    }
    _size = size;
    _syncPaused();
    _poll = Timer.periodic(const Duration(milliseconds: 200), (_) => _check());
  }

  void _check() {
    if (_surface == nullptr) return;
    if (_textureId < 0) {
      final id = sr_texture_id(_surface);
      if (id >= 0) setState(() => _textureId = id);
    }
    final err = _take(sr_error(_surface));
    if (err != null && err != _error) {
      _error = err;
      widget.onError?.call(err);
    }
  }

  @override
  void didUpdateWidget(ShaderSurface old) {
    super.didUpdateWidget(old);
    if (_surface == nullptr) return;
    if (old.source != widget.source || old.lang != widget.lang) {
      _error = null;
      _withCstr(
        widget.source,
        (p) => sr_set_shader(_surface, p, widget.lang.index),
      );
    }
    if (old.fps != widget.fps) sr_set_fps(_surface, widget.fps);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShaderSurface._live.remove(this);
    _poll?.cancel();
    if (_surface != nullptr) sr_destroy(_surface);
    _surface = nullptr;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!shaderSurfaceSupported) return const SizedBox.expand();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth * dpr * widget.scale).round().clamp(1, 4096);
        final h = (box.maxHeight * dpr * widget.scale).round().clamp(1, 4096);
        if (box.hasBoundedWidth && box.hasBoundedHeight) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_surface == nullptr) {
              if (!_creating) _create((w, h));
            } else if (_size != (w, h)) {
              _size = (w, h);
              sr_resize(_surface, w, h);
            }
            _syncPaused();
          });
        }
        if (_textureId < 0) return const SizedBox.expand();
        return SizedBox.expand(
          child: Texture(
            textureId: _textureId,
            filterQuality: FilterQuality.low,
          ),
        );
      },
    );
  }
}
