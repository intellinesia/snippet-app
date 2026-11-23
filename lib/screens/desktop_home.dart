import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../session_quick_send.dart';
import '../theme.dart';
import 'mobile_home/quiet_home.dart';
import 'lead/lead_state.dart' show isDedicatedLeadSession;

/// Desktop Home: the phone's Needs you, Working and Earlier today, centred on
/// one 720 pt measure in the main pane.
class DesktopHome extends StatefulWidget {
  const DesktopHome({
    super.key,
    required this.client,
    required this.sessions,
    required this.onOpenSession,
    required this.onOpenSessions,
    required this.onSettings,
    required this.onSearch,
    required this.onRefresh,
  });

  final DaemonClient client;
  final List<SessionInfo>? sessions;
  final void Function(SessionInfo s) onOpenSession;
  final VoidCallback onOpenSessions;
  final VoidCallback onSettings;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  List<CoordinationAgent> _agents = const [];

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((a) {
      if (mounted) setState(() => _agents = a);
    }).catchError((_) {});
  }

  Future<bool> _decide(SessionInfo s, bool approve) async {
    final ok = await quickSend(
      client: widget.client,
      session: s.id,
      action: approve ? const QuickApprove() : const QuickDeny(),
    );
    if (ok) widget.onRefresh();
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final s in widget.sessions ?? const <SessionInfo>[])
        if (!isDedicatedLeadSession(s.id)) s
    ];
    return ColoredBox(
      color: AppColors.bg,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: QuietHomeScreen(
            sessions: list,
            agents: _agents,
            onOpenSession: widget.onOpenSession,
            onOpenSessions: widget.onOpenSessions,
            onSettings: widget.onSettings,
            onSearch: widget.onSearch,
            onDecide: _decide,
          ),
        ),
      ),
    );
  }
}
