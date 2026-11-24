import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/phone_tool_bar.dart';
import 'package:snippet/theme.dart';

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('bars w=$w s=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, ch) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: ch!),
          home: Scaffold(
            body: Column(children: [
              PhoneBar(title: 'A plain a very long title that must end with an ellipsis here', onBack: () {}),
              PhoneBar(
                  title: 'Agent',
                  subtitle: 'A long subtitle that wraps onto a second line at large text sizes',
                  status: 'Working, 4m',
                  onBack: () {},
                  trailing: [PhoneBarAction('more', 'More', () {})]),
              PhoneLargeBar(title: 'Large', status: 'Working, 4m', onBack: () {}),
            ]),
          ),
        ));
        expect(tester.takeException(), isNull);
        final backs = find.bySemanticsLabel('Back');
        final b = tester.getRect(backs.first);
        final more = tester.getRect(find.bySemanticsLabel('More'));
        final title = tester.getTopLeft(find.text('Agent'));
        final large = tester.getTopLeft(find.text('Large'));
        final bars = tester.widgetList<Container>(find.byType(Container));
        // ignore: avoid_print
        print('w=$w s=$scale back=${b.size}@${b.left} more.right=${w - more.right} titleX=${title.dx} largeX=${large.dx}');
        expect(b.size, const Size(48, 48));
        expect(b.left, 0);
        expect(w - more.right, 4);
        expect(title.dx, 56);
        expect(large.dx, 16);
        expect(find.text('Working, 4m'), findsNWidgets(2));
        expect(bars, isNotEmpty);
      });
    }
  }
}
