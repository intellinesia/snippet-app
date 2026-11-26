import 'package:flutter/material.dart';


/// Agents whose tab shows the Work view (the desk transcript) instead of Chat.
final ValueNotifier<Set<String>> agentWorkView = ValueNotifier(<String>{});

/// The agent whose tab is active in the desktop shell, for the list's
/// selected row.
final ValueNotifier<String?> openAgentTab = ValueNotifier<String?>(null);

/// The group whose conversation tab is active, for the list's nested sessions.
final ValueNotifier<String?> openGroupTab = ValueNotifier<String?>(null);

/// Which sidebar place the active tab is: 'home', 'agents' (roster), or ''.
final ValueNotifier<String> activeShellPlace = ValueNotifier<String>('');

void setAgentWorkView(String agentId, bool work) {
  final next = {...agentWorkView.value};
  work ? next.add(agentId) : next.remove(agentId);
  agentWorkView.value = next;
}
