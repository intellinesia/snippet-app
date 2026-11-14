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
    for (final g in groups) {
      if (g.id == threadId) {
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
          client: client, agentId: thread.peerId, agentName: thread.title);
      return true;
    }
  }
  return false;
}
