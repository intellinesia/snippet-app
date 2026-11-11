import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/coordination/coordination_thread_state.dart';
import 'package:snippet/models.dart';

class _Client extends DaemonClient {
  _Client() : super('http://localhost:1', 't');
  int calls = 0;

  @override
  Future<List<CoordinationEvent>> coordinationEvents(String threadId,
      {int afterSequence = 0, int limit = 100}) async {
    calls++;
    return const [];
  }
}

void main() {
  testWidgets('attachLive refreshes on a 45 s timer until disposed',
      (tester) async {
    final client = _Client();
    final state = CoordinationThreadState(client: client, threadId: 't');
    state.attachLive();
    await tester.pump(const Duration(seconds: 44));
    expect(client.calls, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(client.calls, 1);
    state.attachLive();
    await tester.pump(const Duration(seconds: 46));
    expect(client.calls, 2);
    state.dispose();
    await tester.pump(const Duration(seconds: 100));
    expect(client.calls, 2);
  });
}
