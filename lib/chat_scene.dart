import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet_render/snippet_render.dart';

import 'ambient_loop.dart';
import 'platform.dart';
import 'theme.dart';

// The ambient tick draws the scene too, so both share one redraw.
void _kickScene() {
  SharedShaderSurface.instance.kick();
  ShaderSurface.kickAll();
}

/// An animated shader behind the chat, drawn by the native renderer.
class ChatScene extends ChangeNotifier {
  ChatScene._();
  static final ChatScene instance = ChatScene._();

  static const _key = 'chat_scene';
  static const none = 'none';
  static const presets = {'aurora': 'Aurora', 'stars': 'Stars'};

  String _scene = none;
  String? _error;
  bool _loaded = false;
  bool _userChosen = false;
  bool _listeningTheme = false;
  File? _marker;
  bool _armed = false;
  bool _arming = false;

  String get scene => _scene;
  String? get error => _error;
  bool get active => shaderSurfaceSupported && presets.containsKey(_scene);
  bool get userChosen => _userChosen;

  /// Active and safe to start: the crash marker is on disk.
  bool get ready => active && _armed;

  String _themeDefaultScene() {
    final s = ThemeManager.instance.resolved.backdrop.scene;
    return (s == none || presets.containsKey(s)) ? s : none;
  }

  void _ensureThemeListener() {
    if (_listeningTheme) return;
    _listeningTheme = true;
    ThemeManager.instance.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (_userChosen) return;
    final next = _themeDefaultScene();
    if (next == _scene) return;
    _scene = next;
    _error = null;
    _armed = false;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _scene = none;
    _error = null;
    _loaded = false;
    _userChosen = false;
    _armed = false;
    _arming = false;
    notifyListeners();
  }

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    _ensureThemeListener();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      _userChosen = saved != null;
      _scene = saved ?? _themeDefaultScene();
      final dir = (await getApplicationSupportDirectory()).path;
      _marker = File('$dir/chat_scene_starting');
      if (_marker!.existsSync()) {
        _marker!.deleteSync();
        if (_scene != none) {
          _scene = none;
          _error = 'Turned off: the app closed while the scene was starting.';
          _userChosen = true;
          await prefs.setString(_key, none);
        }
      }
    } catch (_) {
      if (!_userChosen) _scene = _themeDefaultScene();
    }
    notifyListeners();
  }

  /// Native code can take the process down; a marker that outlives a crash
  /// lets the next launch switch the scene off instead of crashing again.
  void arm() {
    if (_armed || _arming || !active) return;
    _arming = true;
    try {
      _marker?.writeAsStringSync(_scene, flush: true);
    } catch (_) {}
    _armed = true;
    _arming = false;
    Timer(const Duration(seconds: 5), () {
      try {
        _marker?.deleteSync();
      } catch (_) {}
    });
    scheduleMicrotask(notifyListeners);
  }

  Future<void> set(String scene) async {
    final changed = scene != _scene;
    _userChosen = true;
    _scene = scene;
    if (changed) {
      _error = null;
      _armed = false;
      notifyListeners();
    }
    try {
      (await SharedPreferences.getInstance()).setString(_key, scene);
    } catch (_) {}
  }

  void reportError(String e) {
    _error = e.split('\n').first;
    notifyListeners();
  }
}

String _vec3(Color c) =>
    'vec3<f32>(${c.r.toStringAsFixed(3)}, ${c.g.toStringAsFixed(3)}, ${c.b.toStringAsFixed(3)})';

const _noise = '''
fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}
fn fbm(q: vec2<f32>) -> f32 {
  var p = q;
  var a = 0.5;
  var s = 0.0;
  for (var i = 0; i < 4; i++) {
    s += a * noise(p);
    p = p * 2.03 + vec2<f32>(1.7, 9.2);
    a *= 0.5;
  }
  return s;
}
''';

/// WGSL for [scene], coloured from the current theme.
String sceneSource(String scene) {
  final head = 'const BG = ${_vec3(AppColors.bg)};\n'
      'const ACCENT = ${_vec3(AppColors.accent)};\n'
      'const OK = ${_vec3(AppColors.ok)};\n$_noise';
  return switch (scene) {
    'stars' => '''$head
fn main_image(p: vec2<f32>) -> vec4<f32> {
  let uv = p / u.resolution.y;
  var c = BG + ACCENT * 0.06 * fbm(uv * 1.2 + vec2<f32>(u.time * 0.01, 0.0));
  for (var l = 0; l < 3; l++) {
    let scale = 18.0 + f32(l) * 14.0;
    let drift = vec2<f32>(u.time * (0.004 + f32(l) * 0.003), 0.0);
    let g = (uv + drift) * scale;
    let cell = floor(g);
    let h = hash(cell + f32(l) * 17.0);
    let pos = vec2<f32>(hash(cell + 3.1), hash(cell + 7.7));
    let d = length(fract(g) - pos);
    let twinkle = 0.55 + 0.45 * sin(u.time * (0.6 + h * 1.4) + h * 40.0);
    let star = smoothstep(0.08, 0.0, d) * step(0.86, h) * twinkle;
    c += mix(vec3<f32>(1.0), ACCENT, 0.4) * star * 0.7;
  }
  return vec4<f32>(c, 1.0);
}
''',
    _ => '''$head
fn main_image(p: vec2<f32>) -> vec4<f32> {
  let uv = p / u.resolution.y;
  let t = u.time * 0.035;
  let n = fbm(uv * 1.4 + vec2<f32>(t, -t * 0.6));
  let m = fbm(uv * 2.2 - vec2<f32>(t * 0.7, t) + n);
  let glow = smoothstep(0.35, 0.9, m);
  let band = smoothstep(0.55, 1.0, n);
  let c = mix(BG, ACCENT, glow * 0.45) + OK * band * 0.12;
  return vec4<f32>(c, 1.0);
}
''',
  };
}

/// Fills its box with the chosen scene and a veil that keeps text readable.
class ChatSceneLayer extends StatelessWidget {
  const ChatSceneLayer({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final scene = ChatScene.instance;
    return ListenableBuilder(
      listenable: scene,
      builder: (context, _) {
        if (!scene.active) return const SizedBox.shrink();
        if (!scene.ready) {
          scene.arm();
          return const SizedBox.shrink();
        }
        final bg = AppColors.bg;
        AmbientClock.onTick ??= _kickScene;
        return IgnorePointer(
          child: RepaintBoundary(
            child: Stack(fit: StackFit.expand, children: [
              kMobile
                  ? ShaderView(
                      source: sceneSource(scene.scene),
                      // Aurora is soft, so a third of the pixels look the same.
                      scale: scene.scene == 'aurora' ? 1 / 3 : .5,
                      onError: scene.reportError,
                    )
                  : ShaderSurface(
                      source: sceneSource(scene.scene),
                      onError: scene.reportError,
                    ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      bg.withValues(alpha: 0.15),
                      bg.withValues(alpha: 0.45),
                      bg.withValues(alpha: 0.85),
                    ],
                    stops: const [0, 0.6, 1],
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Puts the scene behind [child] on a phone. The slot is always present so
/// switching the scene never remounts [child].
class SceneBackdrop extends StatelessWidget {
  const SceneBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kMobile) return child;
    // An ancestor backdrop already paints the scene for this page.
    final nested =
        context.getInheritedWidgetOfExactType<_SceneScope>() != null;
    return _SceneScope(
      child: Stack(fit: StackFit.expand, children: [
        if (!nested) const Positioned.fill(child: ChatSceneLayer()),
        child,
      ]),
    );
  }
}

class _SceneScope extends InheritedWidget {
  const _SceneScope({required super.child});

  @override
  bool updateShouldNotify(_SceneScope old) => false;
}
