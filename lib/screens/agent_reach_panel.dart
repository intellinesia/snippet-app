import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/chat_info.dart' show DockedInfoNav, dockedPick;
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// How an agent reaches you, in a popover on desktop and a sheet on phones.
Future<void> showAgentReachSettings(
  BuildContext context, {
  required DaemonClient client,
  required String agentId,
  required String name,
  Offset? point,
}) {
  final panel = AgentReachPanel(client: client, agentId: agentId);
  final nav = DockedInfoNav.maybeOf(context);
  if (nav != null) {
    nav.push('How it reaches you', (_) => panel);
    return Future<void>.value();
  }
  if (kMobile) {
    return showAppSheet(context,
        title: name,
        subtitle: 'How it reaches you',
        maxHeight: 680,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.s12),
          child: panel,
        ));
  }
  return showPointPopover<void>(context,
      point: point,
      width: 400,
      maxHeight: 700,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(S.s12),
          child: panel,
        ),
      ));
}

/// Preset orders offered for a kind; the service accepts any order.
const _routes = <List<String>>[
  ['push', 'chat'],
  ['chat'],
  ['push'],
  ['voice', 'push', 'chat'],
  ['task_room'],
];

String _routeLabel(List<String> r) => r.isEmpty
    ? 'Nowhere'
    : [
        for (var i = 0; i < r.length; i++)
          i == 0
              ? reachChannelLabel(r[i])
              : reachChannelLabel(r[i]).toLowerCase()
      ].join(', then ');

class AgentReachPanel extends StatefulWidget {
  const AgentReachPanel(
      {super.key, required this.client, required this.agentId});
  final DaemonClient client;
  final String agentId;

  @override
  State<AgentReachPanel> createState() => _AgentReachPanelState();
}

class _AgentReachPanelState extends State<AgentReachPanel> {
  AgentReach? _reach;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.client.agentReach(widget.agentId).then((r) {
      if (mounted) setState(() => _reach = r);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  Future<void> _save(
      {Map<String, List<String>>? policy,
      Map<String, Map<String, bool>>? channels}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await widget.client
          .setAgentReach(widget.agentId, policy: policy, channels: channels);
      if (mounted) setState(() => _reach = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickRoute(BuildContext anchor, String kind) async {
    final current = _reach!.policy[kind] ?? const [];
    final options = [
      ..._routes,
      if (!_routes.any((r) => _sameRoute(r, current)) && current.isNotEmpty)
        current,
    ];
    final picked = await dockedPick<int>(
      context,
      title: kind,
      options: [
        for (var i = 0; i < options.length; i++)
          (i, _routeLabel(options[i]), null),
      ],
      selected: [
        for (var i = 0; i < options.length; i++)
          if (_sameRoute(options[i], current)) i,
      ].firstOrNull,
      fallback: () => showAppMenu<int>(anchor, anchor: anchor, items: [
        for (var i = 0; i < options.length; i++)
          appMenuItem(
              value: i,
              selected: _sameRoute(options[i], current),
              label: _routeLabel(options[i])),
      ]),
    );
    if (picked == null || _sameRoute(options[picked], current)) return;
    await _save(policy: {kind: options[picked]});
  }

  static bool _sameRoute(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  @override
  Widget build(BuildContext context) {
    final reach = _reach;
    if (reach == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s24),
        child: Center(
          child: _error != null
              ? Text(_error!, style: sans(12, color: AppColors.danger))
              : const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final push = reach.channel('push');
    return FlatGroupScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: S.s8),
              child: Text(_error!, style: sans(12, color: AppColors.danger)),
            ),
          AppToggle(
            flat: true,
            label: 'Notifications',
            sub: push.enabled
                ? 'Questions and blockers can ping your phone'
                : 'Nothing pings you; messages wait in chat',
            on: push.enabled,
            onChanged: (v) => _save(channels: {
              'push': {'enabled': v}
            }),
          ),
          if (reach.inQuietHours || reach.onCall)
            Padding(
              padding: const EdgeInsets.only(bottom: S.s4),
              child: Text(
                  reach.onCall
                      ? 'You are on a call, so held channels wait.'
                      : 'Quiet hours now, so held channels wait.',
                  style: sans(12, color: AppColors.run)),
            ),
          _divider(),
          _head('Where each kind goes'),
          for (final kind in AgentReach.kinds)
            Builder(
              builder: (anchor) => _row(
                label: reachKindLabel(kind),
                value: _routeLabel(reach.policy[kind] ?? const []),
                onTap: _saving ? null : () => _pickRoute(anchor, kind),
              ),
            ),
          _divider(),
          _head('Channels'),
          for (final ch in AgentReach.channelOrder) _channel(reach, ch),
        ],
      ),
    );
  }

  Widget _channel(AgentReach reach, String ch) {
    final state = reach.channel(ch);
    final fixed = AgentReach.alwaysOn(ch);
    return Row(children: [
      Expanded(
        child: InkWell(
          key: Key('quiet-$ch'),
          borderRadius: BorderRadius.circular(R.md),
          onTap: _saving
              ? null
              : () => _save(channels: {
                    ch: {'quiet_hours': !state.quietHours}
                  }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reachChannelLabel(ch),
                    style: sans(14, color: AppColors.fg1)),
                const SizedBox(height: 2),
                Text(
                  state.quietHours
                      ? 'Held in quiet hours'
                      : 'Delivers in quiet hours',
                  style: sans(12, color: AppColors.fg3),
                ),
              ],
            ),
          ),
        ),
      ),
      if (fixed)
        Text('Always on', style: sans(12, color: AppColors.fg3))
      else
        AppSwitch(
          key: Key('channel-$ch'),
          on: state.enabled,
          onChanged: (v) => _save(channels: {
            ch: {'enabled': v}
          }),
        ),
    ]);
  }

  Widget _row(
      {required String label, required String value, VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(R.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Text(label, style: sans(14, color: AppColors.fg1))),
          Text(value, style: sans(13, color: AppColors.fg2)),
          const SizedBox(width: S.s4),
          AppIcon('chevron-down', size: 14, color: AppColors.fg3),
        ]),
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s12),
        child: Divider(height: 1, thickness: 1, color: AppColors.border),
      );

  Widget _head(String text) => Padding(
        padding: const EdgeInsets.only(bottom: S.s4),
        child:
            Text(text, style: sans(12, weight: W.label, color: AppColors.fg3)),
      );
}
