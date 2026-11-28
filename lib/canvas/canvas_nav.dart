import 'package:flutter/material.dart';

import '../motion_routes.dart';
import '../media_views.dart' show DaemonScope;
import '../panel.dart';
import '../platform.dart';
import 'canvas_screen.dart';

bool _inShell(BuildContext c) => !kMobile && ShellPanelScope.maybeOf(c) != null;

/// Opens a canvas: a tab in the desktop shell, a full page on phone. Without
/// [canvasId] it opens the workspace canvas, optionally focusing a frame,
/// element and revision.
void openCanvas(
  BuildContext c, {
  String? canvasId,
  String? title,
  String? frameId,
  String? elId,
  int? rev,
}) {
  final daemon = DaemonScope.maybeOf(c) ?? DaemonScope.current;
  Widget screen(VoidCallback? close) => CanvasScreen(
        daemonClient: daemon,
        canvasId: canvasId,
        title: title,
        initialFrameId: frameId,
        initialElId: elId,
        initialRev: rev,
        onClose: close,
      );
  if (_inShell(c)) {
    presentScreen<void>(
      c,
      style: PanelStyle.drawer,
      purpose: ShellPanelPurpose.canvas,
      panelId: canvasId ?? 'workspace',
      title: title,
      builder: (_, close) => screen(close),
    );
    return;
  }
  Navigator.of(c).push<void>(
    AppPageRoute<void>(builder: (_) => screen(null)),
  );
}
