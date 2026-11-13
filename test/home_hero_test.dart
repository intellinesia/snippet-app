import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_session_home.dart';
import 'package:snippet/theme.dart';

void main() {
  const stats = [
    HeroStat('03', 'sessions working', '5 idle'),
    HeroStat('4.2M', 'tokens today', '312 calls'),
    HeroStat('62%', '5h limit used'),
  ];

  String shown(WidgetTester tester) => stats
      .firstWhere((s) => find.text(s.label).evaluate().isNotEmpty)
      .label;

  testWidgets('hero rotates on tap and on its timer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: HomeHero(stats: stats)),
    ));
    final first = shown(tester);
    final i = stats.indexWhere((s) => s.label == first);

    await tester.tap(find.byType(HomeHero));
    await tester.pumpAndSettle();
    expect(shown(tester), stats[(i + 1) % 3].label);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(shown(tester), stats[(i + 2) % 3].label);
  });

  test('compact values fit the dot matrix', () {
    expect(heroCompact(7), '07');
    expect(heroCompact(16840), '16.8k');
    expect(heroCompact(4200000), '4.2M');
    expect(heroCompact(168000), '168k');
  });
}
