import 'package:flutter/material.dart';

import '../menu_widgets.dart';
import '../morph_sheet.dart';
import '../phosphor_icons.dart';
import '../theme.dart';
import 'settings_overlay.dart';
import 'settings_pages.dart';

/// Phone Settings (spec P1 to P6): the shared spring sheet with a medium
/// (60%) and a large detent; a deep link opens at large on the page.
Future<void> showSettingsSheet(
  BuildContext context, {
  required SettingsHost host,
  required void Function(BuildContext) register,
}) {
  final detents = SheetDetents();
  return showSpringSheet<void>(
    context,
    size: SheetSize.large,
    medium: host.startOnPage ? null : 0.6,
    largeGap: 8,
    detents: detents,
    builder: (ctx, scroll) {
      register(ctx);
      return Material(
        type: MaterialType.transparency,
        child: AppSheetSurface(
          expand: true,
          handle: false,
          child: SettingsSheet(host: host, detents: detents, scroll: scroll),
        ),
      );
    },
  ).whenComplete(detents.dispose);
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.host,
    required this.detents,
    required this.scroll,
  });
  final SettingsHost host;
  final SheetDetents detents;
  final ScrollController scroll;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  // Null is the index; a deep link starts on its page.
  late SettingsPage? _page = widget.host.startOnPage ? widget.host.page : null;
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search settings');
  final Map<SettingsPage, String> _values = {};

  bool get _large => widget.host.startOnPage || widget.detents.large;
  bool get _searching => _query.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.detents.addListener(_changed);
    _query.addListener(_changed);
    _searchFocus.addListener(() {
      // The keyboard needs the room (P4).
      if (_searchFocus.hasFocus) widget.detents.expand();
    });
    _loadValues();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.detents.removeListener(_changed);
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Row values (X2.1) from calls the pages already make; a failed or
  /// missing source leaves the row with its name only.
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
      final active = cfg.active;
      put(
          SettingsPage.models,
          active != null && active.isNotEmpty
              ? '$active active'
              : '${cfg.profiles.length} profiles');
      put(SettingsPage.routing, _count(cfg.routing.length, 'rule'));
      put(SettingsPage.webSearch, cfg.webSearchKeySet ? 'On' : 'Off');
      put(SettingsPage.voice, cfg.voice.enabled ? 'On' : 'Off');
    }).catchError((_) {});
    c.getAccounts().then((m) {
      final n = m.values.fold<int>(0, (a, l) => a + l.length);
      put(SettingsPage.accounts, '$n signed in');
    }).catchError((_) {});
    c
        .getUsage(since: DateTime.now().subtract(const Duration(days: 7)))
        .then((u) {
      final t = u.providers.fold<int>(0, (a, p) => a + p.totalTokens);
      put(SettingsPage.usage, '${_compact(t)} this week');
    }).catchError((_) {});
    c.wakes().then((w) {
      put(SettingsPage.wakes, _count(w.wakes.length, 'wake'));
    }).catchError((_) {});
    c.recurringJobs().then((j) {
      put(SettingsPage.scheduled, '${j.length} recurring');
    }).catchError((_) {});
    c.keepWarm().then((k) {
      put(SettingsPage.keepWarm,
          '${k.entries.where((e) => e.enabled).length} on');
    }).catchError((_) {});
    c.vaultList().then((v) {
      put(SettingsPage.vault, _count(v.length, 'secret'));
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
    widget.detents.expand();
    setState(() {
      _page = page;
      _query.clear();
    });
    _searchFocus.unfocus();
    widget.host.onPage(page);
  }

  /// Back (P6): clear search, then page to index, then close. A deep link
  /// skips the index.
  void _back() {
    if (_page == null && _query.text.isNotEmpty) {
      _query.clear();
      _searchFocus.unfocus();
    } else if (_page != null && !widget.host.deepLink) {
      setState(() => _page = null);
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final canPop = (_page == null && _query.text.isEmpty) ||
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
        child: Column(
          key: const Key('settings-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(),
            if (_page == null) _searchField(),
            Expanded(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: still ? 120 : 200),
                child: KeyedSubtree(
                  key: ValueKey(_page?.name ?? (_searching ? 'search' : 'index')),
                  child: _page != null
                      ? _pageView(_page!)
                      : (_searching ? _searchView() : _indexView()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Grabber in a 96 x 48 target over a 48-high title row (P1, P3).
  Widget _topBar() {
    final page = _page;
    final title = page == null ? 'Settings' : settingsPageLabel(page);
    final big = page == null && _large && !_searching;
    final canResize = !widget.host.startOnPage;
    return SizedBox(
      height: 16 + 48,
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 16,
          height: 48,
          child: Row(children: [
            if (page != null)
              _SheetIconButton(
                key: const Key('settings-sheet-back'),
                icon: PhIcons.caretLeft,
                label: 'Back',
                onTap: _back,
              )
            else
              const SizedBox(width: 16),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  key: const Key('settings-sheet-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(big ? 32 : 16,
                      weight: W.label, color: AppColors.fg1),
                ),
              ),
            ),
            _SheetIconButton(
              key: const Key('settings-sheet-close'),
              icon: PhIcons.x,
              label: 'Close settings',
              onTap: _close,
            ),
          ]),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
            child: Semantics(
              button: canResize,
              label: 'Resize settings sheet',
              value: _large ? 'large' : 'medium',
              excludeSemantics: true,
              onTap: canResize
                  ? () => _large
                      ? widget.detents.collapse()
                      : widget.detents.expand()
                  : null,
              child: GestureDetector(
                key: const Key('settings-sheet-grabber'),
                behavior: HitTestBehavior.opaque,
                onTap: canResize
                    ? () => _large
                        ? widget.detents.collapse()
                        : widget.detents.expand()
                    : null,
                child: const SizedBox(
                  width: 96,
                  height: 48,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SheetGrabHandle(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Semantics(
          textField: true,
          label: 'Search settings',
          child: Container(
            key: const Key('settings-sheet-search'),
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const SizedBox(width: 12),
              Icon(PhIcons.magnifyingGlass, size: 15, color: AppColors.fg2),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _query,
                  focusNode: _searchFocus,
                  style: sans(15, color: AppColors.fg1),
                  cursorColor: AppColors.fg1,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    final r = searchSettingsPages(_query.text, values: _values);
                    if (r.isNotEmpty) _open(r.first.row.page);
                  },
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    hintText: 'Search settings',
                    hintStyle: sans(15, color: AppColors.fg2),
                  ),
                ),
              ),
              if (_query.text.isNotEmpty)
                _SheetIconButton(
                  icon: PhIcons.x,
                  label: 'Clear search',
                  iconSize: 14,
                  onTap: () => _query.clear(),
                ),
            ]),
          ),
        ),
      );

  Widget _indexView() {
    final children = <Widget>[];
    for (final (group, rows) in kSettingsGroups) {
      children.add(Semantics(
        container: true,
        explicitChildNodes: true,
        label: group,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    child: Text(group,
                        style: sans(12, weight: W.label, color: AppColors.fg3)),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < rows.length; i++)
              _IndexRow(
                row: rows[i],
                value: _values[rows[i].page] ?? '',
                hairline: i < rows.length - 1,
                onTap: () => _open(rows[i].page),
              ),
          ],
        ),
      ));
    }
    return Semantics(
      label: 'Settings pages',
      container: true,
      explicitChildNodes: true,
      child: ListView(
        key: const Key('settings-sheet-index'),
        controller: widget.scroll,
        padding: EdgeInsets.only(
            bottom: 16 + MediaQuery.paddingOf(context).bottom),
        children: children,
      ),
    );
  }

  Widget _searchView() {
    final hits = searchSettingsPages(_query.text, values: _values);
    final n = hits.length;
    final q = _query.text.trim();
    return ListView(
      key: const Key('settings-sheet-results'),
      controller: widget.scroll,
      padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom),
      children: [
        if (n == 0)
          Padding(
            key: const Key('settings-sheet-no-results'),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text('No settings match "$q"',
                      style: sans(16, weight: W.label, color: AppColors.fg1)),
                ),
                const SizedBox(height: 6),
                Text('Try another word, or search everything in Snippet.',
                    style: sans(14, color: AppColors.fg3)),
                const SizedBox(height: 16),
                if (widget.host.onSearchAll != null) ...[
                  _SheetButton(
                    key: const Key('settings-sheet-search-all'),
                    label: 'Search all of Snippet',
                    onTap: () {
                      final go = widget.host.onSearchAll!;
                      _close();
                      go(q);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                _SheetButton(
                  key: const Key('settings-sheet-browse-all'),
                  label: 'Browse all settings',
                  onTap: () {
                    _query.clear();
                    _searchFocus.unfocus();
                  },
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Semantics(
              liveRegion: true,
              child: Text('$n ${n == 1 ? 'result' : 'results'}',
                  key: const Key('settings-sheet-result-count'),
                  style: sans(12, weight: W.label, color: AppColors.fg3)),
            ),
          ),
          for (var i = 0; i < n; i++)
            _ResultTile(
              hit: hits[i],
              hairline: i < n - 1,
              onTap: () => _open(hits[i].row.page),
            ),
        ],
      ],
    );
  }

  Widget _pageView(SettingsPage page) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.host.deepLink && widget.host.backLabel != null)
            Semantics(
              button: true,
              label: 'Back to ${widget.host.backLabel}',
              excludeSemantics: true,
              child: InkWell(
                key: const Key('settings-sheet-back-line'),
                onTap: _close,
                child: SizedBox(
                  height: 48,
                  child: Row(children: [
                    const SizedBox(width: 16),
                    Icon(PhIcons.arrowLeft, size: 15, color: AppColors.fg2),
                    const SizedBox(width: 8),
                    Text('Back to ${widget.host.backLabel}',
                        style: sans(14, color: AppColors.fg2)),
                  ]),
                ),
              ),
            ),
          Expanded(child: widget.host.body(page, onOpenPage: _open)),
        ],
      );
}

/// Index row (P2): 48 minimum, grows with text; under large text the value
/// moves under the name.
class _IndexRow extends StatelessWidget {
  const _IndexRow({
    required this.row,
    required this.value,
    required this.hairline,
    required this.onTap,
  });
  final SettingsPageRow row;
  final String value;
  final bool hairline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 15 * 1.5;
    final name = Text(row.label, style: sans(15, color: AppColors.fg1));
    final val = Text(value,
        textAlign: stacked ? TextAlign.start : TextAlign.end,
        style: sans(13, color: AppColors.fg3));
    return Semantics(
      button: true,
      label: value.isEmpty ? row.label : '${row.label}, $value',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: Key('settings-sheet-row-${row.page.name}'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          foregroundDecoration: hairline
              ? _Hairline(AppColors.line)
              : null,
          child: Row(children: [
            settingsRowIcon(row, 16, AppColors.fg2),
            const SizedBox(width: 12),
            Expanded(
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [name, if (value.isNotEmpty) val],
                    )
                  : Row(children: [
                      Expanded(child: name),
                      if (value.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(child: val),
                      ],
                    ]),
            ),
            const SizedBox(width: 8),
            Icon(PhIcons.caretRight, size: 13, color: AppColors.fg3),
          ]),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile(
      {required this.hit, required this.hairline, required this.onTap});
  final SettingsHit hit;
  final bool hairline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final group = settingsPageGroup(hit.row.page);
    return Semantics(
      button: true,
      label: '${hit.row.label}, $group',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: Key('settings-sheet-result-${hit.row.page.name}'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          foregroundDecoration: hairline ? _Hairline(AppColors.line) : null,
          child: Row(children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.row.label, style: sans(15, color: AppColors.fg1)),
                  const SizedBox(height: 2),
                  Text(hit.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(PhIcons.caretRight, size: 13, color: AppColors.fg3),
          ]),
        ),
      ),
    );
  }
}

/// Bottom hairline inset 16 on both sides (P2).
class _Hairline extends Decoration {
  const _Hairline(this.color);
  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _HairlinePainter(color);
}

class _HairlinePainter extends BoxPainter {
  _HairlinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final s = cfg.size!;
    final y = offset.dy + s.height - 0.5;
    canvas.drawLine(Offset(offset.dx + 16, y),
        Offset(offset.dx + s.width - 16, y), Paint()..color = color);
  }
}

class _SheetIconButton extends StatelessWidget {
  const _SheetIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconSize = 18,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox.square(
            dimension: 48,
            child: Icon(icon, size: iconSize, color: AppColors.fg2),
          ),
        ),
      );
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(label,
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
              ),
            ),
          ),
        ),
      );
}
