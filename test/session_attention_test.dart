import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/session_attention.dart';
import 'package:snippet/models.dart';

class _Client extends DaemonClient {
  _Client(this.list) : super('https://daemon.invalid', 'tok');
  final List<SessionInfo> list;
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => list;
}

SessionInfo _s(String id, [Map<String, dynamic>? attention]) =>
    SessionInfo.fromJson({
      'id': id,
      'title': id,
      'folder': '/tmp',
      'status': attention == null ? 'idle' : 'waiting_for_input',
      if (attention != null) 'attention': attention,
    });

void main() {
  test('a request is outdated once its session stops waiting on it', () async {
    final client = _Client([
      _s('idle'),
      _s('asking', {'type': 'question', 'id': '3:t'}),
    ]);
    Future<bool> out(String s, String type, [String id = '']) =>
        SessionAttentionProbe.isOutdated(client,
            session: s, type: type, id: id);
    expect(await out('idle', 'question'), isTrue);
    expect(await out('asking', 'question'), isFalse);
    expect(await out('asking', 'question', '3:t'), isFalse);
    expect(await out('asking', 'question', '2:t'), isTrue);
    expect(await out('asking', 'approval'), isTrue);
    expect(await out('gone', 'question'), isFalse);
  });
}
