import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/artifact_grid.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/theme.dart';


class _Client extends DaemonClient {
  _Client(this.list, this.port) : super('https://art7.invalid', 'test-token');

  final List<ArtifactInfo> list;
  final int port;

  @override
  Future<List<ArtifactInfo>> artifacts(String session) async => list;

  @override
  Uri artifactUri(String signedPath) =>
      Uri.parse('http://127.0.0.1:$port$signedPath');
}

ArtifactInfo _art(String id, String title, String kind, int versions,
    DateTime at,
    {String caption = '', String? file}) {
  final sec = at.millisecondsSinceEpoch ~/ 1000;
  return ArtifactInfo.fromJson({
    'id': id,
    'title': title,
    'kind': kind,
    'caption': caption,
    'versions': [
      for (var n = 1; n <= versions; n++)
        {'n': n, 'created_at': sec, 'url': '/a/${file ?? id}.png'},
    ],
  });
}

Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  late HttpServer server;
  setUpAll(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final name = req.uri.pathSegments.last;
      // Any real PNG from the repo stands in for the artifact images.
      final f = File(name == 'goldens.png'
          ? 'assets/icon.png'
          : 'assets/icon_fg.png');
      if (f.existsSync()) {
        req.response.headers.contentType = ContentType('image', 'png');
        req.response.add(f.readAsBytesSync());
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ThemeManager.instance.resetForTest());

  Future<List<ArtifactInfo>> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() => ThemeManager.instance.setName('stone'));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 0, 30);
    final yesterday = today.subtract(const Duration(hours: 6));
    final list = [
      _art('t1', 'Theme token audit', 'csv', 1, yesterday),
      _art('m1', 'Mockup index', 'html', 7, yesterday,
          caption: 'Every round on one page'),
      _art('d1', 'Desktop terminal', 'image', 1, today,
          caption: 'Tabs in the drawer header', file: 'desk'),
      _art('r1', 'Release note for #272', 'markdown', 2, today,
          caption: 'Draft for the changelog'),
      _art('g1', 'Goldens at 390', 'image', 1,
          today.add(const Duration(minutes: 20)),
          file: 'goldens'),
      _art('w1', 'Round 6 review', 'html', 3,
          today.add(const Duration(minutes: 30)),
          caption: 'Lane card and terminal options'),
    ];
    await t.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: AppColors.pageBg,
          body: SessionDeliverables(
            client: _Client(list, server.port),
            session: 's1',
            files: const [(path: '/home/u/round7.md', caption: 'Spec')],
            onClose: () {},
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await t.pump(const Duration(milliseconds: 100));
    }
    return list;
  }

  testWidgets('grid by day with search, chips and a Done pill', (t) async {
    await pump(t);
    expect(find.byType(ArtifactCollection), findsOneWidget);
    expect(find.text('Artifacts and files'), findsOneWidget);
    expect(find.byKey(const ValueKey('deliverables-done')), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.byKey(const ValueKey('artifact-chip-Pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('artifact-chip-Images')), findsOneWidget);
    expect(find.byKey(const ValueKey('artifact-chip-Files')), findsOneWidget);
    final first = t.getTopLeft(find.byKey(const ValueKey('artifact-card-w1')));
    final second = t.getTopLeft(find.byKey(const ValueKey('artifact-card-g1')));
    expect(first.dy, second.dy, reason: 'newest two share the first row');
    expect(second.dx - first.dx,
        t.getSize(find.byKey(const ValueKey('artifact-card-w1'))).width + 10);
    final title = t.widget<Text>(find.text('Round 6 review'));
    expect(title.style!.fontSize, 16);
    expect(t.getSize(find.byKey(const ValueKey('artifact-search'))).height,
        lessThanOrEqualTo(44));
    await _shot(t, 'artifacts-a');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 20));
  });

  testWidgets('chips and search filter the grid', (t) async {
    await pump(t);
    await t.tap(find.byKey(const ValueKey('artifact-chip-Images')));
    await t.pump();
    expect(find.byKey(const ValueKey('artifact-card-g1')), findsOneWidget);
    expect(find.byKey(const ValueKey('artifact-card-w1')), findsNothing);
    await _shot(t, 'artifacts-a-images');
    await t.tap(find.byKey(const ValueKey('artifact-chip-All')));
    await t.enterText(find.byKey(const ValueKey('artifact-search')), 'token');
    await t.pump();
    expect(find.byKey(const ValueKey('artifact-card-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('artifact-card-w1')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 20));
  });

  testWidgets('files keep open and download', (t) async {
    await pump(t);
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('file-download-/home/u/round7.md')), 200,
        scrollable: find
            .descendant(
                of: find.byType(ArtifactCollection),
                matching: find.byType(Scrollable))
            .first);
    await t.pump();
    expect(find.text('round7.md'), findsOneWidget);
    await _shot(t, 'artifacts-a-scrolled');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 20));
  });
}
