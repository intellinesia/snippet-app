import 'package:flutter_test/flutter_test.dart';
import 'package:snippet_render/snippet_render.dart';

class _Fake implements SurfaceBackend {
  final log = <String>[];
  int created = 0;

  @override
  Future<Object?> create(String s, ShaderLang l, int w, int h, int fps) async {
    created++;
    log.add('create $w x $h');
    return created;
  }

  @override
  int textureId(Object s) => 7;
  @override
  String? error(Object s) => null;
  @override
  void setPaused(Object s, bool p) => log.add('paused $p');
  @override
  void resize(Object s, int w, int h) => log.add('resize $w x $h');
  @override
  void setShader(Object s, String src, ShaderLang l) => log.add('shader');
  @override
  void setFps(Object s, int fps) => log.add('fps $fps');
  @override
  void kick(Object s) {}
  @override
  void destroy(Object s) => log.add('destroy');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Fake fake;
  late SharedShaderSurface s;
  setUp(() {
    fake = _Fake();
    s = SharedShaderSurface(
      backend: fake,
      idleGrace: const Duration(milliseconds: 50),
      pollEvery: const Duration(milliseconds: 10),
    )..configure(source: 'a');
  });
  tearDown(() => s.dispose());

  test('one renderer serves many views and pauses with none visible',
      () async {
    final a = Object(), b = Object();
    s.update(a, visible: true, size: (100, 200));
    s.update(b, visible: true, size: (100, 200));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(fake.created, 1);
    expect(s.textureId, 7);
    expect(s.visibleViews, 2);
    expect(fake.log.last, 'paused false');

    s.update(a, visible: false, size: (100, 200));
    expect(s.paused, isFalse);
    s.update(b, visible: false, size: (100, 200));
    expect(s.paused, isTrue);
    expect(s.mountedViews, 2);
  });

  test('resizes on a new screen size and destroys after the grace period',
      () async {
    final a = Object();
    s.update(a, visible: true, size: (100, 200));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    s.update(a, visible: true, size: (200, 100));
    expect(fake.log, contains('resize 200 x 100'));

    s.remove(a);
    expect(s.paused, isTrue);
    expect(s.running, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.running, isFalse);
    expect(fake.log.last, 'destroy');
    expect(s.textureId, -1);
  });

  test('a view arriving within the grace period keeps the renderer', () async {
    final a = Object();
    s.update(a, visible: true, size: (100, 200));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    s.remove(a);
    s.update(Object(), visible: true, size: (100, 200));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.running, isTrue);
    expect(fake.created, 1);
    expect(s.paused, isFalse);
  });

  test('changing the shader reaches the live surface', () async {
    s.update(Object(), visible: true, size: (10, 10));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    s.configure(source: 'b');
    expect(fake.log, contains('shader'));
  });
}
