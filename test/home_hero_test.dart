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

  testWidgets('hero holds its reading, a tap advances, a return reshuffles',
      (tester) async {
    Widget app(bool shown, int visit) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: TickerMode(
              enabled: shown,
              child: HomeHero(stats: stats, visit: visit),
            ),
          ),
        );
    await tester.pumpWidget(app(true, 0));
    final first = shown(tester);
    final i = stats.indexWhere((s) => s.label == first);

    await tester.pump(const Duration(minutes: 5));
    expect(shown(tester), first);

    await tester.tap(find.byType(HomeHero));
    await tester.pumpAndSettle();
    expect(shown(tester), stats[(i + 1) % 3].label);

    final seen = <String>{};
    for (var v = 1; v <= 40; v++) {
      await tester.pumpWidget(app(false, v));
      await tester.pumpWidget(app(true, v));
      await tester.pumpAndSettle();
      seen.add(shown(tester));
    }
    expect(seen.length, greaterThan(1));
  });

  test('compact values fit the dot matrix', () {
    expect(heroCompact(7), '07');
    expect(heroCompact(16840), '16.8k');
    expect(heroCompact(4200000), '4.2M');
    expect(heroCompact(168000), '168k');
  });
}
