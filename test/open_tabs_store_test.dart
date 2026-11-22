import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/store.dart';

void main() {
  test('chat tabs survive a save and load; the active index follows', () async {
    SharedPreferences.setMockInitialValues({});
    final store = InstanceStore();
    await store.saveOpenTabs(const [
      OpenTabDescriptor(instanceUrl: 'u', title: 'gone'),
      OpenTabDescriptor(instanceUrl: 'u', sessionId: 's', title: 'S'),
      OpenTabDescriptor(instanceUrl: 'u', title: 'Rook', chat: 'agent:rook'),
    ], 2);
    final loaded = await store.loadOpenTabs();
    expect(loaded.tabs.map((t) => t.title), ['S', 'Rook']);
    expect(loaded.tabs.last.chat, 'agent:rook');
    expect(loaded.activeIndex, 1);
  });
}
