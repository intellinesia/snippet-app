import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/notification_card.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  for (final size in [const Size(1440, 900), const Size(1100, 800)]) {
    testWidgets('desktop toast clears chrome at ${size.width.toInt()}',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      DaemonClient.wsConnector =
          (uri, {connectTimeout, pingInterval}) => _Socket();
      SharedPreferences.setMockInitialValues({
        'instances':
            '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      foregroundNotifications.drain();
      foregroundNotifications.add({
        'title': 'Lead',
        'kind': 'idle',
        'body': 'Finished and standing by after a very long status line',
      });
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: const NotificationPopovers(child: DesktopShell())));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      // Desktop never renders in-app toasts (asks sit on the composer).
      expect(find.byType(NotificationMessageCard), findsNothing);
      final out = <String, Rect>{};
      // Every window-bar control (tab strip, back/forward, pane header tools).
      for (final e in find.byType(Tooltip).evaluate()) {
        final f = find.byWidget(e.widget);
        final r = tester.getRect(f);
        if (r.top < 48 && r.width > 0) {
          out['${(e.widget as Tooltip).message}'] = r;
        }
      }
      expect(out, isNotEmpty);
      // ignore: avoid_print
      print('DESKTOP ${size.width.toInt()} toasts=0 chrome=$out');
      // Anchor for the call card, the one overlay desktop can show: top 52.
      for (final e in out.entries) {
        expect(e.value.bottom, lessThanOrEqualTo(52), reason: e.key);
      }
      foregroundNotifications.drain();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      DaemonClient.wsConnector = null;
      debugDefaultTargetPlatformOverride = null;
    });
  }
}


class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _Sink(_controller.sink);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _Sink implements WebSocketSink {
  final StreamSink _sink;
  _Sink(this._sink);
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => _sink.close();
  @override
  Future get done => _sink.done;
}
