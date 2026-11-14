import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat_scene.dart';
import 'package:snippet_render/snippet_render.dart';

void main() {
  test('every built-in scene compiles', () {
    for (final scene in ChatScene.presets.keys) {
      expect(checkShader(sceneSource(scene), ShaderLang.wgsl), isNull,
          reason: scene);
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
