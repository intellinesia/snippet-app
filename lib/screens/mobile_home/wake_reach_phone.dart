import 'package:flutter/material.dart';

import '../../api.dart';
import '../../mobile_kit.dart';
import '../../models.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../wake_models.dart';

/// Wakes (HM-12): schedules and watches as kit rows with switches; a schedule
/// opens a sheet to edit its timing. Watches (event and poll rules) are made
/// by the agent itself, so the app can only list and pause them.
class PhoneWakePage extends StatefulWidget {
  const PhoneWakePage(
      {super.key,
      required this.client,
      required this.owner,
      required this.name});
  final DaemonClient client;
  final String owner, name;

  @override
  State<PhoneWakePage> createState() => _PhoneWakePageState();
}

class _PhoneWakePageState extends State<PhoneWakePage> {
  List<WakeSchedule> _wakes = const [];
  List<AgentWatch> _watches = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await widget.client.wakes();
      final w = await widget.client
          .agentWatches(widget.owner)
          .catchError((_) => <AgentWatch>[]);
      if (mounted) {
        setState(() {
          _wakes = [
            for (final x in l.wakes)
              if (x.owner == widget.owner) x
          ];
          _watches = w;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggle(String id, bool on) async {
    try {
      await widget.client.patchWake(id, {'enabled': on});
      await _load();
    } catch (_) {}
  }

  Future<void> _save(WakeSchedule w, String schedule) async {
    try {
      await widget.client.setWake(widget.owner, {
        if (w.name != null) 'name': w.name,
        'schedule': schedule,
        'brief': w.brief,
        'title': w.title.isNotEmpty ? w.title : 'Wake ${widget.name}',
        'enabled': w.enabled,
      });
      await _load();
    } catch (_) {}
  }

  void _edit(WakeSchedule w) => showMkSheet<void>(
        context,
        title: 'Edit wake',
        builder: (_) => _WakeEditor(
            wake: w,
            onSave: (s) async {
              await _save(w, s);
            }),
      );

  MkGroupRow _row(
          {required String id,
          required String icon,
          required String name,
          required String line,
          required String action,
          required bool enabled,
          WakeSchedule? wake}) =>
      MkGroupRow(
        key: ValueKey('rule-$id'),
        icon: icon,
        label: name,
        subtitle: action.isEmpty ? line : '$line\n$action',
        chevron: false,
        onTap: wake == null ? null : () => _edit(wake),
        trailing: MkToggle(
            value: enabled, label: name, onChanged: (v) => _toggle(id, v)),
      );

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bg,
        child: MkPage(
          title: 'Wakes',
          onBack: () => Navigator.of(context).pop(),
          bottomClearance: false,
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                if (_wakes.isNotEmpty)
                  MkGroup(header: 'Schedules', children: [
                    for (final w in _wakes)
                      _row(
                          id: w.id,
                          icon: 'clock',
                          name: w.name ?? (w.title.isEmpty ? 'Wake' : w.title),
                          line: w.scheduleText,
                          action: w.brief,
                          enabled: w.enabled,
                          wake: w),
                  ]),
                if (_watches.isNotEmpty)
                  MkGroup(header: 'Watches', children: [
                    for (final w in _watches)
                      _row(
                          id: w.id,
                          icon: 'eye',
                          name: w.name,
                          line: w.mode == 'poll'
                              ? 'Poll every ${w.intervalMinutes} min'
                              : 'On event',
                          action: w.filter ?? '',
                          enabled: w.enabled),
                  ]),
                if (_wakes.isEmpty && _watches.isEmpty)
                  const MkGroup(children: [
                    MkGroupRow(
                        icon: 'clock',
                        label: 'No wakes yet',
                        subtitle: 'Wakes this agent schedules appear here.',
                        chevron: false),
                  ]),
                const SizedBox(height: 24),
              ]),
            ),
          ],
        ),
      );
}

/// Edit sheet body: kind control and the schedule field. Only schedules are
/// editable, so Event and Poll disable the field.
class _WakeEditor extends StatefulWidget {
  const _WakeEditor({required this.wake, required this.onSave});
  final WakeSchedule wake;
  final Future<void> Function(String schedule) onSave;

  @override
  State<_WakeEditor> createState() => _WakeEditorState();
}

class _WakeEditorState extends State<_WakeEditor> {
  late final _field = TextEditingController(text: widget.wake.scheduleText);
  int _kind = 0;
  bool _saving = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  bool get _valid => _kind == 0 && _field.text.trim().isNotEmpty && !_saving;

  Future<void> _submit() async {
    if (!_valid) return;
    setState(() => _saving = true);
    await widget.onSave(_field.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  Widget _seg() => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == _kind,
                label: const ['Schedule', 'Event', 'Poll'][i],
                excludeSemantics: true,
                child: TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _kind = i),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: i == _kind ? AppColors.surface3 : null,
                        borderRadius: BorderRadius.circular(22)),
                    child: Text(const ['Schedule', 'Event', 'Poll'][i],
                        style: sans(14,
                            weight:
                                i == _kind ? FontWeight.w500 : FontWeight.w400,
                            color: i == _kind ? AppColors.fg1 : AppColors.fg2)),
                  ),
                ),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _seg(),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16)),
            child: TextField(
              controller: _field,
              enabled: _kind == 0,
              onChanged: (_) => setState(() {}),
              style: sans(15, color: AppColors.fg1),
              cursorColor: AppColors.fg1,
              decoration: InputDecoration.collapsed(
                  hintText: _kind == 0
                      ? 'daily 09:00'
                      : 'The agent sets this rule itself',
                  hintStyle: sans(15, color: AppColors.fg4)),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: MkPill('Cancel',
                    expand: true, onTap: () => Navigator.of(context).pop())),
            const SizedBox(width: 12),
            Expanded(
                child: MkPill('Save rule',
                    expand: true,
                    tone: MkPillTone.primary,
                    onTap: _valid ? _submit : null)),
          ]),
        ]),
      );
}

/// Reach (HM-12): a switch row per channel the agent may use to find you.
/// Chat always delivers, so its switch is on and fixed. No email channel exists.
class PhoneReachPage extends StatefulWidget {
  const PhoneReachPage(
      {super.key,
      required this.client,
      required this.agentId,
      required this.name});
  final DaemonClient client;
  final String agentId, name;

  @override
  State<PhoneReachPage> createState() => _PhoneReachPageState();
}

class _PhoneReachPageState extends State<PhoneReachPage> {
  AgentReach? _reach;

  @override
  void initState() {
    super.initState();
    widget.client.agentReach(widget.agentId).then((r) {
      if (mounted) setState(() => _reach = r);
    }).catchError((_) {});
  }

  Future<void> _set(String ch, bool on) async {
    try {
      final r = await widget.client.setAgentReach(widget.agentId, channels: {
        ch: {'enabled': on}
      });
      if (mounted) setState(() => _reach = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final r = _reach;
    const rows = [
      ('chat', 'Chat with you', 'message-circle', 'Messages in the app'),
      ('push', 'Push notification', 'bell', 'Alerts when the app is closed'),
      ('voice', 'Voice call prompt', 'phone', 'Asks to talk by voice'),
    ];
    return Material(
      color: AppColors.bg,
      child: MkPage(
        title: 'Reach',
        onBack: () => Navigator.of(context).pop(),
        bottomClearance: false,
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate([
              if (r != null)
                MkGroup(
                  header: 'Channels',
                  footer: 'Chat always reaches you.',
                  children: [
                    for (final (ch, label, icon, sub) in rows)
                      MkGroupRow(
                        icon: icon,
                        label: label,
                        subtitle: sub,
                        chevron: false,
                        onTap: AgentReach.alwaysOn(ch)
                            ? null
                            : () => _set(ch, !r.channel(ch).enabled),
                        trailing: MkToggle(
                          label: label,
                          value:
                              AgentReach.alwaysOn(ch) || r.channel(ch).enabled,
                          onChanged: AgentReach.alwaysOn(ch)
                              ? null
                              : (v) => _set(ch, v),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 24),
            ]),
          ),
        ],
      ),
    );
  }
}
