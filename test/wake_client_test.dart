import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';

import 'support/wake_fakes.dart';

// Own file: DaemonClient caches one HTTP client per isolate, and widget tests in the same file would install a mock.
void main() {
  group('client', () {
    late HttpServer server;
    late DaemonClient client;
    final seen = <String>[];
    final bodies = <String>[];

    setUp(() async {
      HttpOverrides.global = null;
      seen.clear();
      bodies.clear();
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        seen.add('${req.method} ${req.uri.path}?${req.uri.query}');
        bodies.add(await utf8.decoder.bind(req).join());
        final p = req.uri.path;
        Object body = {};
        var status = 200;
        if (p == '/wakes' && req.method == 'POST') {
          body = wakeJson();
        } else if (p == '/wakes') {
          body = {
            'wakes': [
              wakeJson(),
              {'id': 'o-1', 'kind': 'once', 'owner': 'scout', 'title': 'Ping'},
              {'id': 'w-1', 'kind': 'watch', 'owner': 'scout', 'name': 'ci'},
            ],
            'limits': {}
          };
        } else if (p == '/wakes/runs') {
          body = {
            'runs': [
              {'id': 1, 'status': 'ok', 'fired_at': 5}
            ]
          };
        } else if (p.startsWith('/wakes/')) {
          body = wakeJson();
        } else if (p == '/keep-warm') {
          body = {
            'entries': [keepWarmJson()],
            'limits': {},
            'spend_7d': []
          };
        } else if (p.startsWith('/keep-warm/')) {
          body = keepWarmJson();
        } else if (p.endsWith('/context')) {
          body = {'id': 'scout', 'max_context_tokens': null};
        }
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
      client = DaemonClient('http://127.0.0.1:${server.port}', 'tok');
    });

    tearDown(() => server.close(force: true));

    test('wake calls use the single /wakes resource', () async {
      expect((await client.wakes()).wakes.single.owner, 'scout');
      final book = await client.wakeBook();
      expect(book.every, hasLength(1));
      expect(book.once.single.title, 'Ping');
      expect(book.watches.single.name, 'ci');
      expect(await client.wake('ghost'), isNull);
      await client.setWake('scout', {'schedule': 'daily 09:00'});
      await client.setWake('newcomer', {'schedule': 'daily 09:00'});
      await client.patchWake('wake-scout', {'enabled': false});
      await client.deleteWake('o-1');
      await client.clearWake('scout');
      final runs = await client.wakeRuns(owner: 'scout', limit: 5);
      expect(runs.single.status, 'ok');
      expect(seen, contains('GET /wakes?token=tok&kind=every'));
      expect(seen, contains('GET /wakes/runs?token=tok&owner=scout&limit=5'));
      expect(seen, contains('PATCH /wakes/wake-scout?token=tok'));
      expect(seen, contains('POST /wakes?token=tok'));
      expect(seen, contains('DELETE /wakes/o-1?token=tok'));
      expect(seen, contains('DELETE /wakes/wake-scout?token=tok'));
      expect(seen.where((r) => r.contains('/recurring') || r.contains('/wake-runs') || r.contains('/watches')), isEmpty);
      final post = bodies[seen.indexOf('POST /wakes?token=tok')];
      expect(jsonDecode(post), {'owner': 'newcomer', 'schedule': 'daily 09:00'});
    });

    test('keep-warm and context calls', () async {
      expect((await client.keepWarm()).entries, hasLength(1));
      await client.setKeepWarm('scout', enabled: true, intervalMinutes: 5);
      await client.setAgentContext('scout', 0);
      await client.setAgentContext('scout', 128000);
      final put = seen.indexOf('PUT /keep-warm/scout?token=tok');
      expect(jsonDecode(bodies[put]), {'enabled': true, 'interval_minutes': 5});
      final ctx = [
        for (var i = 0; i < seen.length; i++)
          if (seen[i].startsWith('POST /agents/scout/context')) bodies[i]
      ];
      expect(jsonDecode(ctx[0]), {'max_context_tokens': null});
      expect(jsonDecode(ctx[1]), {'max_context_tokens': 128000});
    });
  });
}
