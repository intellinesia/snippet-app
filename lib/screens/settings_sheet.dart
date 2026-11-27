import 'package:flutter/material.dart';

import '../mobile_kit.dart';
import '../models.dart' show Instance;
import '../motion_routes.dart' show AppPageRoute;
import '../theme.dart';
import '../widgets.dart';
import 'settings_overlay.dart';
import 'settings_pages.dart';

/// Phone Settings: a pushed page with the connected machine on top, then
/// grouped lists; a deep link opens straight on its page.
Future<void> showSettingsSheet(
  BuildContext context, {
  required SettingsHost host,
  required void Function(BuildContext) register,
}) =>
    Navigator.of(context).push<void>(AppPageRoute<void>(
      builder: (ctx) {
        register(ctx);
        return Material(
          type: MaterialType.transparency,
          child: SettingsSheet(host: host),
        );
      },
    ));

// The phone names and icons; the shared list keeps the desktop wording.
const Map<SettingsPage, String> _phoneLabel = {
  SettingsPage.models: 'Profiles',
};

const Map<SettingsPage, String> _phoneIcon = {
  SettingsPage.models: 'bot',
  SettingsPage.routing: 'zap',
  SettingsPage.accounts: 'users',
  SettingsPage.usage: 'analytics',
  SettingsPage.memory: 'brain',
  SettingsPage.wakes: 'repeat',
  SettingsPage.scheduled: 'scheduled',
  SettingsPage.keepWarm: 'timer',
  SettingsPage.vault: 'lock',
  SettingsPage.webSearch: 'globe',
  SettingsPage.voice: 'mic',
  SettingsPage.appearance: 'sliders',
};

String _label(SettingsPage p) => _phoneLabel[p] ?? settingsPageLabel(p);

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.host});
  final SettingsHost host;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  // Null is the index; a deep link starts on its page.
  late SettingsPage? _page = widget.host.startOnPage ? widget.host.page : null;
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search settings');
  final Map<SettingsPage, String> _values = {};
  // Android keeps the field behind the app bar's search action.
  bool _searchOpen = !kAndroidLook;

  bool get _searching => _query.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _query.addListener(_changed);
    _loadValues();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Row values from calls the pages already make; a failed or missing
  /// source leaves the row with its name only.
  void _loadValues() {
    final c = widget.host.client;
    void put(SettingsPage p, String v) {
      if (mounted && v.isNotEmpty) setState(() => _values[p] = v);
    }

    final theme = ThemeManager.instance.resolved;
    final accent = theme.accentName;
    put(SettingsPage.appearance,
        accent == null || accent.isEmpty ? theme.name : '${theme.name}, $accent');
    c.getConfig().then((cfg) {
      put(SettingsPage.models, '${cfg.profiles.length}');
      final lead = cfg.routing['lead'] ?? const <String>[];
      put(
          SettingsPage.routing,
          lead.isNotEmpty
              ? 'Lead: ${lead.first}'
              : _count(cfg.routing.length, 'rule'));
      put(SettingsPage.webSearch, cfg.webSearchKeySet ? 'On' : 'Off');
      put(SettingsPage.voice, cfg.voice.enabled ? 'On' : 'Off');
    }).catchError((_) {});
    c.getAccounts().then((m) {
      final n = m.values.fold<int>(0, (a, l) => a + l.length);
      put(SettingsPage.accounts, '$n');
    }).catchError((_) {});
    c
        .getUsage(since: DateTime.now().subtract(const Duration(days: 7)))
        .then((u) {
      final t = u.providers.fold<int>(0, (a, p) => a + p.totalTokens);
      put(SettingsPage.usage, '${_compact(t)} this week');
    }).catchError((_) {});
    c.wakes().then((w) {
      put(SettingsPage.wakes, '${w.wakes.length}');
    }).catchError((_) {});
    c.recurringJobs().then((j) {
      put(SettingsPage.scheduled, '${j.length}');
    }).catchError((_) {});
    c.keepWarm().then((k) {
      put(SettingsPage.keepWarm,
          '${k.entries.where((e) => e.enabled).length} on');
    }).catchError((_) {});
    c.vaultList().then((v) {
      put(SettingsPage.vault, '${v.length}');
    }).catchError((_) {});
  }

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).round()}k';
    return '$n';
  }

  void _close() => Navigator.of(context).maybePop();

  void _open(SettingsPage page) {
    setState(() {
      _page = page;
      _query.clear();
    });
    _searchFocus.unfocus();
    widget.host.onPage(page);
  }

  /// Back: clear search, then page to index, then close. A deep link skips
  /// the index.
  void _back() {
    if (_page == null && _query.text.isNotEmpty) {
      _query.clear();
      _searchFocus.unfocus();
    } else if (_page == null && kAndroidLook && _searchOpen) {
      setState(() => _searchOpen = false);
    } else if (_page != null && !widget.host.deepLink) {
      setState(() => _page = null);
    } else {
      _close();
    }
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      _searchFocus.requestFocus();
    } else {
      _query.clear();
      _searchFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final canPop = (_page == null &&
            _query.text.isEmpty &&
            !(kAndroidLook && _searchOpen)) ||
        (_page != null && widget.host.deepLink);
    final still = reduceMotion(context);
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'Settings',
        child: KeyedSubtree(
          key: const Key('settings-sheet'),
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: still ? 120 : 200),
            child: KeyedSubtree(
              key: ValueKey(_page?.name ?? 'index'),
              child: _page != null ? _pageView(_page!) : _indexView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Semantics(
          textField: true,
          label: 'Search settings',
          child: Container(
            key: const Key('settings-sheet-search'),
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(kAndroidLook ? 28 : 12),
            ),
            child: Row(children: [
              const SizedBox(width: 14),
              AppIcon('search', size: 16, color: AppColors.fg3),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _query,
                  focusNode: _searchFocus,
                  style: sans(15.5, color: AppColors.fg1),
                  cursorColor: AppColors.fg1,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    final r = searchSettingsPages(_query.text, values: _values);
                    if (r.isNotEmpty) _open(r.first.row.page);
                  },
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: 'Search settings',
                    hintStyle: sans(15.5, color: AppColors.fg4),
                  ),
                ),
              ),
              if (_query.text.isNotEmpty)
                MkIconButton(
                  icon: 'x',
                  label: 'Clear search',
                  bare: true,
                  size: 44,
                  onTap: () => _query.clear(),
                )
              else
                const SizedBox(width: 14),
            ]),
          ),
        ),
      );

  Widget _indexView() {
    final groups = <Widget>[];
    for (final (group, rows) in kSettingsGroups) {
      final list =
          rows.where((r) => r.page != SettingsPage.general).toList();
      if (list.isEmpty) continue;
      groups.add(Semantics(
        container: true,
        explicitChildNodes: true,
        label: group,
        child: MkGroup(
          header: group,
          children: [
            for (final r in list)
              MkGroupRow(
                key: Key('settings-sheet-row-${r.page.name}'),
                label: _label(r.page),
                icon: _phoneIcon[r.page] ?? r.icon ?? 'settings',
                value: _values[r.page],
                onTap: () => _open(r.page),
              ),
          ],
        ),
      ));
    }
    return MkPage(
      title: 'Settings',
      onBack: _close,
      actions: [
        if (kAndroidLook)
          MkAction(_searchOpen ? 'x' : 'search',
              _searchOpen ? 'Close search' : 'Search settings', _toggleSearch),
      ],
      filters: _searchOpen ? _searchField() : null,
      slivers: [
        if (_searching)
          SliverToBoxAdapter(child: _searchResults())
        else
          SliverToBoxAdapter(
            child: Semantics(
              label: 'Settings pages',
              container: true,
              explicitChildNodes: true,
              child: Column(
                key: const Key('settings-sheet-index'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  _MachineCard(
                    key: const Key('settings-sheet-row-general'),
                    active: widget.host.active,
                    onTap: () => _open(SettingsPage.general),
                  ),
                  ...groups,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _searchResults() {
    final hits = searchSettingsPages(_query.text, values: _values);
    final n = hits.length;
    final q = _query.text.trim();
    if (n == 0) {
      return Padding(
        key: const Key('settings-sheet-no-results'),
        padding: const EdgeInsets.fromLTRB(MK.gutter, 28, MK.gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text('No settings match "$q"',
                  style: sans(17, weight: W.label, color: AppColors.fg1)),
            ),
            const SizedBox(height: 6),
            Text('Try another word, or search everything in Snippet.',
                style: mkRowSub()),
            const SizedBox(height: 20),
            if (widget.host.onSearchAll != null) ...[
              KeyedSubtree(
                key: const Key('settings-sheet-search-all'),
                child: MkBigButton('Search all of Snippet', onTap: () {
                  final go = widget.host.onSearchAll!;
                  _close();
                  go(q);
                }),
              ),
              const SizedBox(height: 10),
            ],
            KeyedSubtree(
              key: const Key('settings-sheet-browse-all'),
              child: MkBigButton('Browse all settings', secondary: true,
                  onTap: () {
                _query.clear();
                _searchFocus.unfocus();
              }),
            ),
          ],
        ),
      );
    }
    return Column(
      key: const Key('settings-sheet-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: KeyedSubtree(
            key: const Key('settings-sheet-result-count'),
            child: MkSection('$n ${n == 1 ? 'result' : 'results'}'),
          ),
        ),
        MkList(children: [
          for (var i = 0; i < n; i++)
            KeyedSubtree(
              key: Key('settings-sheet-result-${hits[i].row.page.name}'),
              child: MkRow(
                title: _label(hits[i].row.page),
                subtitle: hits[i].snippet,
                semanticLabel:
                    '${hits[i].row.label}, ${settingsPageGroup(hits[i].row.page)}',
                leading: _ToneIcon(
                    _phoneIcon[hits[i].row.page] ?? hits[i].row.icon ?? 'laptop'),
                divider: i < n - 1,
                onTap: () => _open(hits[i].row.page),
              ),
            ),
        ]),
      ],
    );
  }

  Widget _pageView(SettingsPage page) {
    final backLine = widget.host.deepLink && widget.host.backLabel != null;
    return MkPage(
      title: _label(page),
      onBack: _back,
      bottomClearance: false,
      slivers: [
        if (backLine)
          SliverToBoxAdapter(
            child: Semantics(
              button: true,
              label: 'Back to ${widget.host.backLabel}',
              excludeSemantics: true,
              child: InkWell(
                key: const Key('settings-sheet-back-line'),
                onTap: _close,
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MK.gutter),
                    child: Row(children: [
                      AppIcon(kAndroidLook ? 'arrow-left' : 'chevron-left',
                          size: 15, color: AppColors.fg3),
                      const SizedBox(width: 8),
                      Text('Back to ${widget.host.backLabel}',
                          style: mkRowSub()),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        SliverFillRemaining(
          hasScrollBody: true,
          child: Padding(
            padding: EdgeInsets.only(top: backLine ? 0 : 8),
            child: widget.host.body(page, onOpenPage: _open),
          ),
        ),
      ],
    );
  }
}

/// The connected machine at the top of Settings; opens Machines.
class _MachineCard extends StatelessWidget {
  const _MachineCard({super.key, required this.active, required this.onTap});
  final Instance? active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = active;
    final name = m == null ? 'No machine' : m.label;
    var sub = 'Connect a machine';
    if (m != null) {
      final u = Uri.tryParse(m.url);
      final where = u == null || u.host.isEmpty
          ? m.url
          : (u.hasPort ? '${u.host}:${u.port}' : u.host);
      sub = 'Connected · $where';
    }
    return Semantics(
      button: true,
      label: 'Machines, $name, $sub',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(MK.groupRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashFactory:
                kAndroidLook ? InkRipple.splashFactory : NoSplash.splashFactory,
            highlightColor: AppColors.fg1.withValues(alpha: 0.04),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                        child: AppIcon('monitor',
                            size: 20, color: AppColors.fg2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mkRowTitle()),
                        const SizedBox(height: 2),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppIcon('chevron-right', size: 14, color: AppColors.fg4),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tonal icon disc for search results, matching the group rows.
class _ToneIcon extends StatelessWidget {
  const _ToneIcon(this.icon);
  final String icon;

  @override
  Widget build(BuildContext context) => Container(
        width: kAndroidLook ? 40 : 30,
        height: kAndroidLook ? 40 : 30,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          shape: kAndroidLook ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: kAndroidLook ? null : BorderRadius.circular(9),
        ),
        child: Center(
            child: AppIcon(icon, size: kAndroidLook ? 19 : 17,
                color: AppColors.fg2)),
      );
}
