import 'package:flutter/material.dart';

import '../media_views.dart' show DaemonScope;
import 'canvas_screen.dart';

/// Opens the in-app Canvas screen, optionally focusing a frame, element, and revision.
void openCanvas(
  BuildContext c, {
  String? frameId,
  String? elId,
  int? rev,
}) {
  final daemon = DaemonScope.maybeOf(c) ?? DaemonScope.current;
  Navigator.of(c).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => CanvasScreen(
        daemonClient: daemon,
        initialFrameId: frameId,
        initialElId: elId,
        initialRev: rev,
      ),
    ),
  );
}
