import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/chat_info.dart'
    show
        AgentPageCaption,
        AgentPageRow,
        DockedInfoNav,
        dockedPick,
        dockedPromptText;
import '../settings_form.dart' show SettingsGroup, SettingsSwitch;
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';
import 'agent_panel.dart';

/// Inference profile, desk model and context length for one agent, in a
/// popover on desktop and a sheet on phones.
Future<void> showAgentProfileSettings(
  BuildContext context, {
  required DaemonClient client,
  required CoordinationAgent agent,
  required String name,
  Offset? point,
  VoidCallback? onChanged,
}) {
  final nav = DockedInfoNav.maybeOf(context);
  if (nav != null) {
    nav.push(
        'Models and context',
        (_) => AgentProfilePanel(
            client: client,
            agent: agent,
            name: name,
            showTitle: false,
            onChanged: onChanged,
            onPicked: nav.pop));
    return Future<void>.value();
  }
  Widget buildPanel(BuildContext ctx, {required bool closeOnPick}) =>
      AgentProfilePanel(
        client: client,
        agent: agent,
        name: name,
        onChanged: onChanged,
        onPicked: closeOnPick ? () => Navigator.of(ctx).pop() : null,
      );
  if (kMobile) {
    return showAppSheet(
      context,
      title: name,
      maxHeight: 640,
      child: Builder(
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.s12),
          child: buildPanel(ctx, closeOnPick: true),
        ),
      ),
    );
  }
  return showPointPopover<void>(
    context,
    point: point,
    width: 400,
    maxHeight: 700,
    child: Builder(
      builder: (ctx) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 700),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(S.s12),
          child: buildPanel(ctx, closeOnPick: true),
        ),
      ),
    ),
  );
}

class AgentProfilePanel extends StatefulWidget {
  const AgentProfilePanel({
    super.key,
    required this.client,
    required this.agent,
    required this.name,
    this.onChanged,
    this.onPicked,
    this.showTitle = true,
  });

  /// False when the page header already says 'Models and context'.
  final bool showTitle;
  final DaemonClient client;
  final CoordinationAgent agent;
  final String name;
  final VoidCallback? onChanged;
  final VoidCallback? onPicked;

  @override
  State<AgentProfilePanel> createState() => _AgentProfilePanelState();
}

class _AgentProfilePanelState extends State<AgentProfilePanel> {
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

  Future<void> _save(
      Future<void> Function() call, VoidCallback apply, VoidCallback revert,
      {bool notifyProfile = false}) async {
    setState(apply);
    try {
      await call();
      if (!mounted) return;
      if (notifyProfile) {
        toast(context, 'Model updated');
        widget.onChanged?.call();
        widget.onPicked?.call();
      } else {
        widget.onChanged?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(revert);
      toast(context, '$e', danger: true);
    }
  }

  void _pickWork(String? name) {
    if (name == _work) {
      widget.onPicked?.call();
      return;
    }
    final before = _work;
    _save(() => widget.client.setAgentProfile(widget.agent.id, name),
        () => _work = name, () => _work = before,
        notifyProfile: true);
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
    final text = await dockedPromptText(context,
        title: 'Context length for ${widget.name}',
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

  Widget _head(String text, {String? icon}) => Padding(
        padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s8),
        child: Row(children: [
          if (icon != null) ...[
            AppIcon(icon, size: 14, color: AppColors.fg3),
            SizedBox(width: S.s8),
          ],
          Expanded(
              child: Text(text,
                  style:
                      sans(13, weight: FontWeight.w600, color: AppColors.fg1))),
        ]),
      );

  Widget _profile(
          String label, String detail, bool selected, VoidCallback onTap,
          {String icon = 'cpu'}) =>
      AgentPageRow(
        label: label,
        subtitle: detail,
        icon: icon,
        selected: selected,
        checked: selected,
        chevron: false,
        onTap: onTap,
      );

  Widget _radioRow(String label, String? sub, bool on, VoidCallback onTap) =>
      PanelRow(
        label: label,
        sub: sub,
        leading: PanelRadio(on: on),
        minHeight: 46,
        onTap: onTap,
      );

  Future<void> _pickDeskPage(ServerConfig cfg) async {
    final picked = await dockedPick<String>(
      context,
      title: 'Desk runs on',
      selected: _desk ?? _work,
      options: [for (final p in cfg.profiles) (p.name, p.name, 'cpu')],
      fallback: () async => null,
    );
    if (picked != null) _pickDesk(picked);
  }

  static const _presets = [null, 128000, 200000, 400000];

  Widget _desktop(ServerConfig cfg, String? statusLine) {
    final inPanel = DockedInfoNav.maybeOf(context) != null;
    final ctxIndex = _context == null
        ? 0
        : (_presets.indexOf(_context).clamp(-1, 3) >= 0
            ? _presets.indexOf(_context)
            : 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelFootnote(
            '${widget.name}. The order is session pin, then this profile, '
            'then Routing, then the active profile.'),
        PanelGroup(children: [
          _radioRow('Routing default', 'Your Routing settings for desks',
              _work == null, () => _pickWork(null)),
          for (final p in cfg.profiles)
            _radioRow(p.name, '${p.provider} \u00b7 ${p.model}',
                p.name == _work, () => _pickWork(p.name)),
        ]),
        PanelGroup(top: S.s4, children: [
          PanelRow(
            label: 'Separate desk model',
            sub: 'Keep the desk on its own model while tasks use the one above',
            minHeight: 44,
            trailing:
                SettingsSwitch(value: _separate, onChanged: _toggleSeparate),
            onTap: () => _toggleSeparate(!_separate),
          ),
          if (_separate && inPanel)
            PanelRow(
              label: 'Desk runs on',
              value: _desk ?? _work ?? 'Routing default',
              chevron: true,
              onTap: () => _pickDeskPage(cfg),
            ),
          if (_separate && !inPanel)
            for (final p in cfg.profiles)
              _radioRow(p.name, '${p.provider} \u00b7 ${p.model}',
                  p.name == _desk, () => _pickDesk(p.name)),
        ]),
        if (statusLine != null) PanelFootnote(statusLine),
        PanelGroup(top: S.s4, children: [
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.of(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Compact above', style: sans(13.5, color: AppColors.fg1)),
                Text('Smaller ceilings compact sooner and cost less per turn',
                    style: sans(12, color: AppColors.fg4)),
                SizedBox(height: S.of(10)),
                PanelSegments(
                  labels: const [
                    'Model window',
                    '128k',
                    '200k',
                    '400k',
                    'Custom'
                  ],
                  index: ctxIndex,
                  onSelect: (i) {
                    if (i == 4) {
                      _editContext();
                      return;
                    }
                    final next = _presets[i];
                    if (next == _context) return;
                    final before = _context;
                    _save(
                        () => widget.client
                            .setAgentContext(widget.agent.id, next),
                        () => _context = next,
                        () => _context = before);
                  },
                ),
                SizedBox(height: S.of(10)),
                Text(
                    _context == null || ctxIndex < 4
                        ? 'Custom takes at least 16k, for example 160k.'
                        : 'Custom ceiling: ${tokensLabel(_context!)}. Minimum 16k.',
                    style: sans(11.5, color: AppColors.fg4, height: 1.4)),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    if (_failed) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s24),
        child: Center(
            child: Text("Couldn't load models", style: TS.ui(AppColors.fg3))),
      );
    }
    if (cfg == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s24),
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: Spinner(size: 18))),
      );
    }
    final running = widget.agent.deskProfile;
    final deskTarget = _separate ? (_desk ?? _work) : _work;
    final switching =
        running != null && deskTarget != null && running != deskTarget;
    final statusLine = running == null
        ? null
        : switching
            ? 'Desk is on $running, moving to $deskTarget after this turn'
            : 'Desk is running on $running';

    if (!kMobile) return _desktop(cfg, statusLine);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle) _head('Models and context', icon: 'cpu'),
        const AgentPageCaption('Tasks run on'),
        SettingsGroup(children: [
          _profile('Routing default', 'Your Routing settings for desks',
              _work == null, () => _pickWork(null),
              icon: 'sparkles'),
          for (final p in cfg.profiles)
            _profile(p.name, '${p.provider} · ${p.model}', p.name == _work,
                () => _pickWork(p.name)),
        ]),
        SettingsGroup(children: [
          AgentPageRow(
            label: 'Separate desk model',
            subtitle:
                'Keep the desk on its own model while tasks use the one above',
            icon: 'layers',
            trailing:
                SettingsSwitch(value: _separate, onChanged: _toggleSeparate),
            onTap: () => _toggleSeparate(!_separate),
          ),
        ]),
        if (_separate || statusLine != null)
          Padding(
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_separate)
                  Text('Desk runs on', style: sans(12, color: AppColors.fg3)),
                if (statusLine != null) ...[
                  if (_separate) SizedBox(height: S.s4),
                  Text(statusLine, style: sans(12, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
        if (_separate)
          SettingsGroup(children: [
            for (final p in cfg.profiles)
              _profile(p.name, '${p.provider} · ${p.model}', p.name == _desk,
                  () => _pickDesk(p.name)),
          ]),
        Padding(
          padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6),
          child: Text('Context length',
              style: sans(13, weight: W.strong, color: AppColors.fg1)),
        ),
        SettingsGroup(children: [
          AgentPageRow(
            label: 'Compact above',
            subtitle: 'Smaller ceilings compact sooner and cost less per turn',
            icon: 'shrink',
            value: _context == null ? 'Model window' : tokensLabel(_context!),
            valueMono: true,
            onTap: _editContext,
          ),
        ]),
      ],
    );
  }
}

/// The chat info card's compact model rows: 'Tasks run on' and 'Desk runs on',
/// each opening the same inference-profile list [AgentProfilePanel] uses.
class AgentModelRows extends StatefulWidget {
  const AgentModelRows({
    super.key,
    required this.client,
    required this.agent,
    required this.name,
    this.onChanged,
  });

  final DaemonClient client;
  final CoordinationAgent agent;
  final String name;
  final VoidCallback? onChanged;

  @override
  State<AgentModelRows> createState() => _AgentModelRowsState();
}

class _AgentModelRowsState extends State<AgentModelRows> {
  ServerConfig? _cfg;
  late String? _work = widget.agent.profile;
  late String? _desk = widget.agent.deskModel;
  late bool _separate = widget.agent.deskModel != null;

  String get _workLabel => _work ?? 'Routing default';
  String get _deskLabel =>
      _separate ? (_desk ?? _work ?? 'Routing default') : _workLabel;

  Future<void> _save(
      Future<void> Function() call, VoidCallback apply, VoidCallback revert,
      {bool notifyProfile = false}) async {
    setState(apply);
    try {
      await call();
      if (!mounted) return;
      if (notifyProfile) {
        toast(context, 'Model updated');
        widget.onChanged?.call();
      } else {
        widget.onChanged?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(revert);
      toast(context, '$e', danger: true);
    }
  }

  Future<ServerConfig?> _config() async {
    final cached = _cfg;
    if (cached != null) return cached;
    try {
      final cfg = await widget.client.getConfig();
      if (!mounted) return null;
      setState(() => _cfg = cfg);
      return cfg;
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
      return null;
    }
  }

  Widget _pickOptions(BuildContext ctx, ServerConfig cfg,
          {required bool desk, required void Function(String) onPick}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pickRow(
            ctx,
            desk ? 'Same as tasks' : 'Routing default',
            desk ? 'Follows the profile above' : 'Your Routing settings',
            'layers',
            selected: desk ? !_separate : _work == null,
            onTap: () => onPick(''),
          ),
          for (final p in cfg.profiles)
            _pickRow(
              ctx,
              p.name,
              '${p.provider} · ${p.model}',
              'provider:${p.provider}',
              selected: desk ? (_separate && _desk == p.name) : _work == p.name,
              onTap: () => onPick(p.name),
            ),
        ],
      );

  Future<void> _pick({required bool desk}) async {
    final cfg = await _config();
    if (cfg == null || !mounted) return;
    if (cfg.profiles.isEmpty) {
      toast(context, 'No inference profiles configured', danger: true);
      return;
    }
    final title = desk ? 'Desk runs on' : 'Tasks run on';
    final nav = DockedInfoNav.maybeOf(context);
    final String? picked;
    if (nav != null) {
      final done = Completer<String?>();
      nav.push(
          title,
          (ctx) => _pickOptions(ctx, cfg, desk: desk, onPick: (v) {
                if (!done.isCompleted) done.complete(v);
                nav.pop();
              }));
      picked = await done.future;
    } else {
      picked = await showAppSheet<String>(
        context,
        title: title,
        maxWidth: 420,
        maxHeight: 480,
        child: Builder(
          builder: (ctx) => _pickOptions(ctx, cfg,
              desk: desk, onPick: (v) => Navigator.pop(ctx, v)),
        ),
      );
    }
    if (picked == null || !mounted) return;
    final name = picked.isEmpty ? null : picked;
    if (!desk) {
      if (name == _work) return;
      final before = _work;
      _save(() => widget.client.setAgentProfile(widget.agent.id, name),
          () => _work = name, () => _work = before,
          notifyProfile: true);
      return;
    }
    if (name == null) {
      if (!_separate) return;
      final beforeDesk = _desk;
      _save(() => widget.client.setAgentDeskProfile(widget.agent.id, null), () {
        _separate = false;
        _desk = null;
      }, () {
        _separate = true;
        _desk = beforeDesk;
      });
      return;
    }
    if (_separate && name == _desk) return;
    final beforeDesk = _desk;
    _save(() => widget.client.setAgentDeskProfile(widget.agent.id, name), () {
      _separate = true;
      _desk = name;
    }, () {
      _separate = beforeDesk != null;
      _desk = beforeDesk;
    });
  }

  Widget _pickRow(
    BuildContext ctx,
    String title,
    String? detail,
    String icon, {
    required bool selected,
    required VoidCallback onTap,
  }) =>
      ListRow(
        title: title,
        subtitle: detail,
        selected: selected,
        leading: AppIcon(icon, size: 16, color: AppColors.fg2),
        trailing:
            selected ? AppIcon('check', size: 14, color: AppColors.fg1) : null,
        onTap: onTap,
      );

  Widget _row(String label, String value, {required bool desk}) => InkWell(
        onTap: () => _pick(desk: desk),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 48 : 34),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s16 : S.s8),
            child: Row(children: [
              if (kMobile) ...[
                AppIcon(desk ? 'terminal' : 'cpu',
                    size: 18, color: AppColors.fg3),
                SizedBox(width: S.s12),
              ] else ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.tint2,
                      borderRadius: BorderRadius.circular(R.of(6))),
                  child: AppIcon(desk ? 'terminal' : 'cpu',
                      size: 13, color: AppColors.fg3),
                ),
                SizedBox(width: S.s8),
              ],
              Text(label,
                  maxLines: 1,
                  style: kMobile
                      ? sans(15, color: AppColors.fg1)
                      : sans(13, weight: W.label, color: AppColors.fg1)),
              SizedBox(width: S.s8),
              Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: sans(13, color: AppColors.fg3)),
              ),
              SizedBox(width: S.s4),
              AppIcon('chevron-right', size: 14, color: AppColors.fg3),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('Tasks run on', _workLabel, desk: false),
          Divider(
              height: 1,
              thickness: 1,
              indent: kMobile ? S.s16 : 0,
              color: AppColors.border),
          _row('Desk runs on', _deskLabel, desk: true),
        ],
      );
}
