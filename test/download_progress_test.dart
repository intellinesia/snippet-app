import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';

void main() {
  test('downloads ask for no compression so progress has a total', () async {
    // The test binding answers every request with 400; this needs a real socket.
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final body = List<int>.filled(200000, 65);
    String? asked;
    server.listen((req) async {
      asked = req.headers.value(HttpHeaders.acceptEncodingHeader);
      // Like the daemon: compress when the client allows it, which drops the length.
      if ((asked ?? '').contains('gzip')) {
        req.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        req.response.add(gzip.encode(body));
      } else {
        req.response.contentLength = body.length;
        req.response.add(body);
      }
      await req.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('dl');
    try {
      final client = DaemonClient('http://127.0.0.1:${server.port}', 'tok');
      final totals = <int?>[];
      final out = await client.downloadToFile('/x', File('${dir.path}/x'),
          onProgress: (_, total) => totals.add(total));
      expect(asked, 'identity');
      expect(totals, isNotEmpty);
      expect(totals.every((t) => t == body.length), isTrue);
      expect(await out.length(), body.length);
    } finally {
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
