import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/agent_messaging.dart';
import 'screens/group_messaging.dart' show openGroupThread;

Future<bool> openNotificationConversation(
  BuildContext context,
  DaemonClient client,
  String threadId,
) async {
  if (threadId.startsWith('group:')) {
    final groups = await client.groups();
    if (!context.mounted) return false;
    final id = threadId.substring('group:'.length);
    for (final g in groups) {
      if (g.id == id || g.id == threadId) {
        openGroupThread(context, client: client, group: g);
        return true;
      }
    }
    return false;
  }
  final threads = await client.directThreads();
  if (!context.mounted) return false;
  for (final thread in threads) {
    if (thread.threadId == threadId && thread.peerKind == 'agent') {
      openAgentThread(context,
          client: client,
          agentId: thread.peerId,
          agentName: thread.title,
          initialUnread: thread.unread);
      return true;
    }
  }
  return false;
}

/// Reopens a conversation tab saved by its panel id: `group:<group id>` for a
/// group, otherwise the agent id of a direct chat.
Future<bool> reopenConversation(BuildContext context, DaemonClient client,
    String panelId, String title) async {
  if (panelId.startsWith('group:')) {
    return openNotificationConversation(context, client, panelId);
  }
  openAgentThread(context, client: client, agentId: panelId, agentName: title);
  return true;
}
