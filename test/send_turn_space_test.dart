import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/send_turn_space.dart';

void main() {
  test('spacer fills what the turn leaves and never goes negative', () {
    double h(double tail) =>
        turnSpaceHeight(viewport: 600, paddingVertical: 40, tail: tail);
    expect(h(100), 460);
    expect(h(560), 0);
    expect(h(900), 0);
  });

  testWidgets('sent message sits at the top and the spacer shrinks as it grows',
      (tester) async {
    final anchor = GlobalKey();
    final replyHeight = ValueNotifier<double>(50);
    Widget app({bool active = true}) => Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 600,
            child: ValueListenableBuilder<double>(
              valueListenable: replyHeight,
              builder: (_, h, __) => CustomScrollView(
                reverse: true,
                slivers: [
                  SliverTurnSpace(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                    anchorKey: anchor,
                    active: active,
                    child: SliverList(
                      delegate: SliverChildListDelegate([
                        SizedBox(height: h),
                        KeyedSubtree(
                            key: anchor, child: const SizedBox(height: 40)),
                        const SizedBox(height: 300),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    double anchorTop() => tester.getTopLeft(find.byKey(anchor)).dy;

    await tester.pumpWidget(app());
    expect(anchorTop(), 16);
    replyHeight.value = 200;
    await tester.pump();
    expect(anchorTop(), 16);
    replyHeight.value = 560;
    await tester.pump();
    // Turn taller than the viewport: no spacer, bottom-pinned as usual.
    expect(anchorTop(), -24);

    replyHeight.value = 50;
    await tester.pumpWidget(app(active: false));
    await tester.pump();
    expect(anchorTop(), 600 - 24 - 50 - 40);
  });
}
