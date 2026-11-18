import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/composer_pill.dart';
import 'package:snippet/media_views.dart';

// The review pill once wrapped itself and overflowed the stack on every layout.
void main() {
  for (final rec in [true, false]) {
    testWidgets('voice pill lays out (recording=$rec)', (t) async {
      final buf = WaveBuffer();
      for (var i = 0; i < 80; i++) {
        buf.add(0.3 + (i % 5) / 10);
      }
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 390,
              child: ComposerVoicePill(
                recording: rec,
                time: '0:07',
                wave: LiveRecordingWave(
                    buffer: buf, live: rec, progress: rec ? null : 0.3),
                playing: false,
                onDiscard: () {},
                onPlay: () {},
                onStop: () {},
                onSend: () {},
                onSeek: rec ? null : (_) {},
                onMore: rec ? null : () {},
              ),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
    });
  }
}
