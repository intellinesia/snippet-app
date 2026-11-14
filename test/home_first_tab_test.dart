import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar_mode.dart';

void main() {
  test('the Open on setting picks the start tab and is saved', () async {
    SharedPreferences.setMockInitialValues({});
    await loadSidebarAgentsFirst();
    expect(homeFirstTab(), MobileHome.chats);
    setHomeAgentsFirst(true);
    expect(homeFirstTab(), MobileHome.agents);
    await Future<void>.delayed(Duration.zero);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('home_agents_first'), isTrue);
  });

  test('an earlier desktop choice carries over', () async {
    SharedPreferences.setMockInitialValues({'desktop_sidebar_agents_first': true});
    await loadSidebarAgentsFirst();
    expect(homeAgentsFirst.value, isTrue);
  });
}
