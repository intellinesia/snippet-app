import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Hand off to" picker: the session's active agents (minus the current
/// owner), an optional note, and the Hand off button. Works as a phone sheet
/// or a desktop dialog via `showAppSheet`.
class SessionHandOffSheet extends StatefulWidget {
  const SessionHandOffSheet({
    super.key,
    required this.client,
    required this.sessionId,
    this.ownerId,
    this.onHandedOff,
  });

  final DaemonClient client;
  final String sessionId;

  /// The session's current owner, excluded from the choices. When null it is
  /// resolved from the sessions list.
  final String? ownerId;

  /// Called with the target's display name and whether the hand-off is
  /// pending (applies when the turn ends) after the sheet closes.
  final void Function(String name, bool pending)? onHandedOff;

  @override
  State<SessionHandOffSheet> createState() => _SessionHandOffSheetState();
}

class _SessionHandOffSheetState extends State<SessionHandOffSheet> {
  final _note = TextEditingController();
  List<CoordinationAgent> _agents = const [];
  String? _selected;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.client.coordinationAgents(),
        widget.client.sessions(),
      ]);
      if (!mounted) return;
      final agents = results[0] as List<CoordinationAgent>;
      final sessions = results[1] as List<SessionInfo>;
      var owner = widget.ownerId ?? '';
      if (owner.isEmpty) {
        final me = sessions.where((s) => s.id == widget.sessionId).firstOrNull;
        owner = me?.ownerAgentId ?? me?.displayAgentId ?? '';
      }
      setState(() {
        _agents = [
          for (final a in agents)
            if (a.available && !a.isMissionControl && a.id != owner) a,
        ];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _handOff() async {
    final to = _selected;
    if (to == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.client.handOffSession(widget.sessionId, to,
          note: _note.text);
      if (!mounted) return;
      final name = _agents
              .where((a) => a.id == to)
              .firstOrNull
              ?.displayName ??
          to;
      final pending = res['pending'] == true;
      Navigator.pop(context);
      widget.onHandedOff?.call(name, pending);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Spinner(size: 18)),
          )
        else if (_agents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _error ?? 'No other agents to hand off to.',
              style: TS.meta(),
            ),
          )
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final a in _agents) _agentRow(a),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppField(
            controller: _note,
            hint: 'Note for the new owner (optional)',
            minLines: 1,
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TS.meta(AppColors.danger)),
          ],
          const SizedBox(height: 12),
          Btn('Hand off',
              full: true,
              icon: 'send',
              disabled: _selected == null || _busy,
              onTap: _busy ? null : _handOff),
        ],
      ],
    );
  }

  Widget _agentRow(CoordinationAgent a) {
    final selected = _selected == a.id;
    final role = a.capabilities.isEmpty
        ? (a.kind.isEmpty ? 'agent' : a.kind)
        : a.capabilities.take(2).join(' · ');
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _selected = a.id),
        child: Container(
          constraints: BoxConstraints(minHeight: kMobile ? 56 : 44),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(children: [
          AgentMochi(a.id, size: kMobile ? 26 : 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(a.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.rowTitle()),
                Text(role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.meta()),
              ],
            ),
          ),
            if (selected)
              AppIcon('check', size: 16, color: AppColors.accent),
          ]),
        ),
      ),
    );
  }
}
