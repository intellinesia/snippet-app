import 'package:flutter/material.dart';

import 'api.dart';
import 'menu_widgets.dart' show toast;
import 'notification_conversation.dart';
import 'screens/agent_messaging.dart' show openAgentThread;
import 'screens/tasks/task_common.dart' show openTaskDetail;

/// Chat links that open a place in the app: agent:, thread: and task:.
enum ChatLinkKind { agent, thread, task }

/// The kind and id of a chat link, or null for any other href.
/// Split by hand because thread ids hold `:` and `|`, which Uri mangles.
({ChatLinkKind kind, String id})? parseChatLink(String? href) {
  final h = (href ?? '').trim();
  final cut = h.indexOf(':');
  if (cut <= 0) return null;
  final kind = switch (h.substring(0, cut)) {
    'agent' => ChatLinkKind.agent,
    'thread' => ChatLinkKind.thread,
    'task' => ChatLinkKind.task,
    _ => null,
  };
  if (kind == null) return null;
  var id = h.substring(cut + 1).trim();
  try {
    id = Uri.decodeComponent(id);
  } catch (_) {}
  // `task:task:<id>` is a task room id; the page wants the bare task id.
  if (kind == ChatLinkKind.task && id.startsWith('task:')) id = id.substring(5);
  if (id.isEmpty || id.contains(RegExp(r'\s'))) return null;
  return (kind: kind, id: id);
}

Future<void> openChatLink(BuildContext context, DaemonClient client,
    ({ChatLinkKind kind, String id}) link, String? text) async {
  final what = switch (link.kind) {
    ChatLinkKind.agent => 'agent',
    ChatLinkKind.thread => 'chat',
    ChatLinkKind.task => 'task',
  };
  void missing() {
    if (context.mounted) toast(context, 'Couldn\'t find that $what.');
  }

  try {
    switch (link.kind) {
      case ChatLinkKind.agent:
        final agents = await client.coordinationAgents();
        final a = agents.where((a) => a.id == link.id).firstOrNull;
        if (a == null) return missing();
        if (!context.mounted) return;
        openAgentThread(context,
            client: client, agentId: a.id, agentName: a.displayName);
      case ChatLinkKind.thread:
        final opened =
            await openNotificationConversation(context, client, link.id);
        if (!opened) missing();
      case ChatLinkKind.task:
        await client.getTask(link.id);
        if (!context.mounted) return;
        await openTaskDetail(context, client, link.id);
    }
  } catch (_) {
    missing();
  }
}
