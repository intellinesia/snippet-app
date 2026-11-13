import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/file_viewer.dart';

class _FakeClient extends DaemonClient {
  _FakeClient() : super('https://daemon.invalid', 'test-token');

  @override
  Future<FileContent> readFile(String path) async => FileContent.fromJson(
      {'path': path, 'content': 'hello', 'size': 5, 'hash': 'h'});
}

void main() {
  // The Mac window bar carries no file actions, so the embedded viewer must.
  testWidgets('embedded file tab offers Edit and Download on macOS',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(MaterialApp(
        home: FileViewer(
            client: _FakeClient(),
            path: '/w/notes.md',
            name: 'notes.md',
            embedded: true)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('embedded file tab leaves actions to the tab strip on Linux',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(MaterialApp(
        home: FileViewer(
            client: _FakeClient(),
            path: '/w/notes.md',
            name: 'notes.md',
            embedded: true)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
