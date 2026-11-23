import 'package:flutter/material.dart';

import '../theme.dart';

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

/// The Chat | Work switch an agent tab shows in the window bar.
class AgentViewSwitch extends StatelessWidget {
  const AgentViewSwitch({super.key, required this.agentId});
  final String agentId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: agentWorkView,
      builder: (_, work, __) {
        final isWork = work.contains(agentId);
        Widget seg(String label, bool on, bool toWork) => Tooltip(
              message: toWork
                  ? 'Everything the agent did on its desk'
                  : 'The conversation',
              waitDuration: const Duration(milliseconds: 600),
              child: InkWell(
                onTap: () => setAgentWorkView(agentId, toWork),
                borderRadius: BorderRadius.circular(R.of(7)),
                child: AnimatedContainer(
                  duration: Motion.quick,
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.surface3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(R.of(7)),
                  ),
                  child: Text(label,
                      style:
                          sans(12, color: on ? AppColors.fg1 : AppColors.fg3)),
                ),
              ),
            );
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.of(10)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            seg('Chat', !isWork, false),
            const SizedBox(width: 2),
            seg('Work', isWork, true),
          ]),
        );
      },
    );
  }
}
