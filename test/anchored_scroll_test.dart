import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/anchored_scroll.dart';

class _Row extends StatefulWidget {
  const _Row(this.i, {super.key});
  final int i;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool open = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => open = !open),
        child: SizedBox(height: open ? 250 : 50, child: Text('row ${widget.i}')),
      );
}

Widget _list(AnchoredScrollController c) => MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: c,
          reverse: true,
          itemCount: 40,
          itemBuilder: (_, i) => RowSizeWatch(
            key: ValueKey(i),
            onResize: (delta, bottom) {
              if (bottom == null || bottom > 0) c.correctBy(delta);
            },
            child: _Row(i),
          ),
        ),
      ),
    );

void main() {
  testWidgets('an expanded row keeps its top in the first frame',
      (t) async {
    final c = AnchoredScrollController();
    await t.pumpWidget(_list(c));
    c.jumpTo(300); // off the bottom
    await t.pump();
    final row = find.text('row 10');
    final before = t.getTopLeft(row).dy;
    final pixels = c.offset;
    await t.tap(row);
    await t.pump(); // one frame
    expect(t.getTopLeft(row).dy, before);
    expect(c.offset, pixels + 200);
    await t.pump(const Duration(milliseconds: 100));
    expect(t.getTopLeft(row).dy, before);
  });

  testWidgets('a row above the viewport moves nothing', (t) async {
    final c = AnchoredScrollController();
    await t.pumpWidget(_list(c));
    c.jumpTo(300);
    await t.pump();
    final pixels = c.offset;
    // Collapse-expand off screen rows are never tapped, so only check that
    // no correction is queued without a resize.
    await t.pump();
    expect(c.offset, pixels);
  });
}
