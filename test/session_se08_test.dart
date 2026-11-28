import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lanes_phone.dart';
import 'package:snippet/screens/spec_bar.dart';
import 'package:snippet/theme.dart';

Widget _wrap(double scale, Widget body) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: ch!),
      home: Scaffold(body: body),
    );

LaneInfo _lane(String id, String status, {List<LaneActivity> log = const []}) =>
    LaneInfo(
        id: id,
        title: 'Lane $id',
        status: status,
        startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 12)).toIso8601String(),
        handoff: 'Wire the wake path. ' * 20,
        activityLog: log);

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('lanes list w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        final lanes = [_lane('a', 'running'), _lane('b', 'completed'), _lane('c', 'failed')];
        await t.pumpWidget(_wrap(
            s,
            Column(children: [
              SpecBar(title: 'Lanes', subtitle: lanesSubtitle(lanes)),
              Expanded(
                  child: LanesListPhone(
                      groups: [('snippet', 'Snippet', lanes)], onOpen: (_) {})),
            ])));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.text('3 lanes, 1 running'), findsOneWidget);
        for (final w2 in ['Lane a, Running', 'Lane b, Done', 'Lane c, Failed']) {
          final r = t.getRect(find.bySemanticsLabel(RegExp('^$w2')));
          expect(r.height, greaterThanOrEqualTo(56));
          expect(r.width, w - 32);
        }
        expect(find.text('Working'), findsOneWidget);
        expect(find.text('Failed'), findsOneWidget);
      });

      testWidgets('lane detail w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        var stopped = false;
        await t.pumpWidget(_wrap(
            s,
            SingleChildScrollView(
              child: LaneDetailPhone(
                lane: _lane('a', 'running', log: const [
                  LaneActivity(at: '', kind: 'step', text: 'Read the spec'),
                  LaneActivity(at: '', kind: 'step', text: 'Edit the file'),
                ]),
                onOpenTranscript: () {},
                onStop: () async => stopped = true,
              ),
            )));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.text('Report so far'), findsOneWidget);
        final open = t.getRect(find.bySemanticsLabel('Open transcript'));
        expect(open.width, w - 32);
        expect(open.height, greaterThanOrEqualTo(48));
        expect(t.getRect(find.bySemanticsLabel('Stop lane')).height,
            greaterThanOrEqualTo(48));
        await t.tap(find.text('Stop lane'));
        await t.pump(const Duration(milliseconds: 400));
        expect(stopped, false, reason: 'Stop asks first');
        expect(find.text('Stop this lane?'), findsOneWidget);
      });
    }
  }

  testWidgets('detail without steps shows brief only', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(393, 852);
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(1,
        SingleChildScrollView(child: LaneDetailPhone(lane: _lane('a', 'completed')))));
    expect(find.text('Brief'), findsOneWidget);
    expect(find.text('Report so far'), findsNothing);
    expect(find.text('Stop lane'), findsNothing);
  });
}
