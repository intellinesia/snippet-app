import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat_scene.dart';
import 'package:snippet_render/snippet_render.dart';

// The native renderer is not built on Windows, so checkShader is a no-op there.
void main() {
  if (!shaderSurfaceSupported) return;
  test('every built-in scene compiles', () {
    for (final scene in [...ChatScene.presets.keys, 'aurora-legacy']) {
      expect(checkShader(sceneSource(scene), ShaderLang.wgsl), isNull,
          reason: scene);
    }
  });

  test('scenes compile with backdrop params', () {
    const params = {'speed': 2.5, 'intensity': 9, 'tint': '#FF8800'};
    for (final scene in ChatScene.presets.keys) {
      final src = sceneSource(scene, params);
      expect(checkShader(src, ShaderLang.wgsl), isNull, reason: scene);
      expect(src, contains('SPEED = 2.500'));
      expect(src, contains('INTENSITY = 3.000'));
      expect(src, contains('ACCENT = vec3<f32>(1.000, 0.533, 0.000)'));
    }
  });

  test('a broken shader reports the compiler error', () {
    final err = checkShader(
        'fn main_image(p: vec2<f32>) -> vec4<f32> { return nope; }',
        ShaderLang.wgsl);
    expect(err, contains('nope'));
    expect(
        checkShader(
            'void mainImage(out vec4 c, in vec2 p) { c = vec4(p / iResolution.xy, 0.5 + 0.5 * sin(iTime), 1.0); }',
            ShaderLang.glsl),
        isNull);
  });
}
