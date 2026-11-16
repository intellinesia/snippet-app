import 'package:flutter/material.dart';

import '../api.dart';
import '../desktop_layout.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';

const _routeDefs = <(String, String, String)>[
  ('mission', 'Mission Control', 'Plans and dispatches work'),
  ('inbox', 'Agent inboxes', 'Answers messages and claims tasks'),
  ('lanes', 'Lanes', 'Work a session hands off'),
  ('memory', 'Memory', 'Reflection and compaction notes'),
];

String limitLabel(int resetsAt) {
  final t = DateTime.fromMillisecondsSinceEpoch(resetsAt * 1000);
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  if (sameDay) return '$hh:$mm';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[t.month - 1]} ${t.day}, $hh:$mm';
}

class RoutingScreen extends StatefulWidget {
  const RoutingScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
  });

  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends State<RoutingScreen> {
  ServerConfig? _config;
  Object? _error;
  final Map<String, List<String>> _routes = {};

  @override
  void initState() {
    super.initState();
    _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    try {
      final c = await widget.client.getConfig(force: force);
      if (!mounted) return;
      setState(() {
        _config = c;
        _error = null;
        _routes
          ..clear()
          ..addAll({
            for (final e in c.routing.entries) e.key: [...e.value]
          });
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(String route, List<String> next) async {
    final before = [...?_routes[route]];
    setState(() => _routes[route] = next);
    try {
      await widget.client.setRouting(route, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _routes[route] = before);
      toast(context, "Couldn't save the route: $e", danger: true);
    }
  }

  Future<void> _addFallbackMenu(
      BuildContext anchor, String key, List<String> chosen) async {
    final profiles = _config?.profiles ?? const <InferenceProfile>[];
    final available = [
      for (final p in profiles)
        if (!chosen.contains(p.name)) p
    ];
    if (available.isEmpty) {
      toast(context, 'All profiles are already in this route');
      return;
    }
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 230,
      maxWidth: 320,
      items: [
        appMenuHeading<String>(
            chosen.isEmpty ? 'Select primary profile' : 'Add fallback profile'),
        for (final p in available)
          appMenuRow<String>(
            value: p.name,
            icon: 'provider:${p.provider}',
            label: p.name,
            description: '${p.provider} · ${p.model}',
          ),
      ],
    );
    if (picked == null || !mounted) return;
    await _save(key, [...chosen, picked]);
  }

  Future<void> _pillMenu(
      BuildContext anchor, String key, List<String> chosen, int index) async {
    final name = chosen[index];
    final profiles = _config?.profiles ?? const <InferenceProfile>[];
    final unused = [
      for (final p in profiles)
        if (!chosen.contains(p.name)) p
    ];
    final action = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 220,
      maxWidth: 300,
      items: [
        appMenuHeading<String>(index == 0 ? 'Primary model' : 'Fallback #$index'),
        if (index > 0)
          appMenuItem<String>(
              value: 'primary', icon: 'sparkles', label: 'Make primary'),
        if (index > 0)
          appMenuItem<String>(
              value: 'left', icon: 'arrow-left', label: 'Move earlier'),
        if (index < chosen.length - 1)
          appMenuItem<String>(
              value: 'right', icon: 'arrow-right', label: 'Move later'),
        for (final p in unused)
          appMenuRow<String>(
            value: 'swap:${p.name}',
            icon: 'provider:${p.provider}',
            label: 'Replace with ${p.name}',
            description: p.model,
          ),
        appMenuItem<String>(
            value: 'remove',
            icon: 'trash',
            label: 'Remove from route',
            danger: true),
      ],
    );
    if (action == null || !mounted) return;
    final next = [...chosen];
    if (action == 'primary') {
      next.removeAt(index);
      next.insert(0, name);
    } else if (action == 'left' && index > 0) {
      next.removeAt(index);
      next.insert(index - 1, name);
    } else if (action == 'right' && index < next.length - 1) {
      next.removeAt(index);
      next.insert(index + 1, name);
    } else if (action.startsWith('swap:')) {
      next[index] = action.substring(5);
    } else if (action == 'remove') {
      next.removeAt(index);
    }
    await _save(key, next);
  }

  Widget _pill({
    required Widget child,
    required VoidCallback onTap,
    bool primary = false,
    bool add = false,
    String? tip,
  }) {
    final radius = BorderRadius.circular(kMobile ? R.md : R.sm);
    final body = Material(
      color: add ? Colors.transparent : AppColors.surface3,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: kMobile ? 40 : 32),
          padding: EdgeInsets.symmetric(
              horizontal: kMobile ? S.of(10) : S.s8, vertical: S.s4),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: primary
                ? Border.all(color: AppColors.accent)
                : add
                    ? Border.all(color: AppColors.border2)
                    : null,
          ),
          child: child,
        ),
      ),
    );
    return tip == null ? body : Tooltip(message: tip, child: body);
  }

  Widget _chainWrap(String key, List<String> chosen) {
    final profiles = _config?.profiles ?? const <InferenceProfile>[];
    final byName = {for (final p in profiles) p.name: p};
    final limited = _config?.limited ?? const {};
    final hasMoreProfiles = chosen.length < profiles.length;
    final defaultLabel =
        key == 'lanes' || key == 'memory' ? 'Session model' : 'Active profile';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (chosen.isEmpty)
          Builder(
            builder: (anchor) => _pill(
              onTap: () => _addFallbackMenu(anchor, key, chosen),
              child: Text(defaultLabel, style: sans(13, color: AppColors.fg3)),
            ),
          ),
        for (var i = 0; i < chosen.length; i++)
          Builder(
            builder: (anchor) {
              final name = chosen[i];
              final p = byName[name];
              final isPrimary = i == 0;
              final until = limited[name];
              return _pill(
                primary: isPrimary,
                tip: until != null ? 'Limited until ${limitLabel(until)}' : null,
                onTap: () => _pillMenu(anchor, key, chosen, i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      ProviderLogo(p?.provider ?? name, size: 12),
                      SizedBox(width: S.of(7)),
                      Text(name,
                          style: sans(13,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                      if (until != null) ...[
                        SizedBox(width: S.s6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: AppColors.run, shape: BoxShape.circle),
                        ),
                      ],
                    ]),
                    Text(
                        isPrimary
                            ? 'Primary · tap to edit'
                            : 'Fallback · tap to edit',
                        style: sans(11, color: AppColors.fg3)),
                  ],
                ),
              );
            },
          ),
        if (hasMoreProfiles && chosen.isNotEmpty)
          Builder(
            builder: (anchor) => _pill(
              add: true,
              onTap: () => _addFallbackMenu(anchor, key, chosen),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('plus', size: 13, color: AppColors.fg3),
                SizedBox(width: S.s4),
                Text('Add fallback', style: sans(13, color: AppColors.fg3)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _routeCard(String key, String title, String about) {
    final chosen = _routes[key] ?? const [];
    return Container(
      margin: EdgeInsets.only(bottom: S.s12),
      padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(kMobile ? R.lg : R.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title,
                  style: sans(14, weight: FontWeight.w500, color: AppColors.fg1)),
              SizedBox(width: S.s8),
              Expanded(
                child: Text(about,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg3)),
              ),
            ],
          ),
          SizedBox(height: S.s8),
          _chainWrap(key, chosen),
        ],
      ),
    );
  }

  static const _note =
      'Select a model to make it primary, reorder it, swap it or remove it. The first model handles the work; the rest step in when it hits a limit.';

  List<Widget> _cards() => [
        Padding(
          padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s12),
          child: Text(_note, style: sans(13, height: 1.5, color: AppColors.fg3)),
        ),
        for (final (key, title, about) in _routeDefs)
          _routeCard(key, title, about),
      ];

  @override
  Widget build(BuildContext context) {
    if (!kMobile && _config == null) {
      return SettingsGroup(children: [
        _error == null
            ? const SettingsRow(label: 'Loading routing…')
            : SettingsRow(
                label: "Couldn't load routing",
                sub: '$_error',
                danger: true,
                trailing: Btn('Retry',
                    small: true,
                    variant: BtnVariant.secondary,
                    onTap: () => _load(force: true)),
              ),
      ]);
    }
    if (!kMobile) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: _cards());
    }
    final Widget body;
    if (_config == null) {
      body = _error == null
          ? const ListSkeleton()
          : EmptyState(
              icon: 'alert-triangle',
              title: "Couldn't load routing",
              body: '$_error',
              action:
                  Btn('Retry', small: true, onTap: () => _load(force: true)),
            );
    } else {
      body = ListView(
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s40),
        children: _cards(),
      );
    }
    final scoped = CardGroupScope(child: body);
    if (widget.embedded && widget.onBack != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
              title: 'Routing', compact: true, onBack: widget.onBack!),
          Expanded(child: scoped),
        ],
      );
    }
    return scoped;
  }
}
