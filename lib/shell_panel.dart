import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'media_views.dart';
import 'widgets.dart' show ShellPanelRoot;

enum ShellPanelPurpose {
  lanes,
  checkpoints,
  recurring,
  processes,
  files,
  file,
  task,
  tasks,
  agents,
  agent,
  conversation,
  inbox,
  artifact,
  deliverables,
  pullRequests,
  autonomy,
  wakes,
  memory,
  generic,
}

/// Set by the desktop shell so panel content can open a session as a tab.
void Function(DaemonClient client, String sessionId, String title)?
    openSessionInTab;

class ShellPanelRequest {
  ShellPanelRequest(
      {required this.purpose,
      required this.id,
      required this.client,
      this.sessionId,
      this.title,
      this.sidePanel,
      required this.builder});

  final ShellPanelPurpose purpose;
  final String id;
  final DaemonClient? client;
  final String? sessionId;
  final String? title;
  final Widget Function(BuildContext, VoidCallback) builder;

  /// Info docked in the shell's right panel beside this conversation; gets a
  /// callback that closes the conversation tab.
  final Widget Function(BuildContext context, VoidCallback closeTab)? sidePanel;

  /// Set by the shell: reveal or toggle [sidePanel].
  VoidCallback? showSide;
  VoidCallback? toggleSide;
  final Completer<Object?> dismissed = Completer<Object?>();
  final navigatorKey = GlobalKey<NavigatorState>();
  String get key => 'request|${client?.baseUrl}|$sessionId|${purpose.name}|$id';
  String get label =>
      title ??
      switch (purpose) {
        ShellPanelPurpose.task => 'Task',
        ShellPanelPurpose.agents => 'Agents',
        ShellPanelPurpose.conversation => 'Conversation',
        ShellPanelPurpose.deliverables => 'Artifacts & files',
        ShellPanelPurpose.pullRequests => id.isEmpty ? 'Pull requests' : '#$id',
        ShellPanelPurpose.autonomy => 'Automated wakes',
        ShellPanelPurpose.wakes => 'Wakes and keep warm',
        ShellPanelPurpose.lanes => id.isEmpty ? 'Delegated lanes' : 'Lane',
        ShellPanelPurpose.recurring => 'Scheduled jobs',
        ShellPanelPurpose.file => id.split('/').last,
        _ => '${purpose.name[0].toUpperCase()}${purpose.name.substring(1)}',
      };
  void complete() {
    if (!dismissed.isCompleted) dismissed.complete();
  }
}

class ShellPanelScope extends InheritedWidget {
  const ShellPanelScope(
      {super.key,
      required this.open,
      this.client,
      this.sessionId,
      required super.child});
  final Future<Object?> Function(ShellPanelRequest) open;
  final DaemonClient? client;
  final String? sessionId;
  static ShellPanelScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellPanelScope>();
  @override
  bool updateShouldNotify(ShellPanelScope old) =>
      old.open != open || old.client != client || old.sessionId != sessionId;
}

class ShellPanelBody extends StatelessWidget {
  const ShellPanelBody(
      {super.key, required this.request, required this.onClose});
  final ShellPanelRequest request;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final host = ShellPanelScope.maybeOf(context)!;
    Widget body = Navigator(
      key: request.navigatorKey,
      pages: [
        MaterialPage<void>(
          key: ValueKey(request.key),
          child: Builder(
              builder: (context) => Material(
                  type: MaterialType.transparency,
                  child: request.builder(context, onClose))),
        )
      ],
      onDidRemovePage: (_) => onClose(),
    );
    final client = request.client;
    if (client != null) body = DaemonScope(client: client, child: body);
    return ShellPanelScope(
        open: host.open,
        client: client,
        sessionId: request.sessionId,
        child: ShellRequestScope(
            request: request,
            child: ShellPanelRoot(label: request.label, child: body)));
  }
}

/// The shell request a panel's content is hosted in, if any.
class ShellRequestScope extends InheritedWidget {
  const ShellRequestScope(
      {super.key, required this.request, required super.child});
  final ShellPanelRequest request;
  static ShellPanelRequest? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellRequestScope>()?.request;
  @override
  bool updateShouldNotify(ShellRequestScope old) => old.request != request;
}
