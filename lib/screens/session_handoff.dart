import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../mochi.dart';
import '../morph_sheet.dart';
import '../motion_routes.dart';
import '../platform.dart';
import 'spec_bar.dart';
import '../theme.dart';
import '../widgets.dart';
import '../tap_detector.dart';

// Re-exported so the session part files reach them through this one import.
export '../morph_sheet.dart' show globalRectOf, lastChipOrigin;
export 'session_fork.dart' show showForkSheet, SessionForkPanel;

/// "Hand off to" picker as a sheet or dialog body: [SessionHandOffPanel]
/// that closes its route once the hand-off lands.
class SessionHandOffSheet extends StatelessWidget {
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
  Widget build(BuildContext context) => SessionHandOffPanel(
        client: client,
        sessionId: sessionId,
        ownerId: ownerId,
        onHandedOff: (name, pending) {
          Navigator.pop(context);
          onHandedOff?.call(name, pending);
        },
      );
}

/// The hand-off body: the session's active agents (minus the current owner),
/// an optional note, and the Hand off button. Embeddable anywhere, such as the
/// phone composer tray; the host decides what happens on success.
class SessionHandOffPanel extends StatefulWidget {
  const SessionHandOffPanel({
    super.key,
    required this.client,
    required this.sessionId,
    this.ownerId,
    this.onHandedOff,
    this.list = false,
    this.spec = false,
  });

  /// SE-06 phone page layout: 56 high rows, note box, 48 high Hand off.
  final bool spec;

  final DaemonClient client;
  final String sessionId;
  final String? ownerId;

  /// Agents as compact rows, for narrow hosts such as the session panel.
  final bool list;

  /// Called with the target's display name and whether the hand-off is
  /// pending once the daemon accepts it.
  final void Function(String name, bool pending)? onHandedOff;

  @override
  State<SessionHandOffPanel> createState() => _SessionHandOffPanelState();
}

class _SessionHandOffPanelState extends State<SessionHandOffPanel> {
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
            if (a.available && !a.isLead && a.id != owner) a,
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
      final res = await widget.client
          .handOffSession(widget.sessionId, to, note: _note.text);
      if (!mounted) return;
      final name =
          _agents.where((a) => a.id == to).firstOrNull?.displayName ?? to;
      final pending = res['pending'] == true;
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
    if (widget.spec) return _specBuild(context);
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
          if (widget.list)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 40 * 4.5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (var i = 0; i < _agents.length; i++) ...[
                      if (i > 0) const SizedBox(height: 2),
                      _row(_agents[i]),
                    ],
                  ]),
                ),
              ),
            )
          else
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

  Widget _specBuild(BuildContext context) {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Spinner(size: 18)));
    }
    if (_agents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error ?? 'No other agents to hand off to.',
            style: sans(13, color: AppColors.fg3)),
      );
    }
    final enabled = _selected != null && !_busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SpecLabel('Hand off to', top: 16),
      for (final a in _agents)
        SpecSelectRow(
          label: a.displayName,
          sub: 'Agent - personal',
          selected: _selected == a.id,
          minHeight: 56,
          barHeight: 48,
          leading: AgentMochi(a.id, size: 24),
          onTap: _busy ? () {} : () => setState(() => _selected = a.id),
        ),
      const SpecLabel('Note for Lead'),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
        child: TextField(
          controller: _note,
          minLines: 3,
          maxLines: 6,
          style: sans(15, color: AppColors.fg1),
          cursorColor: AppColors.fg1,
          decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Optional',
              hintStyle: sans(15, color: AppColors.fg3)),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(_error!, style: TS.meta(AppColors.danger)),
        ),
      const SizedBox(height: 16),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            button: true,
            enabled: enabled,
            label:
                _pickedName == null ? 'Hand off' : 'Hand off to $_pickedName',
            child: ExcludeSemantics(
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? _handOff : null,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: enabled ? AppColors.fg1 : AppColors.surface3,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('Hand off',
                      style: sans(15,
                          weight: W.label,
                          color: enabled ? AppColors.bg : AppColors.fg3)),
                ),
              ),
            ),
          )),
      const SizedBox(height: 24),
    ]);
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

  Widget _row(CoordinationAgent a) {
    final selected = _selected == a.id;
    final (state, word) = _stateOf(a);
    return Material(
      color: AppColors.surface3,
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _selected = a.id),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: selected
              ? BoxDecoration(
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4)))
              : null,
          child: Row(children: [
            AgentMochi(a.id, size: 22, state: state),
            const SizedBox(width: 10),
            Expanded(
              child: Text(a.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5,
                      color: selected ? AppColors.fg1 : AppColors.fg2)),
            ),
            if (word != null) ...[
              const SizedBox(width: 6),
              Text(word, style: sans(11, color: AppColors.fg4)),
            ],
            if (selected) ...[
              const SizedBox(width: 6),
              AppIcon('check', size: 13, color: AppColors.accent),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _tile(CoordinationAgent a) {
    final selected = _selected == a.id;
    final (state, word) = _stateOf(a);
    return Semantics(
      button: true,
      selected: selected,
      label: a.displayName,
      child: TapDetector(
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
            if (word != null) Text(word, style: sans(11, color: AppColors.fg3)),
          ]),
        ),
      ),
    );
  }
}

/// Opens hand off: a bar B page on phones (SE-06), a morph sheet elsewhere.
Future<void> showHandOffSheet(
  BuildContext context, {
  required DaemonClient client,
  required String sessionId,
  String? ownerId,
  String? sessionTitle,
  void Function(String name, bool pending)? onHandedOff,
  Rect? origin,
}) {
  if (kMobile) {
    return Navigator.of(context).push<void>(AppPageRoute<void>(
      builder: (page) => Material(
        color: AppColors.pageBg,
        child: SafeArea(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SpecBar(title: 'Hand off session', subtitle: sessionTitle),
            Expanded(
              child: SingleChildScrollView(
                child: SessionHandOffPanel(
                  client: client,
                  sessionId: sessionId,
                  ownerId: ownerId,
                  spec: true,
                  onHandedOff: (name, pending) {
                    Navigator.pop(page);
                    onHandedOff?.call(name, pending);
                  },
                ),
              ),
            ),
          ]),
        ),
      ),
    ));
  }
  return showMorphSheet<void>(
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
}
