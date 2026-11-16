import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../mochi.dart';
import '../morph_sheet.dart';
import '../theme.dart';
import '../widgets.dart';

// Re-exported so the session part files reach them through this one import.
export '../morph_sheet.dart' show globalRectOf, lastChipOrigin;
export 'session_fork.dart' show showForkSheet;

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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final a in _agents) _tile(a),
            ]),
          ),
          const SizedBox(height: 12),
          AppField(
            controller: _note,
            hint: 'Note for ${_pickedName ?? 'the new owner'} (optional)',
            minLines: 1,
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TS.meta(AppColors.danger)),
          ],
          const SizedBox(height: 12),
          Btn(_pickedName == null ? 'Hand off' : 'Hand to $_pickedName',
              full: true,
              disabled: _selected == null || _busy,
              onTap: _busy ? null : _handOff),
        ],
      ],
    );
  }

  String? get _pickedName =>
      _agents.where((a) => a.id == _selected).firstOrNull?.displayName;

  /// Character state and the short word under the name; unknown presence
  /// shows no word.
  (AgentCharacterState, String?) _stateOf(CoordinationAgent a) {
    final p = a.presence;
    if (p == null) return (AgentCharacterState.idle, null);
    if (p.active) return (AgentCharacterState.working, 'working');
    final since = p.since;
    final recent =
        since != null && DateTime.now().difference(since).inMinutes < 10;
    return recent
        ? (AgentCharacterState.idle, 'free')
        : (AgentCharacterState.sleeping, 'asleep');
  }

  Widget _tile(CoordinationAgent a) {
    final selected = _selected == a.id;
    final (state, word) = _stateOf(a);
    return Semantics(
      button: true,
      selected: selected,
      label: a.displayName,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : () => setState(() => _selected = a.id),
        child: Container(
          width: 76,
          constraints: const BoxConstraints(minHeight: 44),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentBg : Colors.transparent,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
                color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AgentMochi(a.id, size: 40, state: state),
            const SizedBox(height: 6),
            Text(a.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, weight: W.label, color: AppColors.fg1)),
            if (word != null)
              Text(word, style: sans(11, color: AppColors.fg3)),
          ]),
        ),
      ),
    );
  }
}

/// Opens the hand-off sheet, growing out of [origin] on phones.
Future<void> showHandOffSheet(
  BuildContext context, {
  required DaemonClient client,
  required String sessionId,
  String? ownerId,
  void Function(String name, bool pending)? onHandedOff,
  Rect? origin,
}) =>
    showMorphSheet<void>(
      context,
      title: 'Hand off to',
      subtitle: 'They take this session after the current turn.',
      origin: origin,
      builder: (_) => SessionHandOffSheet(
        client: client,
        sessionId: sessionId,
        ownerId: ownerId,
        onHandedOff: onHandedOff,
      ),
    );
