import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar_mode.dart';

void main() {
  // Tests default to the phone platform; these are about the desktop sidebar.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('the phone has one home list and desktop keeps its sidebar mode',
      () async {
    SharedPreferences.setMockInitialValues({});
    sidebarAgentsFirst.value = false;
    await loadSidebarAgentsFirst();
    expect(homeFirstTab(), MobileHome.chats);
    setSidebarAgentsFirst(true);
    expect(homeFirstTab(), MobileHome.agents);
    await Future<void>.delayed(Duration.zero);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('desktop_sidebar_agents_first'), isTrue);
  });

  test('an earlier "Open on" choice carries over to the desktop sidebar',
      () async {
    SharedPreferences.setMockInitialValues({'home_agents_first': true});
    sidebarAgentsFirst.value = false;
    await loadSidebarAgentsFirst();
    expect(sidebarAgentsFirst.value, isTrue);
  });
}
