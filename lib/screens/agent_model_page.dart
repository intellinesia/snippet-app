import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';
import '../panel.dart';
import 'mobile_chrome.dart';

/// The model page on its own screen, for phones where there is no side panel.
Future<void> showAgentModelPage(BuildContext context,
        {required DaemonClient client,
        required CoordinationAgent agent,
        required String name}) =>
    presentScreen(context,
        builder: (_, close) => Material(
              color: readingBg,
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MobileBackBar(
                        title: 'Inference profile',
                        subtitle: name,
                        onBack: close),
                    Expanded(
                        child: AgentModelPage(client: client, agent: agent)),
                  ],
                ),
              ),
            ));

/// An agent's models and context length: the profile its tasks run on, an
/// optional separate one for its desk, and its context ceiling.
class AgentModelPage extends StatefulWidget {
  const AgentModelPage({super.key, required this.client, required this.agent});
  final DaemonClient client;
  final CoordinationAgent agent;

  @override
  State<AgentModelPage> createState() => _AgentModelPageState();
}

class _AgentModelPageState extends State<AgentModelPage> {
  ServerConfig? _cfg;
  bool _failed = false;
  late String? _work = widget.agent.profile;
  late String? _desk = widget.agent.deskModel;
  late bool _separate = widget.agent.deskModel != null;
  late int? _context = widget.agent.maxContextTokens;

  @override
  void initState() {
    super.initState();
    widget.client.getConfig().then((c) {
      if (mounted) setState(() => _cfg = c);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  Future<void> _save(Future<void> Function() call, VoidCallback apply,
      VoidCallback revert) async {
    setState(apply);
    try {
      await call();
    } catch (e) {
      if (!mounted) return;
      setState(revert);
      toast(context, '$e', danger: true);
    }
  }

  void _pickWork(String? name) {
    if (name == _work) return;
    final before = _work;
    _save(() => widget.client.setAgentProfile(widget.agent.id, name),
        () => _work = name, () => _work = before);
  }

  void _pickDesk(String name) {
    if (name == _desk) return;
    final before = _desk;
    _save(() => widget.client.setAgentDeskProfile(widget.agent.id, name),
        () => _desk = name, () => _desk = before);
  }

  void _toggleSeparate(bool on) {
    if (on) return setState(() => _separate = true);
    final before = _desk;
    if (before == null) return setState(() => _separate = false);
    _save(() => widget.client.setAgentDeskProfile(widget.agent.id, null), () {
      _separate = false;
      _desk = null;
    }, () {
      _separate = true;
      _desk = before;
    });
  }

  Future<void> _editContext() async {
    final text = await promptText(context,
        title: 'Context length for ${widget.agent.displayName}',
        initial: _context == null ? '' : tokensLabel(_context!),
        hint: 'For example 128k. Minimum 16k; empty uses the model window.');
    if (text == null || !mounted) return;
    final next = text.trim().isEmpty ? null : parseTokens(text);
    if (text.trim().isNotEmpty &&
        (next == null || next < kMinAgentContextTokens)) {
      toast(context, 'Enter at least 16k tokens, for example 128k',
          danger: true);
      return;
    }
    if (next == _context) return;
    final before = _context;
    _save(() => widget.client.setAgentContext(widget.agent.id, next),
        () => _context = next, () => _context = before);
  }

  Widget _heading(String text, {String? note}) => Padding(
        padding: const EdgeInsets.fromLTRB(S.s16, S.s16, S.s16, S.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TS.ui(AppColors.fg2)),
          if (note != null) Text(note, style: TS.meta(AppColors.fg3)),
        ]),
      );

  Widget _row(String icon, String label, String? detail, bool selected,
          VoidCallback onTap,
          {Widget? trailing}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s8),
          child: Row(children: [
            AppIcon(icon, size: 16, color: AppColors.fg2),
            const SizedBox(width: S.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TS.ui(AppColors.fg1)),
                  if (detail != null)
                    Text(detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TS.meta(AppColors.fg3)),
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (selected) AppIcon('check', size: 14, color: AppColors.fg1),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    if (_failed) {
      return Center(
          child: Text("Couldn't load models", style: TS.ui(AppColors.fg3)));
    }
    if (cfg == null) return Center(child: DelayedSpinner(size: 16));
    final running = widget.agent.deskProfile;
    final deskTarget = _separate ? (_desk ?? _work) : _work;
    final switching =
        running != null && deskTarget != null && running != deskTarget;
    return ListView(
      padding: const EdgeInsets.only(bottom: S.s16),
      children: [
        _heading(_separate ? 'Tasks run on' : 'Works on',
            note: _separate ? null : 'Its desk and the tasks it takes'),
        _row('sparkles', 'Routing default', 'Your Routing settings',
            _work == null, () => _pickWork(null)),
        for (final p in cfg.profiles)
          _row('provider:${p.provider}', p.name, '${p.provider} · ${p.model}',
              p.name == _work, () => _pickWork(p.name)),
        const SizedBox(height: S.s8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.s12),
          child: AppToggle(
            on: _separate,
            onChanged: _toggleSeparate,
            label: 'Separate desk model',
            sub: 'Keep the desk on its own model while tasks use the one above',
          ),
        ),
        if (_separate) ...[
          _heading('Desk runs on',
              note: running == null
                  ? null
                  : switching
                      ? 'Desk is on $running, moving after this turn'
                      : 'Desk is running on $running'),
          for (final p in cfg.profiles)
            _row('provider:${p.provider}', p.name, '${p.provider} · ${p.model}',
                p.name == _desk, () => _pickDesk(p.name)),
        ] else if (running != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, 0),
            child: Text(
                switching
                    ? 'Desk is on $running, moving after this turn'
                    : 'Desk is running on $running',
                style: TS.meta(AppColors.fg3)),
          ),
        _heading('Context length'),
        _row(
          'layers',
          'Compact above',
          'Smaller ceilings compact sooner and cost less per turn',
          false,
          _editContext,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_context == null ? 'Model window' : tokensLabel(_context!),
                key: const ValueKey('context-value'),
                style: mono(13, color: AppColors.fg2)),
            const SizedBox(width: 4),
            AppIcon('chevron-right', size: 14, color: AppColors.fg4),
          ]),
        ),
      ],
    );
  }
}
