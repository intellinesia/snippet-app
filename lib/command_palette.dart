import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

enum PaletteKind {
  recent('Recent'),
  session('This chat'),
  command('Go to'),
  tab('Open tabs'),
  chat('Chats'),
  file('Files'),
  pr('Pull requests'),
  task('Tasks'),
  agent('Agents'),
  artifact('Artifacts'),
  terminal('Terminals'),
  setting('Settings');

  const PaletteKind(this.label);
  final String label;
}

class PaletteItem {
  final String id;
  final PaletteKind kind;
  final String icon;
  final String title;
  final String subtitle;
  final String shortcut;
  final List<String> keywords;
  final VoidCallback run;

  const PaletteItem({
    required this.id,
    required this.kind,
    required this.icon,
    required this.title,
    required this.run,
    this.subtitle = '',
    this.shortcut = '',
    this.keywords = const [],
  });
}

class PaletteSource {
  final PaletteKind kind;
  final Future<List<PaletteItem>> Function() load;
  const PaletteSource(this.kind, this.load);
}

const _prefixes = <String, Set<PaletteKind>>{
  '>': {PaletteKind.session, PaletteKind.command, PaletteKind.setting},
  '@': {PaletteKind.agent},
  '#': {PaletteKind.pr},
  '/': {PaletteKind.file},
};

const _recentKey = 'palette.recent';
const _recentMax = 8;

Future<void> showCommandPalette(
  BuildContext context, {
  required List<PaletteItem> items,
  List<PaletteSource> sources = const [],
}) {
  Widget body() => _Palette(items: items, sources: sources);
  final view = View.of(context);
  final desktop =
      view.physicalSize.width / view.devicePixelRatio >= kDesktopBreakpoint;
  if (desktop) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'palette',
      barrierColor: Colors.black.withValues(alpha: .35),
      transitionDuration: Motion.quick,
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(S.s24, 96, S.s24, S.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 650),
            child: _solidFrame(body()),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final c = CurvedAnimation(parent: anim, curve: Motion.enter);
        return FadeTransition(
            opacity: c,
            child: ScaleTransition(
                scale: Tween(begin: 0.98, end: 1.0).animate(c), child: child));
      },
    );
  }
  return showModalBottomSheet(
    sheetAnimationStyle: sheetMotion,
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      final mq = MediaQuery.of(context);
      final available = mq.size.height - mq.viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: available * 0.85),
          child: _frame(body()),
        ),
      );
    },
  );
}

Widget _frame(Widget child) {
  final radius = BorderRadius.vertical(top: Radius.circular(R.sheetTop));
  return ClipRRect(
    borderRadius: radius,
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border(top: BorderSide(color: AppColors.border2)),
      ),
      child: Material(color: AppColors.glassSurface, child: child),
    ),
  );
}

Widget _solidFrame(Widget child) {
  final radius = BorderRadius.all(Radius.circular(R.lg));
  return DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface1,
      borderRadius: radius,
      border: Border.all(color: AppColors.lineStrong),
      boxShadow: overlayShadow,
    ),
    child: ClipRRect(
      borderRadius: radius,
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}

const _desktopOrder = [
  PaletteKind.session,
  PaletteKind.task,
  PaletteKind.agent,
  PaletteKind.command,
];

double? fuzzyScore(String query, String text) {
  if (query.isEmpty) return 0;
  if (text.isEmpty) return null;
  final t = text.toLowerCase();
  final at = t.indexOf(query);
  if (at >= 0) {
    final boundary = at == 0 || _isBoundary(t.codeUnitAt(at - 1));
    return 100 +
        (boundary ? 40 : 0) +
        (at == 0 ? 20 : 0) -
        math.min(at, 30) -
        math.min(t.length - query.length, 40) * 0.25;
  }
  var score = 0.0;
  var ti = 0;
  var last = -2;
  for (var qi = 0; qi < query.length; qi++) {
    final c = query.codeUnitAt(qi);
    var found = -1;
    while (ti < t.length) {
      if (t.codeUnitAt(ti) == c) {
        found = ti;
        ti++;
        break;
      }
      ti++;
    }
    if (found < 0) return null;
    if (found == last + 1) {
      score += 6;
    } else if (found == 0 || _isBoundary(t.codeUnitAt(found - 1))) {
      score += 8;
    } else {
      score += 1;
    }
    last = found;
  }
  return score - math.min(t.length, 60) * 0.1;
}

bool _isBoundary(int c) =>
    c == 0x20 || c == 0x2F || c == 0x2D || c == 0x5F || c == 0x2E || c == 0x3A;

class _Scored {
  final PaletteItem item;
  final double score;
  const _Scored(this.item, this.score);
}

class _Palette extends StatefulWidget {
  final List<PaletteItem> items;
  final List<PaletteSource> sources;
  const _Palette({required this.items, required this.sources});
  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  static double get _rowHeight => kMobile ? 44.0 : 34.0;
  static double get _headerHeight => kMobile ? 30.0 : 32.0;

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final Map<PaletteKind, List<PaletteItem>> _loaded = {};
  final Set<PaletteKind> _loading = {};
  List<String> _recent = const [];
  int _selected = 0;
  List<Object> _rows = const [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _selected = 0));
    _loadRecent();
    for (final s in widget.sources) {
      _loading.add(s.kind);
      s.load().then((items) {
        if (!mounted) return;
        setState(() {
          _loaded[s.kind] = items;
          _loading.remove(s.kind);
        });
      }, onError: (_) {
        if (mounted) setState(() => _loading.remove(s.kind));
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final r = p.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = r);
    } catch (_) {}
  }

  Future<void> _remember(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final r = [
        id,
        ...(p.getStringList(_recentKey) ?? const <String>[])
            .where((e) => e != id),
      ];
      await p.setStringList(_recentKey, r.take(_recentMax).toList());
    } catch (_) {}
  }

  Iterable<PaletteItem> get _all sync* {
    yield* widget.items;
    for (final list in _loaded.values) {
      yield* list;
    }
  }

  (Set<PaletteKind>?, String) get _parsed {
    final raw = _ctrl.text.trimLeft();
    if (raw.isNotEmpty) {
      final kinds = _prefixes[raw[0]];
      if (kinds != null) return (kinds, raw.substring(1).trim().toLowerCase());
    }
    return (null, raw.trim().toLowerCase());
  }

  double? _score(PaletteItem item, List<String> tokens) {
    var total = 0.0;
    for (final tok in tokens) {
      var best = fuzzyScore(tok, item.title);
      final sub = fuzzyScore(tok, item.subtitle);
      if (sub != null && (best == null || sub * 0.6 > best)) best = sub * 0.6;
      for (final k in item.keywords) {
        final ks = fuzzyScore(tok, k);
        if (ks != null && (best == null || ks * 0.8 > best)) best = ks * 0.8;
      }
      if (best == null) return null;
      total += best;
    }
    if (_recent.contains(item.id)) total += 15;
    return total;
  }

  int _capFor(PaletteKind k) => switch (k) {
        PaletteKind.file => 20,
        PaletteKind.chat => 8,
        _ => 10,
      };

  List<Object> _buildRows() {
    final (kinds, q) = _parsed;
    final rows = <Object>[];
    if (q.isEmpty && kinds == null) {
      final byId = {for (final i in _all) i.id: i};
      final recent = [
        for (final id in _recent)
          if (byId[id] != null) byId[id]!,
      ];
      final shown = <String>{};
      void section(PaletteKind label, Iterable<PaletteItem> items, int cap) {
        final list =
            items.where((i) => !shown.contains(i.id)).take(cap).toList();
        if (list.isEmpty) return;
        rows.add(label);
        rows.addAll(list);
        shown.addAll(list.map((e) => e.id));
      }

      Iterable<PaletteItem> of(PaletteKind k) =>
          widget.items.where((i) => i.kind == k);
      section(PaletteKind.recent, recent, kMobile ? _recentMax : 2);
      section(PaletteKind.session, of(PaletteKind.session), 6);
      if (!kMobile) {
        section(PaletteKind.command, of(PaletteKind.command), 20);
        section(PaletteKind.setting,
            _all.where((i) => i.kind == PaletteKind.setting), 2);
        return rows;
      }
      section(PaletteKind.tab, of(PaletteKind.tab), 6);
      section(PaletteKind.chat, of(PaletteKind.chat), 5);
      // A taste of each kind, so the empty palette shows what it can reach.
      for (final k in const [
        PaletteKind.pr,
        PaletteKind.task,
        PaletteKind.agent,
        PaletteKind.setting,
      ]) {
        section(k, _all.where((i) => i.kind == k), 2);
      }
      section(PaletteKind.command, of(PaletteKind.command), 20);
      return rows;
    }

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final groups = <PaletteKind, List<_Scored>>{};
    for (final item in _all) {
      if (kinds != null && !kinds.contains(item.kind)) continue;
      final s = tokens.isEmpty ? 0.0 : _score(item, tokens);
      if (s == null) continue;
      (groups[item.kind] ??= []).add(_Scored(item, s));
    }
    double best(List<_Scored> l) => l.map((e) => e.score).reduce(math.max);
    final ordered = groups.entries.toList()
      ..sort((a, b) {
        if (!kMobile) {
          final ia = _desktopOrder.indexOf(a.key);
          final ib = _desktopOrder.indexOf(b.key);
          if (ia >= 0 || ib >= 0) {
            return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
          }
        }
        return best(b.value).compareTo(best(a.value));
      });
    for (final g in ordered) {
      if (tokens.isNotEmpty) {
        g.value.sort((a, b) => b.score.compareTo(a.score));
      }
      rows.add(g.key);
      rows.addAll(g.value.take(_capFor(g.key)).map((e) => e.item));
    }
    return rows;
  }

  List<PaletteItem> get _selectable => _rows.whereType<PaletteItem>().toList();

  void _move(int delta) {
    final n = _selectable.length;
    if (n == 0) return;
    setState(() => _selected = ((_selected + delta) % n + n) % n);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
  }

  void _ensureVisible() {
    if (!_scroll.hasClients) return;
    var y = 0.0;
    var idx = -1;
    for (final r in _rows) {
      if (r is PaletteKind) {
        y += _headerHeight;
        continue;
      }
      idx++;
      if (idx == _selected) break;
      y += _rowHeight;
    }
    final view = _scroll.position.viewportDimension;
    final off = _scroll.offset;
    final max = _scroll.position.maxScrollExtent;
    if (y - _headerHeight < off) {
      _scroll.jumpTo(math.max(0, y - _headerHeight).clamp(0, max).toDouble());
    } else if (y + _rowHeight + 6 > off + view) {
      _scroll.jumpTo((y + _rowHeight + 6 - view).clamp(0, max).toDouble());
    }
  }

  void _run(PaletteItem item) {
    _remember(item.id);
    Navigator.pop(context);
    item.run();
  }

  void _runSelected() {
    final list = _selectable;
    if (list.isEmpty) return;
    _run(list[_selected.clamp(0, list.length - 1)]);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    _rows = _buildRows();
    final selectable = _selectable;
    if (_selected >= selectable.length) _selected = 0;
    final (kinds, q) = _parsed;
    final busy = _loading.isNotEmpty && (q.isNotEmpty || kinds != null);
    var index = -1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _move(1),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): _runSelected,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _runSelected,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        kMobile ? _mobileSearch(busy) : _desktopSearch(busy),
        Flexible(
          child: selectable.isEmpty
              ? Padding(
                  padding: EdgeInsets.fromLTRB(S.s16, S.s20, S.s16, S.s24),
                  child: Center(
                      heightFactor: 1,
                      child: Text(busy ? 'Searching…' : 'No matches',
                          style: TS.meta())),
                )
              : ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                      kMobile ? S.s12 : S.s6, 0, kMobile ? S.s12 : S.s6, S.s8),
                  children: [
                    for (final r in _rows)
                      if (r is PaletteKind)
                        _header(r)
                      else
                        _row(r as PaletteItem, ++index),
                  ],
                ),
        ),
        if (!kMobile) _footer(),
      ]),
    );
  }

  Widget _mobileSearch(bool busy) {
    return Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: S.s12),
      margin: EdgeInsets.fromLTRB(S.s16, S.s16, S.s16, S.s8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.of(12)),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(children: [
        AppIcon('search', size: 16, color: AppColors.fg3),
        SizedBox(width: S.s8),
        Expanded(
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            cursorColor: AppColors.accent,
            style: sans(14, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search or jump to anything',
              hintStyle: sans(14, color: AppColors.fg4),
            ),
          ),
        ),
        if (busy)
          Padding(
            padding: EdgeInsets.only(left: S.s8),
            child: DelayedSpinner(size: 12),
          ),
      ]),
    );
  }

  Widget _desktopSearch(bool busy) {
    Widget chip(String prefix, String label) => GestureDetector(
          onTap: () {
            _ctrl.value = TextEditingValue(
              text: '$prefix ',
              selection: TextSelection.collapsed(offset: prefix.length + 1),
            );
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              height: 20,
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Text('$prefix $label', style: sans(11, color: AppColors.fg3)),
            ),
          ),
        );
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineStrong)),
      ),
      child: Row(children: [
        AppIcon('search', size: 16, color: AppColors.fg3),
        SizedBox(width: S.of(10)),
        Expanded(
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            cursorColor: AppColors.accent,
            style: sans(15, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search or jump to anything',
              hintStyle: sans(15, color: AppColors.fg4),
            ),
          ),
        ),
        if (busy)
          Padding(
            padding: EdgeInsets.only(right: S.s8),
            child: DelayedSpinner(size: 12),
          ),
        chip('>', 'commands'),
        chip('@', 'agents'),
        chip('#', 'PRs'),
        chip('/', 'files'),
      ]),
    );
  }

  Widget _header(PaletteKind k) => SizedBox(
        height: _headerHeight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              kMobile ? S.s4 : S.of(10), S.of(10), S.of(10), S.s2),
          child: kMobile
              ? Text(k.label, style: sans(12, color: AppColors.fg3))
              : Text(k.label,
                  style: sans(11, weight: W.title, color: AppColors.fg4)),
        ),
      );

  Widget _kbd(String k) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(k, style: sans(11, color: AppColors.fg4)),
      );

  Widget _row(PaletteItem item, int i) {
    final selected = i == _selected;
    final keys = item.shortcut.isEmpty
        ? const <String>[]
        : item.shortcut.split(RegExp(r'[\s+]+')).where((k) => k.isNotEmpty);
    return MouseRegion(
      onHover: (_) {
        if (_selected != i) setState(() => _selected = i);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _run(item),
        child: Container(
          height: _rowHeight,
          padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s8 : S.of(10)),
          decoration: BoxDecoration(
            color: selected
                ? (kMobile ? AppColors.surface3 : AppColors.surface2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kMobile ? R.of(10) : R.md),
          ),
          child: Row(children: [
            SizedBox(
              width: kMobile ? 22 : 18,
              child: Center(
                child: AppIcon(item.icon,
                    size: kMobile ? 15 : 14, color: AppColors.fg3),
              ),
            ),
            SizedBox(width: S.of(10)),
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 14 : 13, color: AppColors.fg1)),
                ),
                if (item.subtitle.isNotEmpty)
                  Flexible(
                    child: Padding(
                      padding: EdgeInsets.only(left: kMobile ? S.s8 : S.of(10)),
                      child: Text(item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(kMobile ? 12 : 11.5, color: AppColors.fg4)),
                    ),
                  ),
              ]),
            ),
            if (kMobile && item.shortcut.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(left: S.s8),
                child:
                    Text(item.shortcut, style: sans(11, color: AppColors.fg4)),
              )
            else
              for (final k in keys) _kbd(k),
            if (!kMobile && selected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('↵', style: sans(13, color: AppColors.fg4)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _footer() {
    Widget hint(List<String> keys, String label) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final k in keys) _kbd(k),
            SizedBox(width: S.s6),
            Text(label, style: sans(11.5, color: AppColors.fg4)),
          ]),
        );
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.lineStrong))),
      child: Row(children: [
        hint(const ['↑', '↓'], 'move'),
        hint(const ['↵'], 'open'),
        hint(const ['esc'], 'close'),
        const Spacer(),
        Flexible(
          child: Text('Type to search tabs, chats, files, PRs, tasks, agents',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(11.5, color: AppColors.fg4)),
        ),
      ]),
    );
  }
}
