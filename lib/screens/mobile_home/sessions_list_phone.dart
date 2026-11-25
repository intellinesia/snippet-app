import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mochi.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../toast_avoid.dart';
import '../../widgets.dart';
import '../session_list_row.dart' show projectLabel, sessionNeedsYou;
import '../shell_nav.dart' show sessionBusy;
import 'agents_home.dart' show SwitchRow;
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
    showAppSheet<void>(context, title: 'Sort and show',
        child: StatefulBuilder(builder: (ctx, set) {
      Widget opt(String label, bool on, VoidCallback tap) => Semantics(
            button: true,
            selected: on,
            label: label,
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                tap();
                set(() {});
                setState(() {});
                _save();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                        child: Text(label,
                            style: sans(15,
                                weight: on ? W.label : W.body,
                                color: AppColors.fg1))),
                    if (on) AppIcon('check', size: 18, color: AppColors.fg1),
                  ]),
                ),
              ),
            ),
          );
      Widget label(String t) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child:
                Text(t, style: sans(12, weight: W.label, color: AppColors.fg3)),
          );
      return Column(mainAxisSize: MainAxisSize.min, children: [
        label('Sort'),
        opt('Recent activity', !_byName, () => _byName = false),
        opt('Name', _byName, () => _byName = true),
        label('Show'),
        SwitchRow('Group by folder', _group, (v) {
          set(() => _group = v);
          setState(() {});
          _save();
        }),
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
    final names = {for (final a in widget.agents) a.id: a.displayName};
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
        ToastAvoid(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: sans(15, color: AppColors.fg1),
            cursorColor: AppColors.fg1,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surface2,
              hintText: 'Search sessions',
              hintStyle: sans(15, color: AppColors.fg3),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        )),
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
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(k,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, weight: W.label, color: AppColors.fg3)),
        ));
        final rows = groups[k]!;
        for (var i = 0; i < rows.length; i++) {
          children.add(_row(rows[i], names, last: i == rows.length - 1));
        }
      }
    } else {
      for (var i = 0; i < shown.length; i++) {
        children.add(_row(shown[i], names, last: i == shown.length - 1));
      }
    }
    children.add(const SizedBox(height: 24));
    return CollapsingRoot(
      title: 'Sessions',
      actions: [
        if (!widget.selecting) ...[
          _IconTap('sliders-horizontal', 'Filter', _openFilter),
          _IconTap(
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

class _IconTap extends StatelessWidget {
  const _IconTap(this.icon, this.label, this.onTap);
  final String icon, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
              width: 48,
              height: 48,
              child:
                  Center(child: AppIcon(icon, size: 20, color: AppColors.fg2))),
        ),
      );
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
    return MediaQuery(
      data: mq.copyWith(textScaler: scaler),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final f in SessionsFilter.values) ...[
              if (f != SessionsFilter.all) const SizedBox(width: 8),
              _Chip(f, counts[f] ?? 0, f == filter, () => onSelect(f)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.f, this.count, this.selected, this.onTap);
  final SessionsFilter f;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = _filterLabel(f);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $count',
      child: ExcludeSemantics(
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.fg1 : AppColors.surface2,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (f == SessionsFilter.needs && count > 0) ...[
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: quietAmber, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: sans(13,
                      weight: selected ? W.label : W.body,
                      color: selected ? AppColors.bg : AppColors.fg2)),
              const SizedBox(width: 6),
              Text('$count',
                  style:
                      sans(13, color: selected ? AppColors.bg : AppColors.fg3)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One session row (SE-02): 36 avatar at x16, text at x62, time at the end.
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
    final agentId = s.displayAgentId ?? 'snippet';

    Widget avatar;
    if (selecting) {
      avatar = AppIcon(selected ? 'check-circle' : 'circle',
          size: 24,
          color: selected ? AppColors.fg1 : AppColors.fg3,
          filled: selected);
    } else if (s.agentId == null && s.workerAgentId == null) {
      avatar = AppIcon('folder', size: 20, color: AppColors.fg2);
    } else {
      avatar = AgentMochi(agentId,
          size: 28,
          state: busy ? AgentCharacterState.working : AgentCharacterState.idle);
    }
    final stateWord = needs
        ? 'Needs you'
        : busy
            ? 'Working'
            : failed
                ? 'Failed'
                : 'Done';
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
            constraints: const BoxConstraints(minHeight: 56),
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.surface2, shape: BoxShape.circle),
                    child: avatar,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(15,
                                height: 20 / 15,
                                weight: W.label,
                                color: AppColors.fg1)),
                        if (needs)
                          Row(children: [
                            const QuietHand(size: 16),
                            const SizedBox(width: 4),
                            Text('Needs you',
                                style: sans(12.5,
                                    weight: W.label, color: quietAmber)),
                          ])
                        else
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12.5,
                                  height: 18 / 12.5, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  if (busy || failed) ...[
                    const SizedBox(width: 8),
                    busy
                        ? const SpinnerGlyph(size: 14)
                        : AppIcon('x', size: 14, color: AppColors.fg2),
                    const SizedBox(width: 6),
                  ] else
                    const SizedBox(width: 8),
                  Text(time, style: sans(12, color: AppColors.fg3)),
                ]),
              ),
              if (!last)
                Positioned(
                    left: 62,
                    right: 16,
                    bottom: 0,
                    child: Container(height: 1, color: AppColors.border)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A ring with a gap; spins unless reduced motion is on.
class SpinnerGlyph extends StatefulWidget {
  const SpinnerGlyph({super.key, this.size = 14});
  final double size;
  @override
  State<SpinnerGlyph> createState() => _SpinnerGlyphState();
}

class _SpinnerGlyphState extends State<SpinnerGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: RotationTransition(
          turns: _c,
          child: CustomPaint(painter: _Ring(AppColors.fg2)),
        ),
      );
}

class _Ring extends CustomPainter {
  _Ring(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2), 0, 4.6, false, p);
  }

  @override
  bool shouldRepaint(_Ring o) => o.color != color;
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
