import 'package:flutter/material.dart';

import '../../menu_widgets.dart' show relativeTime;
import '../../mochi.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../session_list_row.dart' show sessionNeedsYou;
import '../shell_nav.dart' show sessionBusy;
import 'home_data.dart';

/// Quiet Home and Sessions: two calm lists, no hero, no shader, no cards.
/// Both read the same sessions; Home shows only what matters now.
class QuietPlaceHeader extends StatelessWidget {
  const QuietPlaceHeader(
      {super.key, required this.title, this.onSearch, this.trailing});
  final String title;
  final VoidCallback? onSearch;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s12, S.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (onSearch != null)
              _IconTap('search', 'Search', onSearch!),
            if (trailing != null) trailing!,
          ]),
          Text(title,
              style: sans(22,
                  height: 28 / 22, weight: W.title, color: AppColors.fg1)),
        ]),
      );
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
              child: Center(
                  child: AppIcon(icon, size: 22, color: AppColors.fg1))),
        ),
      );
}

String _agentName(SessionInfo s, Map<String, String> names) {
  final id = s.displayAgentId ?? '';
  return names[id] ?? (id.isEmpty ? 'Snippet' : id);
}

Widget _stateMark(SessionInfo s) {
  if (sessionNeedsYou(s)) return const QuietHand(size: 20);
  if (sessionBusy(s)) {
    return AppIcon('circle', size: 20, color: AppColors.fg1);
  }
  return SizedBox.square(
      dimension: 20, child: CustomPaint(painter: _Dashed(AppColors.fg4)));
}

String _stateWord(SessionInfo s) => sessionNeedsYou(s)
    ? 'Needs you'
    : sessionBusy(s)
        ? 'Running'
        : s.settled
            ? 'Completed'
            : 'Idle';

class QuietHomeScreen extends StatelessWidget {
  const QuietHomeScreen({
    super.key,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    required this.onOpenSessions,
    required this.onSettings,
    required this.onSearch,
    this.onNew,
    this.onDecide,
    this.offline,
  });

  final Widget? offline;
  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final void Function(SessionInfo s) onOpenSession;
  final VoidCallback onOpenSessions;
  final VoidCallback onSettings;
  final VoidCallback onSearch;
  final VoidCallback? onNew;
  final Future<bool> Function(SessionInfo s, bool approve)? onDecide;

  @override
  Widget build(BuildContext context) {
    final names = {for (final a in agents) a.id: a.displayName};
    final asks = needsYouItems(sessions);
    final working = [
      for (final s in sessions)
        if (!s.settled && sessionBusy(s) && !sessionNeedsYou(s)) s
    ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final dayStart = DateTime.now()
            .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
            .millisecondsSinceEpoch ~/
        1000;
    final finished = sessions
        .where((s) =>
            !sessionBusy(s) && !sessionNeedsYou(s) && s.lastActive >= dayStart)
        .length;
    return ListView(
      padding: EdgeInsets.only(bottom: S.s24),
      children: [
        QuietPlaceHeader(
          title: 'Home',
          onSearch: onSearch,
          trailing: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSettings,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.surface2, shape: BoxShape.circle),
                  child: Text('B',
                      style: sans(13, weight: W.label, color: AppColors.fg1)),
                ),
              ),
            ),
          ),
        ),
        if (offline != null) offline!,
        if (asks.isEmpty && working.isEmpty)
          _EmptyHome(finished: finished, onNew: onNew, onOpenSessions: onOpenSessions)
        else if (asks.isEmpty)
          QuietRow(
            title: 'Nothing needs you',
            leading: AppIcon('check-circle', size: 20, color: AppColors.fg3),
          )
        else ...[
          QuietSectionLabel('Needs you', count: asks.length),
          for (final a in asks) _Ask(item: a, names: names, onOpen: onOpenSession, onDecide: onDecide),
        ],
        if (working.isNotEmpty) ...[
          QuietSectionLabel('Working', count: working.length),
          for (final s in working)
            QuietRow(
              title: s.title.isEmpty ? 'Untitled session' : s.title,
              titleLines: 2,
              sub: '${_agentName(s, names)} · Working',
              meta: relativeTime(s.lastActive),
              leading: AgentMochi(s.displayAgentId ?? 'snippet', size: 24),
              onTap: () => onOpenSession(s),
            ),
        ],
        if (finished > 0 && !(asks.isEmpty && working.isEmpty)) ...[
          SizedBox(height: S.s8),
          QuietRow(
            title: '$finished finished today',
            leading: AppIcon('check-circle', size: 20, color: AppColors.fg3),
            trailing:
                AppIcon('chevron-right', size: 16, color: AppColors.fg4),
            onTap: onOpenSessions,
          ),
        ],
      ],
    );
  }
}

class _Ask extends StatefulWidget {
  const _Ask(
      {required this.item,
      required this.names,
      required this.onOpen,
      required this.onDecide});
  final AskItem item;
  final Map<String, String> names;
  final void Function(SessionInfo) onOpen;
  final Future<bool> Function(SessionInfo, bool)? onDecide;

  @override
  State<_Ask> createState() => _AskState();
}

class _AskState extends State<_Ask> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    await widget.onDecide!(widget.item.session, approve);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.item.session;
    final canDecide =
        widget.item.kind == AskKind.approval && widget.onDecide != null;
    return Container(
      margin: EdgeInsets.fromLTRB(S.s16, 0, S.s16, S.s8),
      padding: EdgeInsets.all(S.s12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.of(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpen(s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: EdgeInsets.only(top: S.s2),
                child: const QuietHand()),
            SizedBox(width: S.s12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title.isEmpty ? 'Untitled session' : s.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: sans(15,
                            height: 20 / 15,
                            weight: W.label,
                            color: AppColors.fg1)),
                    Text(
                        '${_agentName(s, widget.names)} · ${switch (widget.item.kind) {
                          AskKind.approval => 'Asks to run something',
                          AskKind.question => 'Asked you a question',
                          AskKind.handoff => 'Ready for review',
                        }}',
                        style: sans(13, height: 18 / 13, color: AppColors.fg3)),
                  ]),
            ),
            SizedBox(width: S.s8),
            Text(relativeTime(s.lastActive),
                style: sans(12, height: 16 / 12, color: AppColors.fg3)),
          ]),
        ),
        SizedBox(height: S.s12),
        Row(children: [
          if (canDecide) ...[
            Btn('Approve',
                small: true,
                onTap: _busy ? null : () => _decide(true)),
            SizedBox(width: S.s8),
          ],
          Btn(canDecide ? 'Reply' : 'Open',
              small: true,
              variant: BtnVariant.secondary,
              onTap: () => widget.onOpen(s)),
        ]),
      ]),
    );
  }
}

enum _Filter { all, needs, running }

class QuietSessionsScreen extends StatefulWidget {
  const QuietSessionsScreen({
    super.key,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    this.onSessionActions,
  });
  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(SessionInfo s)? onSessionActions;

  @override
  State<QuietSessionsScreen> createState() => _QuietSessionsScreenState();
}

class _QuietSessionsScreenState extends State<QuietSessionsScreen> {
  _Filter _filter = _Filter.all;
  bool _searching = false;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final a in widget.agents) a.id: a.displayName};
    final all = [...widget.sessions]
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    final needs = all.where(sessionNeedsYou).length;
    final running = all.where((s) => sessionBusy(s) && !sessionNeedsYou(s)).length;
    final q = _q.text.trim().toLowerCase();
    bool hit(SessionInfo s) =>
        q.isEmpty ||
        s.title.toLowerCase().contains(q) ||
        _agentName(s, names).toLowerCase().contains(q);
    final shown = switch (_filter) {
      _Filter.all => all,
      _Filter.needs => all.where(sessionNeedsYou).toList(),
      _Filter.running =>
        all.where((s) => sessionBusy(s) && !sessionNeedsYou(s)).toList(),
    }.where(hit).toList();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/ 1000;
    final yesterday = today - 86400;
    String bucket(SessionInfo s) => s.lastActive >= today
        ? 'Today'
        : s.lastActive >= yesterday
            ? 'Yesterday'
            : 'Earlier';
    final children = <Widget>[
      QuietPlaceHeader(
          title: 'Sessions',
          onSearch: () => setState(() {
                _searching = !_searching;
                if (!_searching) _q.clear();
              })),
      if (_searching)
        Padding(
          padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
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
              hintStyle: sans(15, color: AppColors.fg4),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: S.s12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.of(12)),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
      Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, 0),
        child: Wrap(spacing: S.s8, children: [
          _Chip('All', all.length, _filter == _Filter.all,
              () => setState(() => _filter = _Filter.all)),
          _Chip('Needs you', needs, _filter == _Filter.needs,
              () => setState(() => _filter = _Filter.needs)),
          _Chip('Running', running, _filter == _Filter.running,
              () => setState(() => _filter = _Filter.running)),
        ]),
      ),
    ];
    String? last;
    for (final s in shown) {
      final b = bucket(s);
      if (b != last) {
        children.add(QuietSectionLabel(b));
        last = b;
      }
      children.add(QuietRow(
        title: s.title.isEmpty ? 'Untitled session' : s.title,
        titleLines: 2,
        sub: '${_agentName(s, names)} · ${_stateWord(s)}',
        meta: relativeTime(s.lastActive),
        leading: _stateMark(s),
        onTap: () => widget.onOpenSession(s),
        onLongPress: widget.onSessionActions == null
            ? null
            : () => widget.onSessionActions!(s),
      ));
    }
    if (shown.isEmpty) {
      children.add(Padding(
        padding: EdgeInsets.all(S.s32),
        child: Text('No sessions here.',
            textAlign: TextAlign.center,
            style: sans(14, color: AppColors.fg3)),
      ));
    }
    children.add(SizedBox(height: S.s24));
    return ListView(children: children);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.count, this.selected, this.onTap);
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: S.s12),
          decoration: BoxDecoration(
            color: selected ? AppColors.fg1 : AppColors.surface2,
            borderRadius: BorderRadius.circular(R.of(18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: sans(14,
                    weight: selected ? W.label : W.body,
                    color: selected ? AppColors.bg : AppColors.fg1)),
            SizedBox(width: S.s6),
            Text('$count',
                style: sans(14,
                    color: selected ? AppColors.bg : AppColors.fg3)),
          ]),
        ),
      );
}

/// Idle mark: a dashed ring (the icon font has no dashed circle).
class _Dashed extends CustomPainter {
  _Dashed(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final r = size.width / 2 - 1.5;
    const n = 10;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * 3.141592653589793 / n;
      canvas.drawArc(
          Rect.fromCircle(center: size.center(Offset.zero), radius: r),
          a,
          2 * 3.141592653589793 / n * 0.55,
          false,
          paint);
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome(
      {required this.finished, required this.onNew, required this.onOpenSessions});
  final int finished;
  final VoidCallback? onNew;
  final VoidCallback onOpenSessions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s32, S.s40 * 2, S.s32, S.s24),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
          child: AppIcon('check-circle', size: 28, color: AppColors.fg2),
        ),
        SizedBox(height: S.s16),
        Text('Nothing needs you',
            textAlign: TextAlign.center,
            style: sans(20, weight: W.label, color: AppColors.fg1)),
        SizedBox(height: S.s8),
        Text('No agent is working. Start something, or ask Lead what is next.',
            textAlign: TextAlign.center,
            style: sans(14, color: AppColors.fg3, height: 1.4)),
        if (onNew != null) ...[
          SizedBox(height: S.s24),
          TapDetector(
            onTap: onNew,
            child: Container(
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: S.s20),
              decoration: BoxDecoration(
                  color: AppColors.accentFill,
                  borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('edit', size: 16, color: AppColors.accentFg),
                SizedBox(width: S.s8),
                Text('New session',
                    style: sans(14, weight: W.label, color: AppColors.accentFg)),
              ]),
            ),
          ),
        ],
        if (finished > 0) ...[
          SizedBox(height: S.s24),
          TapDetector(
            onTap: onOpenSessions,
            child: Text('$finished finished today',
                style: sans(13, color: AppColors.fg3)),
          ),
        ],
      ]),
    );
  }
}
