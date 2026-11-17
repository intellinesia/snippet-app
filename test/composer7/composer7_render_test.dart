import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/composer_pill.dart';

import 'composer7_harness.dart';

// Renders the round 7 composer states to R7_SHOTS for review by eye.
void main() {
  testWidgets('phone: empty', (tester) async {
    final h = Harness();
    await h.pump(tester, {'status': 'idle', 'events': chatEvents});
    await h.shoot(tester, 'empty');
    await h.done(tester);
  });

  testWidgets('phone: typing', (tester) async {
    final h = Harness();
    await h.pump(tester, {'status': 'idle', 'events': chatEvents});
    await tester.enterText(find.byType(TextField).last,
        'Can you also check the 360 width before you open it');
    await h.settle(tester);
    await h.shoot(tester, 'typing');
    await h.done(tester);
  });

  testWidgets('phone: tray', (tester) async {
    final h = Harness();
    await h.pump(tester, {
      'status': 'idle',
      'events': chatEvents,
      'lanes': [
        {'id': 'l1', 'title': 'Goldens', 'status': 'running', 'started_at': ''},
        {'id': 'l2', 'title': 'Notes', 'status': 'running', 'started_at': ''},
      ],
    });
    await tester.tap(find.bySemanticsLabel('Actions'));
    await h.settle(tester);
    await h.shoot(tester, 'tray');
    await h.done(tester);
  });

  testWidgets('phone: running, typing', (tester) async {
    final h = Harness();
    await h.pump(tester, {'status': 'running', 'events': chatEvents});
    await tester.enterText(find.byType(TextField).last,
        'Can you also check the 360 width before you open it');
    await h.settle(tester);
    await h.shoot(tester, 'runtyping');
    await h.done(tester);
  });

  testWidgets('phone: running, empty', (tester) async {
    final h = Harness();
    await h.pump(tester, {'status': 'running', 'events': chatEvents});
    await h.shoot(tester, 'running');
    await h.done(tester);
  });

  for (final n in [1, 3]) {
    testWidgets('phone: $n queued', (tester) async {
      final h = Harness();
      await h.pump(tester, {
        'status': 'running',
        'events': chatEvents,
        'queued_inputs': queued(n),
      });
      await h.shoot(tester, 'queued$n');
      await h.done(tester);
    });
  }

  testWidgets('phone: voice', (tester) async {
    final h = Harness();
    await h.pump(tester, {'status': 'idle', 'events': chatEvents});
    await tester.tap(find.byType(ComposerMorphButton));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await h.shoot(tester, 'voice');
    await h.done(tester);
  });

  testWidgets('desktop: running, 3 queued', (tester) async {
    final h = Harness();
    await h.pump(
        tester,
        {
          'status': 'running',
          'events': chatEvents,
          'queued_inputs': queued(3),
        },
        desktop: true);
    await h.shoot(tester, 'desk');
    await h.done(tester);
  });
}
