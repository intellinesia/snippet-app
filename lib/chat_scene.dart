import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet_render/snippet_render.dart';

import 'theme.dart';

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
  File? _marker;
  bool _armed = false;
  bool _arming = false;

  String get scene => _scene;
  String? get error => _error;
  bool get active => shaderSurfaceSupported && presets.containsKey(_scene);

  /// Active and safe to start: the crash marker is on disk.
  bool get ready => active && _armed;

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _scene = prefs.getString(_key) ?? none;
      final dir = (await getApplicationSupportDirectory()).path;
      _marker = File('$dir/chat_scene_starting');
      final log = File('$dir/chat_scene_crash.log');
      if (_marker!.existsSync()) {
        _marker!.deleteSync();
        if (_scene != none) {
          _scene = none;
          final why = log.existsSync() ? log.readAsStringSync().trim() : '';
          _error = why.isEmpty
              ? 'Turned off: the app closed while the scene was starting.'
              : 'Turned off after a crash: ${why.split('\n').last}';
          await prefs.setString(_key, none);
        }
      }
      if (log.existsSync()) log.deleteSync();
      setCrashLog(log.path);
    } catch (_) {}
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
    if (scene == _scene) return;
    _scene = scene;
    _error = null;
    _armed = false;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_key, scene);
    } catch (_) {}
  }

  void reportError(String e) {
    _error = e;
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
        return IgnorePointer(
          child: RepaintBoundary(
            child: Stack(fit: StackFit.expand, children: [
              ShaderSurface(
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
