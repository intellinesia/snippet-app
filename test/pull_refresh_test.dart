import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/pull_refresh.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('a reversed list refreshes from its oldest end on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var refreshes = 0;
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PullToRefresh(
              reverse: true,
              onRefresh: () async => refreshes++,
              child: ListView.builder(
                controller: scroll,
                reverse: true,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 40,
                itemBuilder: (_, i) =>
                    SizedBox(height: 60, child: Text('m$i')),
              ),
            ),
          ),
        ));
        // Pulling up from the newest end, by the composer, does nothing.
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(refreshes, 0);

        // A fling that coasts into the oldest message does not refresh.
        await tester.fling(find.byType(ListView), const Offset(0, 900), 6000);
        await tester.pumpAndSettle();
        expect(scroll.offset, scroll.position.maxScrollExtent);
        expect(refreshes, 0);

        // Pulling down past it does.
        await tester.timedDrag(find.byType(ListView), const Offset(0, 300),
            const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(refreshes, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
