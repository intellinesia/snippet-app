import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../mobile_kit.dart';
import '../session_list_row.dart' show projectLabel, sessionNeedsYou;
import '../shell_nav.dart' show sessionBusy;
import 'collapsing_root.dart';

/// SE-02 filters: All, Working, Needs you, Done.
enum SessionsFilter { all, working, needs, done }

/// Failed is shown only when the payload says so; today the daemon reports
/// status 'failed' or 'error' for a turn that ended badly.
bool sessionFailed(SessionInfo s) =>
    s.status == 'failed' || s.status == 'error';

/// Done = settled, completed or failed (and not needing the user).
bool sessionDone(SessionInfo s) => !sessionNeedsYou(s) && !sessionBusy(s);

/// Title rule: title, else "New session in FOLDER". The sessions payload
/// carries no first user message, so that middle step is not available.
String sessionRowTitle(SessionInfo s) {
  final t = s.title.trim();
  if (t.isNotEmpty) return t.length > 80 ? t.substring(0, 80) : t;
  final f = projectLabel(s);
  return f == 'No project' ? 'New session' : 'New session in $f';
}

String _sub(SessionInfo s) {
  final branch = (s.branch ?? '').trim();
  final base = branch.isNotEmpty ? branch : projectLabel(s);
  if (sessionFailed(s)) return 'Failed - $base';
  return base;
}

class SessionsListPrefs {
  static const sortKey = 'sessions_sort_name';
  static const groupKey = 'sessions_group_folder';
}

class QuietSessionsScreen extends StatefulWidget {
  const QuietSessionsScreen({
    super.key,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    this.onSessionActions,
    this.onNew,
    this.selecting = false,
    this.selected = const {},
    this.onToggle,
    this.onExitSelect,
    this.onSelectAll,
    this.loading = false,
  });
  final bool selecting;
  final bool loading;
  final Set<String> selected;
  final void Function(SessionInfo s)? onToggle;
  final VoidCallback? onExitSelect;
  final void Function(List<SessionInfo> shown)? onSelectAll;
  final VoidCallback? onNew;
  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(SessionInfo s)? onSessionActions;

  @override
  State<QuietSessionsScreen> createState() => _QuietSessionsScreenState();
}

class _QuietSessionsScreenState extends State<QuietSessionsScreen> {
  SessionsFilter _filter = SessionsFilter.all;
  bool _searching = false;
  bool _byName = false;
  bool _group = true;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _byName = p.getBool(SessionsListPrefs.sortKey) ?? false;
        _group = p.getBool(SessionsListPrefs.groupKey) ?? true;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(SessionsListPrefs.sortKey, _byName);
      await p.setBool(SessionsListPrefs.groupKey, _group);
    } catch (_) {}
  }

  void _openFilter() {
    showMkSheet<void>(context,
        title: 'Sort and show',
        builder: (_) => StatefulBuilder(builder: (ctx, set) {
              void apply(VoidCallback fn) {
                fn();
                set(() {});
                setState(() {});
                _save();
              }

              Widget opt(String label, bool on, VoidCallback tap) => Semantics(
                    selected: on,
                    child: MkGroupRow(
                      label: label,
                      chevron: false,
                      trailing: on
                          ? AppIcon('check', size: 20, color: AppColors.fg1)
                          : null,
                      onTap: () => apply(tap),
                    ),
                  );
              return Column(mainAxisSize: MainAxisSize.min, children: [
                MkGroup(flush: true, header: 'Sort', children: [
                  opt('Recent activity', !_byName, () => _byName = false),
                  opt('Name', _byName, () => _byName = true),
                ]),
                MkGroup(flush: true, header: 'Show', children: [
                  MkGroupRow(
                    label: 'Group by folder',
                    chevron: false,
                    trailing: MkToggle(
                        value: _group,
                        label: 'Group by folder',
                        onChanged: (v) => apply(() => _group = v)),
                    onTap: () => apply(() => _group = !_group),
                  ),
                ]),
              ]);
            }));
  }

  String _agentName(SessionInfo s, Map<String, String> names) {
    final id = s.displayAgentId ?? '';
    return names[id] ?? (id.isEmpty ? 'Snippet' : id);
  }

  bool _inFilter(SessionInfo s, SessionsFilter f) => switch (f) {
        SessionsFilter.all => true,
        SessionsFilter.working => sessionBusy(s) && !sessionNeedsYou(s),
        SessionsFilter.needs => sessionNeedsYou(s),
        SessionsFilter.done => sessionDone(s),
      };

  @override
  Widget build(BuildContext context) {
    final names = {for (final a in widget.agents) a.id: a.shortName};
    final all = [...widget.sessions];
    int count(SessionsFilter f) => all.where((s) => _inFilter(s, f)).length;
    final q = _q.text.trim().toLowerCase();
    bool hit(SessionInfo s) =>
        q.isEmpty ||
        sessionRowTitle(s).toLowerCase().contains(q) ||
        _agentName(s, names).toLowerCase().contains(q);
    final shown = all.where((s) => _inFilter(s, _filter) && hit(s)).toList();
    if (_byName) {
      shown.sort((a, b) => sessionRowTitle(a)
          .toLowerCase()
          .compareTo(sessionRowTitle(b).toLowerCase()));
    } else {
      shown.sort((a, b) => b.lastActive.compareTo(a.lastActive));
    }

    final children = <Widget>[
      if (widget.selecting)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
          child: Row(children: [
            IconBtn('x',
                size: 48,
                iconSize: 20,
                tooltip: 'Cancel',
                onTap: widget.onExitSelect),
            Expanded(
              child: Text(
                  widget.selected.isEmpty
                      ? 'Select sessions'
                      : '${widget.selected.length} selected',
                  style: sans(16, weight: W.label, color: AppColors.fg1)),
            ),
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelectAll?.call(shown),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: _SelectAllText(),
              ),
            ),
          ]),
        )
      else
        const LargeTitle('Sessions'),
      if (_searching)
        MkSearchField(
            controller: _q,
            hint: 'Search sessions',
            onChanged: (_) => setState(() {})),
      if (all.isNotEmpty)
        _ChipRow(
          filter: _filter,
          counts: {for (final f in SessionsFilter.values) f: count(f)},
          onSelect: (f) => setState(() => _filter = f),
        ),
    ];

    if (widget.loading && all.isEmpty) {
      children.add(const ListSkeleton());
    } else if (shown.isEmpty) {
      children.add(_Empty(
        none: all.isEmpty,
        filter: _filter,
        onNew: widget.onNew,
      ));
    } else if (_group) {
      final groups = <String, List<SessionInfo>>{};
      for (final s in shown) {
        groups.putIfAbsent(projectLabel(s), () => []).add(s);
      }
      final keys = groups.keys.toList()
        ..sort((a, b) => groups[b]!
            .map((s) => s.lastActive)
            .reduce(math.max)
            .compareTo(groups[a]!.map((s) => s.lastActive).reduce(math.max)));
      for (final k in keys) {
        children.add(MkSection(k));
        final rows = groups[k]!;
        children.add(MkList(children: [
          for (var i = 0; i < rows.length; i++)
            _row(rows[i], names, last: i == rows.length - 1),
        ]));
      }
    } else {
      children.add(MkList(children: [
        for (var i = 0; i < shown.length; i++)
          _row(shown[i], names, last: i == shown.length - 1),
      ]));
    }
    children.add(const SizedBox(height: 24));
    return CollapsingRoot(
      title: 'Sessions',
      actions: [
        if (!widget.selecting) ...[
          MkIconTap('sliders-horizontal', 'Filter', _openFilter),
          MkIconTap(
              'search',
              'Search',
              () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _q.clear();
                  })),
        ],
      ],
      child: ListView(children: children),
    );
  }

  Widget _row(SessionInfo s, Map<String, String> names, {required bool last}) {
    final sel = widget.selecting && widget.selected.contains(s.id);
    return SessionRowPhone(
      session: s,
      selecting: widget.selecting,
      selected: sel,
      last: last,
      onTap: () =>
          widget.selecting ? widget.onToggle?.call(s) : widget.onOpenSession(s),
      onLongPress: widget.onSessionActions == null || widget.selecting
          ? null
          : () => widget.onSessionActions!(s),
    );
  }
}

class _SelectAllText extends StatelessWidget {
  const _SelectAllText();
  @override
  Widget build(BuildContext context) => Text('Select all',
      style: sans(13, weight: W.label, color: AppColors.fg1));
}

String _filterLabel(SessionsFilter f) => switch (f) {
      SessionsFilter.all => 'All',
      SessionsFilter.working => 'Working',
      SessionsFilter.needs => 'Needs you',
      SessionsFilter.done => 'Done',
    };

class _ChipRow extends StatelessWidget {
  const _ChipRow(
      {required this.filter, required this.counts, required this.onSelect});
  final SessionsFilter filter;
  final Map<SessionsFilter, int> counts;
  final ValueChanged<SessionsFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scaler = mq.textScaler.clamp(maxScaleFactor: 1.35);
    // Needs you shows only while something needs the user (or it is selected).
    final visible = [
      for (final f in SessionsFilter.values)
        if (f != SessionsFilter.needs || (counts[f] ?? 0) > 0 || f == filter) f,
    ];
    return MediaQuery(
      data: mq.copyWith(textScaler: scaler),
      child: MkFilterGroup<SessionsFilter>(
        padding: MK.filterPad,
        options: [
          for (final f in visible)
            MkFilter(f, _filterLabel(f), count: counts[f] ?? 0),
        ],
        selected: filter,
        onSelect: onSelect,
      ),
    );
  }
}

/// One session row: the state mark leads, title over a mono branch, time on
/// the right. No folder tiles.
class SessionRowPhone extends StatelessWidget {
  const SessionRowPhone({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.last = false,
  });
  final SessionInfo session;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting, selected, last;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final needs = sessionNeedsYou(s);
    final busy = sessionBusy(s) && !needs;
    final failed = sessionFailed(s) && !needs && !busy;
    final title = sessionRowTitle(s);
    final time = relativeTime(s.lastActive);
    final sub = _sub(s);
    final ch = s.changes ?? s.totalChanges;
    final diff = ch == null || (ch.added == 0 && ch.removed == 0)
        ? null
        : '+${ch.added} \u2212${ch.removed}';

    Widget mark;
    if (selecting) {
      mark = AppIcon(selected ? 'check-circle' : 'circle',
          size: 24,
          color: selected ? AppColors.fg1 : AppColors.fg3,
          filled: selected);
    } else {
      mark = MkStateMark(needs
          ? MkState.needsYou
          : busy
              ? MkState.working
              : failed
                  ? MkState.failed
                  : MkState.done);
    }
    final stateWord = needs
        ? 'Needs you'
        : busy
            ? 'Working'
            : failed
                ? 'Failed'
                : 'Completed';
    // Board rows: iPhone 24 slot, 12 gap, 64 tall; Android tiles 40 slot,
    // 14 gap, 68 tall. The mark centres on the whole row.
    final a = kAndroidLook;
    final left = a ? 16.0 : MK.gutter;
    final markSlot = a ? 40.0 : 24.0, gap = a ? 14.0 : 12.0;
    final titleText = Text(title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: a ? mkRowTitle() : sans(15, weight: W.label, height: 1.4));
    final timeText = Text(time, style: mkTime().copyWith(height: 1.4));
    final subText = needs
        ? Text('Needs you',
            style: sans(13, weight: W.label, height: 1.4, color: MK.amber))
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: sub),
              if (diff != null) ...[
                TextSpan(text: ' · ', style: TextStyle(color: AppColors.fg4)),
                TextSpan(text: diff),
              ],
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mkMonoSub(),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $stateWord, $sub, $time',
      child: ExcludeSemantics(
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: a ? 68 : 64),
            // Passthrough keeps the min height so the content centres.
            child: Stack(fit: StackFit.passthrough, children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: left, vertical: 10),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: markSlot, child: Center(child: mark)),
                      SizedBox(width: gap),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (a)
                              titleText
                            else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: titleText),
                                  const SizedBox(width: 8),
                                  timeText,
                                ],
                              ),
                            const SizedBox(height: 2),
                            subText,
                          ],
                        ),
                      ),
                      if (a) ...[
                        const SizedBox(width: 14),
                        Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: timeText),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!last && !a)
                Positioned(
                    left: left + markSlot + gap,
                    right: left,
                    bottom: 0,
                    child: Container(height: 0.5, color: MK.hairline)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The working glyph on phone: the morph, the one working indicator.
class SpinnerGlyph extends StatelessWidget {
  const SpinnerGlyph({super.key, this.size = 14});
  final double size;
  @override
  Widget build(BuildContext context) => MkMorph(size: size);
}

class _Empty extends StatelessWidget {
  const _Empty({required this.none, required this.filter, this.onNew});
  final bool none;
  final SessionsFilter filter;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final head = none ? 'No sessions' : 'Nothing here';
    final sub = none
        ? 'Start one from a folder on your Mac.'
        : 'No ${_filterLabel(filter).toLowerCase()} sessions.';
    return EmptyState(
      icon: none ? 'chat' : 'layers',
      title: head,
      body: sub,
      action: none && onNew != null
          ? StateButton('New session', onTap: onNew)
          : null,
    );
  }
}
