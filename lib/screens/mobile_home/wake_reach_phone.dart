import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../wake_models.dart';
import 'agents_home.dart';

// Cards and segments sit 16 in from the screen edge on the board.
const double _inset = 16;

/// Wake (HM-12): rule cards with switches; the open card edits a schedule.
/// Watches (event and poll rules) are created by the agent itself, so the
/// app can only list, pause and delete them.
class PhoneWakePage extends StatefulWidget {
  const PhoneWakePage(
      {super.key, required this.client, required this.owner, required this.name});
  final DaemonClient client;
  final String owner, name;

  @override
  State<PhoneWakePage> createState() => _PhoneWakePageState();
}

class _PhoneWakePageState extends State<PhoneWakePage> {
  List<WakeSchedule> _wakes = const [];
  List<AgentWatch> _watches = const [];
  String? _editing; // wake id, or 'new'
  int _kind = 0;
  final _field = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await widget.client.wakes();
      final w = await widget.client
          .agentWatches(widget.owner)
          .catchError((_) => <AgentWatch>[]);
      if (mounted) {
        setState(() {
          _wakes = [for (final x in l.wakes) if (x.owner == widget.owner) x];
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

  bool get _valid => _kind == 0 && _field.text.trim().isNotEmpty;

  Future<void> _save(WakeSchedule? w) async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.client.setWake(widget.owner, {
        if (w?.name != null) 'name': w!.name,
        'schedule': _field.text.trim(),
        'brief': w?.brief ?? '',
        'title': w?.title.isNotEmpty == true ? w!.title : 'Wake ${widget.name}',
        'enabled': w?.enabled ?? true,
      });
      _editing = null;
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  Widget _seg() => Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(22)),
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
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: i == _kind ? AppColors.surface3 : null,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(const ['Schedule', 'Event', 'Poll'][i],
                        style: sans(13,
                            weight: i == _kind ? FontWeight.w500 : FontWeight.w400,
                            color: i == _kind ? AppColors.fg1 : AppColors.fg2)),
                  ),
                ),
              ),
            ),
        ]),
      );

  Widget _card(
      {required String id,
      required String name,
      required String line,
      required String action,
      required bool enabled,
      WakeSchedule? wake}) {
    final open = _editing == id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, 10),
      child: Container(
        key: ValueKey('rule-$id'),
        constraints: const BoxConstraints(minHeight: 88),
        decoration: BoxDecoration(
            color: AppColors.surface1, borderRadius: BorderRadius.circular(12)),
        child: Stack(children: [
          if (open)
            Positioned(
                left: 0, top: 0, bottom: 0, width: 2,
                child: ColoredBox(color: AppColors.fg1)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 2, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: TapDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: wake == null
                        ? null
                        : () => setState(() {
                              _editing = open ? null : id;
                              _kind = 0;
                              _field.text = wake.scheduleText;
                            }),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: sans(15, weight: FontWeight.w500, color: AppColors.fg1)),
                          Text(line, style: sans(12, color: AppColors.fg3)),
                          if (action.isNotEmpty)
                            Text(action, style: sans(12, color: AppColors.fg2)),
                        ]),
                  ),
                ),
                SpecSwitch(
                    value: enabled,
                    label: name,
                    onChanged: (v) => _toggle(id, v)),
              ]),
              if (open) ...[
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.only(right: 14), child: _seg()),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(8)),
                    child: TextField(
                      controller: _field,
                      enabled: _kind == 0,
                      onChanged: (_) => setState(() {}),
                      style: sans(14, color: AppColors.fg1),
                      cursorColor: AppColors.fg1,
                      decoration: InputDecoration.collapsed(
                          hintText: _kind == 0
                              ? 'daily 09:00'
                              : 'The agent sets this rule itself',
                          hintStyle: sans(14, color: AppColors.fg4)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    _btn('Cancel', false, () => setState(() => _editing = null)),
                    const SizedBox(width: 8),
                    _btn('Save rule', true, _valid ? () => _save(wake) : null),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _btn(String label, bool primary, VoidCallback? onTap) => SizedBox(
        width: primary ? 150 : 110,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: label,
          excludeSemantics: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              key: ValueKey('btn-$label'),
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: primary
                      ? (onTap == null ? AppColors.surface3 : AppColors.fg1)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(12)),
              child: Text(label,
                  style: sans(14,
                      weight: FontWeight.w500,
                      color: primary
                          ? (onTap == null ? AppColors.fg4 : AppColors.bg)
                          : AppColors.fg1)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bg,
        child: SafeArea(
          child: Column(children: [
            PushedBar(title: 'Wake', subtitle: widget.name),
            Expanded(
              child: ListView(padding: const EdgeInsets.only(top: 16, bottom: 24), children: [
                for (final w in _wakes)
                  _card(
                      id: w.id,
                      name: w.name ?? (w.title.isEmpty ? 'Wake' : w.title),
                      line: w.scheduleText,
                      action: w.brief,
                      enabled: w.enabled,
                      wake: w),
                for (final w in _watches)
                  _card(
                      id: w.id,
                      name: w.name,
                      line: w.mode == 'poll'
                          ? 'Poll every ${w.intervalMinutes} min'
                          : 'On event',
                      action: w.filter ?? '',
                      enabled: w.enabled),
                if (_wakes.isEmpty && _watches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(_inset),
                    child: Center(
                        child: Text('No wake rules yet',
                            style: sans(14, color: AppColors.fg3))),
                  ),
              ]),
            ),
          ]),
        ),
      );
}

/// Reach (HM-12): a switch row per channel the agent may use to find you.
/// Chat always delivers, so its switch is on and fixed. No email channel exists.
class PhoneReachPage extends StatefulWidget {
  const PhoneReachPage(
      {super.key, required this.client, required this.agentId, required this.name});
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
      ('chat', 'Chat with you'),
      ('push', 'Push notification'),
      ('voice', 'Voice call prompt'),
    ];
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          PushedBar(title: 'Reach', subtitle: widget.name),
          Expanded(
            child: ListView(children: [
              const HomeLabel('Channels'),
              if (r != null)
                for (final (ch, label) in rows)
                  SwitchRow(
                    label,
                    AgentReach.alwaysOn(ch) || r.channel(ch).enabled,
                    AgentReach.alwaysOn(ch) ? null : (v) => _set(ch, v),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }
}
