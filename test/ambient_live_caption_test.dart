import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/ambient/live_caption.dart';
import 'package:snippet/screens/mission_control/widgets/ambient_stage.dart';
import 'package:snippet/swr.dart';

void main() {
  tearDown(() {
    LiveCaptionFeed.instance.text.value = null;
    LiveCaptionFeed.instance.lastFinal.value = null;
  });

  testWidgets('a final ambient_live event sets lastFinal', (tester) async {
    final feed = LiveCaptionFeed(
        finalHold: const Duration(milliseconds: 50),
        partialHold: const Duration(milliseconds: 50));
    feed.apply({'kind': 'ambient_live', 'text': 'hello there', 'final': false});
    expect(feed.text.value, 'hello there');
    expect(feed.lastFinal.value, isNull);
    feed.apply({'kind': 'ambient_live', 'text': 'hello there', 'final': true});
    expect(feed.lastFinal.value, 'hello there');
    await tester.pump(const Duration(milliseconds: 80));
    expect(feed.text.value, isNull);
    expect(feed.lastFinal.value, 'hello there');
  });

  testWidgets('DeviceEventHub feeds ambient_live frames into LiveCaptionFeed',
      (tester) async {
    final hub = DeviceEventHub.local();
    hub.add({'kind': 'ambient_live', 'text': 'hub words', 'final': false});
    expect(LiveCaptionFeed.instance.text.value, 'hub words');
    await tester.pump(const Duration(seconds: 5));
    expect(LiveCaptionFeed.instance.text.value, isNull);
  });

  testWidgets('AmbientHeardLine shows the live text, then the last final',
      (tester) async {
    final feed = LiveCaptionFeed(
        finalHold: const Duration(milliseconds: 100),
        partialHold: const Duration(milliseconds: 100));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AmbientHeardLine(wide: false, feed: feed))));
    expect(find.textContaining('hello'), findsNothing);

    feed.apply({'text': 'hello there', 'final': false});
    await tester.pump();
    expect(find.text('\u201Chello there\u201D'), findsOneWidget);

    feed.apply({'text': 'all done', 'final': true});
    await tester.pump();
    expect(find.text('\u201Call done\u201D'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('\u201Call done\u201D'), findsOneWidget);
  });
}
