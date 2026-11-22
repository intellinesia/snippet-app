import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

class _ArtifactClient extends DaemonClient {
  _ArtifactClient({required this.onArtifacts})
      : super('http://127.0.0.1:1', 'test');

  final Future<List<ArtifactInfo>> Function(int attempt) onArtifacts;
  int attempts = 0;

  @override
  Future<List<ArtifactInfo>> artifacts(String sessionId) =>
      onArtifacts(++attempts);
}

void main() {
  testWidgets(
      'ArtifactRow image keeps a 150pt shimmer+spinner slot, never renders fake skeleton bars, and offers retry on failure',
      (tester) async {
    final first = Completer<List<ArtifactInfo>>();
    final second = Completer<List<ArtifactInfo>>();
    final client = _ArtifactClient(
      onArtifacts: (n) => n == 1 ? first.future : second.future,
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ArtifactRow(
          client: client,
          session: 's1',
          id: 'a1',
          version: 1,
          title: 'First screen round 5',
          kind: 'image',
          caption: '',
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(Skeleton), findsNothing);
    expect(find.byType(LoadingBlock), findsOneWidget);
    expect(find.byType(DelayedSpinner), findsOneWidget);
    final loadingHeight = tester.getSize(find.byType(ArtifactRow)).height;

    // Failing the metadata fetch keeps the slot height and surfaces Retry.
    first.completeError(Exception('timeout'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Couldn’t load preview'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.getSize(find.byType(ArtifactRow)).height,
        closeTo(loadingHeight, 1.0));

    // Tapping Retry issues a second request and returns to the calm loader.
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(client.attempts, 2);
    expect(find.byType(LoadingBlock), findsOneWidget);

    second.complete(const []);
    await tester.pump();
  });

  testWidgets('ArtifactRow and ArtifactInline text previews use compact LoadingInline instead of tall skeleton blocks',
      (tester) async {
    final pending = Completer<List<ArtifactInfo>>();
    final client = _ArtifactClient(onArtifacts: (_) => pending.future);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtifactRow(
              client: client,
              session: 's1',
              id: 'm1',
              version: 1,
              title: 'Spec notes',
              kind: 'markdown',
              caption: '',
            ),
            ArtifactInline(
              client: client,
              session: 's1',
              id: 'm2',
              version: 1,
              title: 'Inline spec',
              kind: 'markdown',
              caption: '',
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(Skeleton), findsNothing);
    expect(find.byType(LoadingBlock), findsNothing);
    expect(find.byType(LoadingInline), findsNWidgets(2));
    for (final el in find.byType(LoadingInline).evaluate()) {
      final box = el.renderObject! as RenderBox;
      expect(box.size.height, lessThan(60));
    }
  });
}
