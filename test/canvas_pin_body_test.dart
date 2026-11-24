import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';

// Own file: the daemon client's HTTP client is static and must stay real here.
void main() {
  test('postCanvasPin sends canvas_id in body and query', () async {
    final old = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = old);
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    Uri? uri;
    Map<String, dynamic>? body;
    server.listen((req) async {
      uri = req.uri;
      body = jsonDecode(await utf8.decoder.bind(req).join())
          as Map<String, dynamic>;
      req.response
        ..statusCode = 200
        ..write('{"id":"p1"}');
      await req.response.close();
    });
    final c = DaemonClient('http://127.0.0.1:${server.port}', 'tok');
    await c.postCanvasPin({'frame_id': 'se-03-d', 'text': 'hi'},
        canvasId: 'screens-all-v17');
    expect(uri!.queryParameters['canvas_id'], 'screens-all-v17');
    expect(body!['canvas_id'], 'screens-all-v17');
    expect(body!['frame_id'], 'se-03-d');
  });
}
