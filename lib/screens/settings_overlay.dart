import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../phosphor_icons.dart';
import '../platform.dart';
import '../theme.dart';
import '../desktop_layout.dart';
import '../motion.dart';
import '../widgets.dart';
import 'settings_pages.dart';
import 'settings_panel.dart';
import 'settings_sheet.dart';

export 'settings_panel.dart' show SettingsPage;
export 'settings_pages.dart'
    show
        kSettingsGroups,
        settingsPageLabel,
        settingsPageIcon,
        settingsPageKeywords;

SettingsPage _lastPage = SettingsPage.general;
BuildContext? _openContext;

/// True while the Settings dialog or sheet is up.
bool get settingsOverlayOpen => _openContext != null;

/// Closes the open Settings overlay, if any (the shortcut toggles it).
void closeSettingsOverlay() {
  final c = _openContext;
  if (c != null && c.mounted) Navigator.of(c).maybePop();
}

/// The one Settings entry (spec S0): Settings is an overlay, never a tab or
/// a destination: a centred modal dialog on desktop, a sheet on the phone.
Future<void> showSettings(
  BuildContext context, {
  required DaemonClient client,
  required List<Instance> instances,
  required Instance? active,
  required void Function(Instance) onRemove,
  void Function(Instance, String)? onRename,
  void Function(Instance)? onSelect,
  void Function(Instance)? onAdd,
  SettingsPage? page,
  String? backLabel,
  String? targetId,
  ValueChanged<String>? onSearchAll,
}) {
  // Session-scoped: a plain reopen lands where the user last was.
  if (page != null) _lastPage = page;
  final host = SettingsHost(
    client: client,
    instances: instances,
    active: active,
    onRemove: onRemove,
    onRename: onRename,
    onSelect: onSelect,
    onAdd: onAdd,
    page: _lastPage,
    startOnPage: page != null,
    deepLink: page != null && backLabel != null,
    backLabel: backLabel,
    targetId: page == null ? null : targetId,
    onSearchAll: onSearchAll,
    onPage: (p) => _lastPage = p,
  );
  final Future<void> done;
  if (kMobile) {
    done = showSettingsSheet(context, host: host, register: _register);
  } else {
    final still = reduceMotion(context);
    done = showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close settings',
      // Spec D1: scrim over the whole window, no blur.
      barrierColor: AppColors.scrim,
      transitionDuration: still
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) {
        _register(ctx);
        return SettingsDialog(host: host);
      },
      transitionBuilder: (ctx, animation, _, child) {
        final t = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeOut);
        return FadeTransition(
          opacity: t,
          // Reduced motion keeps only the 1 ms fade, no rise.
          child: still
              ? child
              : AnimatedBuilder(
                  animation: t,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, 8 * (1 - t.value)),
                    child: child,
                  ),
                  child: child,
                ),
        );
      },
    );
  }
  return done.whenComplete(() => _openContext = null);
}

void _register(BuildContext ctx) => _openContext = ctx;

/// What the dialog and the sheet both need: page bodies' data and callbacks,
/// the page to open on and the deep-link origin.
class SettingsHost {
  const SettingsHost({
    required this.client,
    required this.instances,
    required this.active,
    required this.onRemove,
    required this.page,
    required this.onPage,
    this.onRename,
    this.onSelect,
    this.onAdd,
    this.startOnPage = false,
    this.deepLink = false,
    this.backLabel,
    this.targetId,
    this.onSearchAll,
  });

  final DaemonClient client;
  final List<Instance> instances;
  final Instance? active;
  final void Function(Instance) onRemove;
  final void Function(Instance, String)? onRename;
  final void Function(Instance)? onSelect;
  final void Function(Instance)? onAdd;
  final SettingsPage page;
  final ValueChanged<SettingsPage> onPage;
  /// The caller named a page (phone: open on it at large, not the index).
  final bool startOnPage;
  final bool deepLink;
  final String? backLabel;

  /// Page-local row id a deep link scrolls to and highlights (spec X2.5).
  final String? targetId;
  final ValueChanged<String>? onSearchAll;

  Widget body(SettingsPage page, {ValueChanged<SettingsPage>? onOpenPage}) =>
      SettingsChromeScope(
          child: SettingsSectionView(
        key: ValueKey('settings-body-${page.name}'),
        client: client,
        instances: instances,
        active: active,
        page: page,
        targetId: page == this.page ? targetId : null,
        onSelectPage: onOpenPage,
        chromeless: true,
        v5Desktop: !kMobile,
        onRemove: onRemove,
        onRename: onRename,
        onSelect: onSelect,
        onAdd: onAdd,
      ));
}

final List<SettingsPageRow> _flat = [
  for (final (_, rows) in kSettingsGroups) ...rows,
];

Widget settingsRowIcon(SettingsPageRow row, double size, Color color) =>
    row.iconData != null
        ? Icon(row.iconData, size: size, color: color)
        : AppIcon(row.icon!, size: size, color: color);

/// The desktop dialog (spec D1 to D8): centred surface2 card, list column
/// with search on the left, content pane with a 48-high header on the right.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.host});
  final SettingsHost host;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsPage _page = widget.host.page;
  late int _cursor = _flat.indexWhere((r) => r.page == _page);
  late final bool _deepLink = widget.host.deepLink;
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search settings');
  final _listFocus = FocusNode(debugLabel: 'Settings pages');
  final _headingFocus = FocusNode(debugLabel: 'Settings heading');
  final _listScroll = ScrollController();
  int _sel = 0;
  // The list's focus ring shows once the keyboard has moved its cursor.
  bool _keyed = false;

  bool get _searching => _query.text.trim().isNotEmpty;
  List<SettingsHit> get _results => searchSettingsPages(_query.text);

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() => _sel = 0));
    _searchFocus.addListener(() => setState(() {}));
    _listFocus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Deep links land on the heading so the origin line reads next (D6).
      (_deepLink ? _headingFocus : _listFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    _listFocus.dispose();
    _headingFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _open(SettingsPage page) {
    setState(() {
      _page = page;
      _cursor = _flat.indexWhere((r) => r.page == page);
      if (_query.text.isNotEmpty) _query.clear();
    });
    widget.host.onPage(page);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    final mod = kMacOS ? hw.isMetaPressed : hw.isControlPressed;
    if (k == LogicalKeyboardKey.escape) {
      if (_query.text.isNotEmpty) {
        _query.clear();
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.comma) {
      _close();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.slash && !_searchFocus.hasFocus && !mod) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    final inSearch =
        _searching && (_searchFocus.hasFocus || _listFocus.hasFocus);
    final inList = _listFocus.hasFocus;
    if (!inSearch && !inList) return KeyEventResult.ignored;
    final n = inSearch ? _results.length : _flat.length;
    if (n == 0) return KeyEventResult.ignored;
    int? to;
    final at = inSearch ? _sel : _cursor;
    if (k == LogicalKeyboardKey.arrowDown) to = math.min(n - 1, at + 1);
    if (k == LogicalKeyboardKey.arrowUp) to = math.max(0, at - 1);
    if (k == LogicalKeyboardKey.home && inList) to = 0;
    if (k == LogicalKeyboardKey.end && inList) to = n - 1;
    if (to != null) {
      setState(() {
        _keyed = true;
        inSearch ? _sel = to! : _cursor = to!;
      });
      return KeyEventResult.handled;
    }
    final enter = k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        (k == LogicalKeyboardKey.space && inList);
    if (enter) {
      _open(inSearch ? _results[_sel].row.page : _flat[_cursor].page);
      if (inSearch) _listFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final dark = AppColors.bg.computeLuminance() < 0.5;
    return Focus(
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, c) {
        // Spec D1: min(960, 90% width) x min(640, 90% height), centred.
        final w = math.min(960.0, c.maxWidth * 0.9);
        final h = math.min(640.0, c.maxHeight * 0.9);
        // The list column collapses under 800; it narrows under 1100 (D7).
        final listW =
            c.maxWidth < 800 ? 0.0 : (c.maxWidth < 1100 ? 208.0 : 240.0);
        return Center(
          child: SizedBox(
            key: const Key('settings-card'),
            width: w,
            height: h,
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: 'Settings',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.4 : 0.22),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: AppColors.surface1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.border2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (listW > 0) _listColumn(listW),
                        Expanded(child: _contentPane(listW == 0)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // Tab order (D6): Search, list, page controls, Close.
  Widget _order(double n, Widget child) =>
      FocusTraversalOrder(order: NumericFocusOrder(n), child: child);

  Widget _searchField({double? width}) => _order(
        1,
        Semantics(
          sortKey: const OrdinalSortKey(1),
          textField: true,
          label: 'Search settings',
          child: Container(
            key: const Key('settings-search'),
            width: width,
            constraints: const BoxConstraints(minHeight: 28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _searchFocus.hasFocus
                      ? AppColors.border2
                      : AppColors.border,
                ),
              ),
              child: Row(children: [
                const SizedBox(width: 8),
                Icon(PhIcons.magnifyingGlass, size: 13, color: AppColors.fg2),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _query,
                    focusNode: _searchFocus,
                    style: sans(12, color: AppColors.fg1),
                    cursorColor: AppColors.fg1,
                    cursorHeight: 14,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      final r = _results;
                      if (r.isNotEmpty) {
                        _open(r[_sel.clamp(0, r.length - 1)].row.page);
                        _listFocus.requestFocus();
                      } else {
                        _searchFocus.requestFocus();
                      }
                    },
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Search settings',
                      hintStyle: sans(12, color: AppColors.fg2),
                    ),
                  ),
                ),
                if (_query.text.isNotEmpty)
                  _ChromeButton(
                    key: const Key('settings-search-clear'),
                    icon: PhIcons.x,
                    label: 'Clear search',
                    size: 28,
                    iconSize: 12,
                    onTap: () {
                      _query.clear();
                      _searchFocus.requestFocus();
                    },
                  )
                else if (!_searchFocus.hasFocus)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ExcludeSemantics(
                      child: Text('/',
                          style: sans(11, color: AppColors.fg2)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );

  /// Spec D2: surface1 column with title, search and the grouped 13 rows.
  Widget _listColumn(double width) {
    final results = _searching ? _results : null;
    final shown = results?.map((r) => r.row.page).toSet();
    var index = -1;
    final children = <Widget>[];
    for (final (group, rows) in kSettingsGroups) {
      final visible = [
        for (final r in rows)
          if (shown == null || shown.contains(r.page)) r,
      ];
      if (visible.isEmpty) {
        index += rows.length;
        continue;
      }
      final groupRows = <Widget>[];
      for (final r in rows) {
        index++;
        if (shown != null && !shown.contains(r.page)) continue;
        final i = index;
        groupRows.add(_ListRow(
          row: r,
          selected: r.page == _page && !_searching,
          focused: _keyed && _listFocus.hasFocus && _cursor == i,
          onTap: () {
            _open(r.page);
            _listFocus.requestFocus();
          },
        ));
      }
      children.add(Semantics(
        explicitChildNodes: true,
        label: group,
        container: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ExcludeSemantics(
                      child: Text(group,
                          style: sans(11,
                              weight: W.label, color: AppColors.fg3)),
                    ),
                  ),
                ),
              ),
              ...groupRows,
            ],
          ),
        ),
      ));
    }
    if (shown != null && shown.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Text('No pages match',
            key: const Key('settings-list-empty'),
            style: sans(12, color: AppColors.fg3)),
      ));
    }
    return Container(
      key: const Key('settings-list'),
      width: width,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Settings',
                    style: sans(14, weight: W.label, color: AppColors.fg1)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: _searchField(),
          ),
          Expanded(
            child: _order(
              2,
              Semantics(
                sortKey: const OrdinalSortKey(2),
                label: 'Settings pages',
                explicitChildNodes: true,
                container: true,
                child: Focus(
                  focusNode: _listFocus,
                  child: RawScrollbar(
                    controller: _listScroll,
                    thickness: 3,
                    radius: const Radius.circular(2),
                    thumbColor: AppColors.fg3.withValues(alpha: 0.5),
                    child: ListView(
                      key: const Key('settings-list-rows'),
                      controller: _listScroll,
                      padding: const EdgeInsets.only(bottom: 12),
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Under 800 wide the list folds into a picker row under the header (D7).
  Widget _pickerRow() => Padding(
        key: const Key('settings-picker-row'),
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
        child: Row(children: [
          _searchField(width: 210),
          const SizedBox(width: 8),
          _order(
            2,
            Builder(
              builder: (ctx) => _TonalButton(
                key: const Key('settings-picker'),
                label: settingsPageGroup(_page),
                semanticLabel: 'Settings pages, ${settingsPageLabel(_page)}',
                trailing: PhIcons.caretDown,
                onTap: () => _showPicker(ctx),
              ),
            ),
          ),
        ]),
      );

  // X2.3: the shared app menu, grouped like the list.
  Future<void> _showPicker(BuildContext anchor) async {
    final picked = await showAppMenu<SettingsPage>(
      context,
      anchor: anchor,
      below: true,
      minWidth: 240,
      items: [
        for (final (group, rows) in kSettingsGroups) ...[
          appMenuHeading<SettingsPage>(group),
          for (final r in rows)
            appMenuRow<SettingsPage>(
              value: r.page,
              icon: r.icon ?? 'laptop',
              leading: r.iconData == null
                  ? null
                  : Icon(r.iconData, size: 16, color: AppColors.fg3),
              label: r.label,
              selected: r.page == _page,
              height: 28,
            ),
        ],
      ],
    );
    if (picked != null) _open(picked);
  }

  /// Spec D1: 48-high header (title, Esc hint, Close), hairline, then the
  /// page, the search results or the no-results state.
  Widget _contentPane(bool narrow) {
    final results = _searching ? _results : null;
    final title = results != null ? 'Search results' : settingsPageLabel(_page);
    final Widget body;
    if (results == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_deepLink && widget.host.backLabel != null) _backLine(),
          Expanded(child: widget.host.body(_page, onOpenPage: _open)),
        ],
      );
    } else if (results.isEmpty) {
      body = _noResults();
    } else {
      body = _resultList(results);
    }
    return Column(
      key: const Key('settings-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const Key('settings-header'),
          height: 48,
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 10),
            child: Row(children: [
              Expanded(
                child: Focus(
                  focusNode: _headingFocus,
                  skipTraversal: true,
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      key: const Key('settings-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(16, weight: W.label, color: AppColors.fg1),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ExcludeSemantics(
                  child: Text('Esc',
                      key: const Key('settings-esc-hint'),
                      style: sans(11, weight: W.body, color: AppColors.fg3)),
                ),
              ),
              _order(
                4,
                Semantics(
                  sortKey: const OrdinalSortKey(0),
                  child: _ChromeButton(
                    key: const Key('settings-close'),
                    icon: PhIcons.x,
                    label: 'Close settings',
                    size: 28,
                    iconSize: 14,
                    onTap: _close,
                  ),
                ),
              ),
            ]),
          ),
        ),
        Container(height: 1, color: AppColors.line),
        if (narrow) _pickerRow(),
        Expanded(
          child: _order(
            3,
            FocusTraversalGroup(
              child: Semantics(
                sortKey: const OrdinalSortKey(3),
                explicitChildNodes: true,
                child: Swap(
                  stateKey: results == null
                      ? _page
                      : (results.isEmpty ? 'none' : 'results'),
                  fill: true,
                  child: body,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _backLine() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 24, 0),
        child: Semantics(
          button: true,
          label: 'Back to ${widget.host.backLabel}',
          excludeSemantics: true,
          child: _HoverTap(
            key: const Key('settings-back-line'),
            onTap: _close,
            radius: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 8),
                Icon(PhIcons.arrowLeft, size: 13, color: AppColors.fg2),
                const SizedBox(width: 6),
                Text('Back to ${widget.host.backLabel}',
                    style: sans(12, color: AppColors.fg2)),
                const SizedBox(width: 8),
              ]),
            ),
          ),
        ),
      );

  Widget _resultList(List<SettingsHit> results) {
    final n = results.length;
    return ListView(
      key: const Key('settings-results'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Row(children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                  '$n ${n == 1 ? 'result' : 'results'} for "${_query.text.trim()}"',
                  key: const Key('settings-result-count'),
                  style: sans(12, color: AppColors.fg3)),
            ),
          ),
          Text('Enter opens, Down moves, Esc clears',
              style: sans(11, color: AppColors.fg3)),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < n; i++) ...[
          if (i > 0 && i != _sel && i - 1 != _sel)
            Container(height: 1, color: AppColors.line)
          else if (i > 0)
            const SizedBox(height: 1),
          _ResultRow(
            hit: results[i],
            selected: i == _sel,
            onTap: () {
              _open(results[i].row.page);
              _listFocus.requestFocus();
            },
          ),
        ],
      ],
    );
  }

  Widget _noResults() => Center(
        key: const Key('settings-no-results'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(PhIcons.magnifyingGlass, size: 16, color: AppColors.fg3),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text('No settings match "${_query.text.trim()}"',
                  textAlign: TextAlign.center,
                  style: sans(16, weight: W.label, color: AppColors.fg1)),
            ),
            const SizedBox(height: 6),
            Text('Try another word, or search everything in Snippet.',
                textAlign: TextAlign.center,
                style: sans(12, color: AppColors.fg3)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (widget.host.onSearchAll != null)
                _TonalButton(
                  key: const Key('settings-search-all'),
                  label: 'Search all of Snippet',
                  hint: kMacOS ? '⌘K' : 'Ctrl K',
                  onTap: () {
                    final q = _query.text.trim();
                    final go = widget.host.onSearchAll!;
                    _close();
                    go(q);
                  },
                ),
              _TonalButton(
                key: const Key('settings-browse-all'),
                label: 'Browse all settings',
                onTap: () {
                  _query.clear();
                  _listFocus.requestFocus();
                },
              ),
            ]),
          ]),
        ),
      );
}

/// List row (D2): 28 high, inset 8, radius 8; selected gets a surface2
/// plate, a 2 pt fg1 bar and a 500 label so selection is not colour alone.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.row,
    required this.selected,
    required this.focused,
    required this.onTap,
  });
  final SettingsPageRow row;
  final bool selected, focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Semantics(
          button: true,
          selected: selected,
          label: row.label,
          excludeSemantics: true,
          onTap: onTap,
          child: _HoverTap(
            key: Key('settings-row-${row.page.name}'),
            onTap: onTap,
            radius: 8,
            fill: selected ? AppColors.surface2 : null,
            ring: focused,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Stack(alignment: Alignment.centerLeft, children: [
                if (selected)
                  Positioned(
                    left: 0,
                    top: 6,
                    bottom: 6,
                    child: Container(
                      key: const Key('settings-row-bar'),
                      width: 2,
                      decoration: BoxDecoration(
                        color: AppColors.fg1,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                  const SizedBox(width: 8),
                  settingsRowIcon(
                      row, 14, selected ? AppColors.fg1 : AppColors.fg2),
                  const SizedBox(width: 10),
                  Expanded(
                    // Large text wraps the name rather than truncating it.
                    child: Text(row.label,
                        maxLines: MediaQuery.textScalerOf(context).scale(1) > 1.5
                            ? null
                            : 1,
                        overflow: MediaQuery.textScalerOf(context).scale(1) > 1.5
                            ? null
                            : TextOverflow.ellipsis,
                        style: sans(13,
                            weight: selected ? W.label : W.body,
                            color: selected ? AppColors.fg1 : AppColors.fg2)),
                  ),
                ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// Search result (D4): 52 high; name, snippet, "Group / Page" and a chevron.
class _ResultRow extends StatelessWidget {
  const _ResultRow(
      {required this.hit, required this.selected, required this.onTap});
  final SettingsHit hit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = hit.row;
    final group = settingsPageGroup(row.page);
    return Semantics(
      button: true,
      selected: selected,
      label: '${row.label}, $group',
      excludeSemantics: true,
      onTap: onTap,
      child: _HoverTap(
        key: Key('settings-result-${row.page.name}'),
        onTap: onTap,
        radius: 8,
        fill: selected ? AppColors.surface3 : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Stack(alignment: Alignment.centerLeft, children: [
            if (selected)
              Positioned(
                left: 0,
                top: 10,
                bottom: 10,
                child: Container(width: 2, color: AppColors.fg1),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.label,
                          style: sans(13,
                              weight: W.label, color: AppColors.fg1)),
                      const SizedBox(height: 2),
                      Text(hit.snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, color: AppColors.fg2)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text('$group / ${row.label}',
                    style: sans(12, color: AppColors.fg2)),
                const SizedBox(width: 8),
                Icon(PhIcons.caretRight, size: 12, color: AppColors.fg2),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Hover and press feedback by tonal step only; [ring] draws the 1.5 pt
/// fg2 keyboard focus ring (D6).
class _HoverTap extends StatefulWidget {
  const _HoverTap({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 8,
    this.fill,
    this.ring = false,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color? fill;
  final bool ring;

  @override
  State<_HoverTap> createState() => _HoverTapState();
}

class _HoverTapState extends State<_HoverTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fill = widget.fill ??
        (_hover ? AppColors.surface2.withValues(alpha: 0.6) : null);
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(widget.radius),
            border: widget.ring
                ? Border.all(color: AppColors.fg2, width: 1.5)
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Icon-only chrome control with a keyboard focus ring and a label.
class _ChromeButton extends StatefulWidget {
  const _ChromeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 28,
    this.iconSize = 14,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size, iconSize;

  @override
  State<_ChromeButton> createState() => _ChromeButtonState();
}

class _ChromeButtonState extends State<_ChromeButton> {
  bool _focus = false, _hover = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.label,
          child: FocusableActionDetector(
            onShowFocusHighlight: (v) => setState(() => _focus = v),
            onShowHoverHighlight: (v) => setState(() => _hover = v),
            mouseCursor: SystemMouseCursors.click,
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) => widget.onTap()),
            },
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: _hover ? AppColors.surface3 : null,
                  borderRadius: BorderRadius.circular(8),
                  border: _focus
                      ? Border.all(color: AppColors.fg2, width: 1.5)
                      : null,
                ),
                child: Icon(widget.icon,
                    size: widget.iconSize, color: AppColors.fg2),
              ),
            ),
          ),
        ),
      );
}

/// 28-high tonal button (no outline), optional key hint and trailing icon.
class _TonalButton extends StatefulWidget {
  const _TonalButton({
    super.key,
    required this.label,
    required this.onTap,
    this.hint,
    this.trailing,
    this.semanticLabel,
  });
  final String label;
  final VoidCallback onTap;
  final String? hint, semanticLabel;
  final IconData? trailing;

  @override
  State<_TonalButton> createState() => _TonalButtonState();
}

class _TonalButtonState extends State<_TonalButton> {
  bool _focus = false, _hover = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.semanticLabel ?? widget.label,
        excludeSemantics: true,
        onTap: widget.onTap,
        child: FocusableActionDetector(
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          onShowHoverHighlight: (v) => setState(() => _hover = v),
          mouseCursor: SystemMouseCursors.click,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) => widget.onTap()),
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _hover ? AppColors.surface3 : AppColors.surface1,
                borderRadius: BorderRadius.circular(8),
                border: _focus
                    ? Border.all(color: AppColors.fg2, width: 1.5)
                    : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.label,
                    style: sans(12, weight: W.label, color: AppColors.fg1)),
                if (widget.hint != null) ...[
                  const SizedBox(width: 8),
                  Text(widget.hint!, style: sans(11, color: AppColors.fg3)),
                ],
                if (widget.trailing != null) ...[
                  const SizedBox(width: 6),
                  Icon(widget.trailing, size: 12, color: AppColors.fg2),
                ],
              ]),
            ),
          ),
        ),
      );
}
