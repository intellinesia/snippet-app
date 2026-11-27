import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session_fork.dart';
import 'package:snippet/screens/session_handoff.dart';
import 'package:snippet/screens/spec_bar.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('http://127.0.0.1:1', 'test');
  String? handed;
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        for (final n in ['Sashy', 'Rook'])
          CoordinationAgent.fromJson({
            'id': n.toLowerCase(),
            'display_name': n,
            'status': 'active',
            'kind': 'agent'
          })
      ];
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [];
  @override
  Future<Map<String, dynamic>> handOffSession(String session, String toAgent,
      {String? note}) async {
    handed = toAgent;
    return {};
  }
}

Widget _wrap(double scale, Widget body) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: ch!),
      home: Scaffold(
          body: Column(children: [
        const SpecBar(title: 'Hand off session', subtitle: 'Wire the wake'),
        Expanded(child: SingleChildScrollView(child: body)),
      ])),
    );

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('hand off w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        final c = _Client();
        await t.pumpWidget(_wrap(
            s, SessionHandOffPanel(client: c, sessionId: 'x', spec: true)));
        await t.pump();
        await t.pump();
        expect(t.takeException(), isNull);
        final row = t.getRect(find.bySemanticsLabel('Sashy'));
        expect(row.width, w - 16);
        expect(row.height, greaterThanOrEqualTo(48));
        // Disabled until chosen.
        expect(find.bySemanticsLabel('Hand off'), findsOneWidget);
        await t.tap(find.text('Sashy'));
        await t.pump();
        expect(find.text('Selected'), findsOneWidget);
        final btn = t.getRect(find.bySemanticsLabel('Hand off to Sashy'));
        expect(btn.width, w - 32);
        expect(btn.height, greaterThanOrEqualTo(48));
        await t.tap(find.text('Hand off'));
        await t.pump();
        expect(c.handed, 'sashy');
      });
      testWidgets('fork sheet w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        bool? chose;
        await t.pumpWidget(_wrap(
            s,
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SessionForkPanel(
                    fromLabel: 'Keep going with the wake wiring please ' * 4,
                    onChoose: (v, _) => chose = v))));
        expect(t.takeException(), isNull);
        final fork = t.getRect(find.bySemanticsLabel('Fork'));
        expect(fork.width, w - 32);
        expect(fork.height, greaterThanOrEqualTo(48));
        expect(
            t
                .getRect(find.bySemanticsLabel('Fork from the start instead'))
                .height,
            greaterThanOrEqualTo(48));
        await t.tap(find.text('Fork from the start instead'));
        expect(chose, false);
      });
      testWidgets('fork from latest offers one button w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        String? title;
        await t.pumpWidget(_wrap(
            s,
            SessionForkPanel(
                fromLabel: 'the latest message',
                latest: true,
                onChoose: (_, v) => title = v)));
        expect(find.text('Fork from the start instead'), findsNothing);
        await t.enterText(find.byType(TextField), 'Tray retry');
        await t.tap(find.text('Fork'));
        expect(title, 'Tray retry');
      });
    }
  }
}
