import 'dart:async';

import 'package:flutter/material.dart';
import '../platform.dart';

import '../api.dart';
import '../settings_form.dart';
import '../models.dart';
import '../task_reason.dart';
import '../theme.dart';
import '../widgets.dart';
import '../swr.dart';

import 'shell_models.dart' show RightTab;
import 'tasks/task_common.dart' show TaskEmptyNote, taskTitleInk;
import '../tap_detector.dart';

class MissionBoardPanel extends StatefulWidget {
  const MissionBoardPanel({
    super.key,
    required this.client,
    required this.onOpenSession,
    this.readouts = const [],
    this.activeReadout,
    this.readoutBody,
    this.onSelectReadout,
    this.onCloseReadout,
    this.onClearReadout,
    this.onExpandReadout,
  });

  final DaemonClient client;
  final void Function(String sessionId, String title) onOpenSession;
  final List<RightTab> readouts;
  final String? activeReadout;
  final Widget Function(RightTab readout)? readoutBody;
  final ValueChanged<RightTab>? onSelectReadout;
  final ValueChanged<RightTab>? onCloseReadout;
  final VoidCallback? onClearReadout;
  final ValueChanged<RightTab>? onExpandReadout;

  @override
  State<MissionBoardPanel> createState() => _MissionBoardPanelState();
}

class _MissionBoardPanelState extends State<MissionBoardPanel> {
  List<LeadTask> _tasks = const [];
  List<RecurringJob> _jobs = const [];
  bool _loaded = false;
  Revalidator? _live;
  _BoardFilter _filter = _BoardFilter.active;

  @override
  void initState() {
    super.initState();
    _load();
    _bindLive();
  }

  @override
  void didUpdateWidget(MissionBoardPanel old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) {
      _bindLive();
      _load();
    }
  }

  void _bindLive() {
    _live?.dispose();
    _live = Revalidator(
        client: widget.client,
        on: (e) => Swr.coordination(e) || e['kind'] == 'recurring',
        debounce: const Duration(seconds: 1),
        onRevalidate: ({required bool force}) => _load());
  }

  @override
  void dispose() {
    _live?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await widget.client.leadOverview();
      List<RecurringJob> jobs = const [];
      try {
        jobs = await widget.client.recurringJobs();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _tasks = o.recentTasks.where((t) => !t.archived).toList();
        _jobs = jobs.where((j) => j.enabled && j.nextRunAt > 0).toList()
          ..sort((a, b) => a.nextRunAt.compareTo(b.nextRunAt));
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _at(int secs) {
    final t = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final now = DateTime.now();
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return hm;
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return t.difference(now).inDays < 6
        ? days[t.weekday - 1]
        : '${t.day}/${t.month}';
  }

  Widget _label(String text) => Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.s16, S.s12, S.s8),
        child: Text(text, style: sans(12.5, color: AppColors.fg3)),
      );

  TaskNote _note(LeadTask t) {
    final titles = {for (final x in _tasks) x.id: x.title};
    return taskNote(
      status: t.status,
      statusReason: t.statusReason,
      waitingOn: t.waitingOn,
      currentStep: t.currentStep,
      supersededBy: t.supersededBy,
      titleOf: (id) => titles[id],
    );
  }

  (String, Color, Color) _pill(LeadTask t) {
    if (!kMobile) {
      final label = switch (t.status) {
        'in_review' => 'In review',
        'blocked' => 'Blocked',
        'done' => 'Done',
        _ => 'Working',
      };
      return (label, AppColors.fg2, Grouped.plate);
    }
    return switch (t.status) {
      'in_review' => ('In review', AppColors.accent, AppColors.accentBg),
      'blocked' => ('Blocked', AppColors.danger, AppColors.dangerBg),
      'done' => ('Done', AppColors.ok, AppColors.okBg),
      _ => ('Working', AppColors.run, AppColors.runBg),
    };
  }

  String _when(LeadTask t) {
    if (t.status == 'done' || t.status == 'in_review') return _at(t.updatedAt);
    final m = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(t.updatedAt * 1000))
        .inMinutes;
    if (m < 1) return 'now';
    return m < 60 ? '$m min' : _at(t.updatedAt);
  }

  Widget _taskCard(LeadTask t) {
    final sid = t.sessionId;
    final open = sid == null ? null : () => widget.onOpenSession(sid, t.title);
    final review = t.status == 'in_review';
    final (label, fg, bg) = _pill(t);
    final note = _note(t).line;
    final radius = BorderRadius.circular(R.of(kMobile ? 20 : 9));
    return Padding(
      key: ValueKey('board-card-${t.id}'),
      padding: EdgeInsets.fromLTRB(S.s12, 0, S.s12, S.s8),
      child: Material(
        color: kMobile ? AppColors.surface2 : Grouped.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: kMobile
              ? BorderSide(color: review ? AppColors.border2 : AppColors.border)
              : BorderSide(color: Grouped.cardBorder),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: open,
          child: Padding(
            padding:
                EdgeInsets.fromLTRB(S.of(15), S.of(13), S.of(15), S.of(13)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: S.s6, vertical: S.s2),
                    decoration: BoxDecoration(
                      color: kMobile ? AppColors.surface3 : Grouped.plate,
                      borderRadius: BorderRadius.circular(R.of(6)),
                    ),
                    child: Text(t.id, style: mono(11, color: AppColors.fg3)),
                  ),
                  SizedBox(width: S.s8),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s2),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(R.of(8)),
                    ),
                    child: Text(label,
                        style: sans(12, weight: W.label, color: fg)),
                  ),
                  const Spacer(),
                  Text(_when(t),
                      style: sans(12, color: AppColors.fg4, tabular: true)),
                ]),
                SizedBox(height: S.s6),
                Text(t.title.isEmpty ? '(untitled)' : t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.label,
                        height: kMobile ? 20 / 15 : 18 / 13,
                        color: kMobile ? AppColors.fg1 : taskTitleInk)),
                SizedBox(height: S.s6),
                Row(children: [
                  Expanded(
                    child: Text(note ?? '',
                        key: ValueKey('note-${t.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                                                  style: sans(12,
                            color: kMobile && t.status == 'blocked'
                                ? AppColors.danger
                                : AppColors.fg3)),
                  ),
                  if (open != null) ...[
                    SizedBox(width: S.s8),
                    _cardButton(
                        review
                            ? 'Review'
                            : t.status == 'done'
                                ? 'Read'
                                : 'Open',
                        primary: review,
                        onTap: open),
                  ],
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardButton(String text,
          {required bool primary, required VoidCallback onTap}) =>
      Material(
        color: kMobile
            ? (primary ? AppColors.accentFill : AppColors.surface3)
            : (primary ? PaneRow.plate : Grouped.card),
        borderRadius: BorderRadius.circular(kMobile ? R.of(10) : PaneRow.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobile ? R.of(10) : PaneRow.radius),
          onTap: onTap,
          child: Container(
            height: kMobile ? 30 : PaneRow.pill,
            padding: EdgeInsets.symmetric(horizontal: S.of(11)),
            alignment: Alignment.center,
            child: Text(text,
                style: sans(12,
                    weight: W.label,
                    color: kMobile
                        ? (primary ? AppColors.accentFg : AppColors.fg1)
                        : PaneRow.labelOn)),
          ),
        ),
      );

  Widget _filterBar() => Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.s4, S.s12, S.s4),
        child: Container(
          padding: EdgeInsets.all(S.s4),
          decoration: BoxDecoration(
            color: kMobile ? AppColors.surface1 : Grouped.card,
            borderRadius: BorderRadius.circular(R.of(kMobile ? 16 : 8)),
            border: kMobile
                ? Border.all(color: AppColors.border)
                : Border.all(color: Grouped.cardBorder),
          ),
          child: Row(children: [
            for (final f in _BoardFilter.values)
              Expanded(
                child: TapDetector(
                  key: ValueKey('board-filter-${f.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _filter = f),
                  child: AnimatedContainer(
                    duration: Motion.quick,
                    height: kMobile ? 32 : PaneRow.pill,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _filter == f
                          ? (kMobile ? AppColors.surface3 : PaneRow.plate)
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(R.of(kMobile ? 12 : 6)),
                    ),
                    child: Text(f.label,
                        style: sans(kMobile ? 13 : 12.5,
                            weight: _filter == f ? W.label : W.body,
                            color: kMobile
                                ? (_filter == f ? AppColors.fg1 : AppColors.fg3)
                                : (_filter == f
                                    ? PaneRow.labelOn
                                    : PaneRow.labelOff))),
                  ),
                ),
              ),
          ]),
        ),
      );

  int get _activeCount => _tasks
      .where((t) =>
          t.status == 'in_progress' ||
          t.status == 'in_review' ||
          t.status == 'blocked')
      .length;

  RightTab? get _readout =>
      widget.readouts.where((r) => r.key == widget.activeReadout).firstOrNull;

  Widget _seg(String text, bool on, VoidCallback onTap,
      {VoidCallback? onClose}) {
    return Padding(
      padding: EdgeInsets.only(right: S.s2),
      child: Material(
        color: on ? PaneRow.plate : Colors.transparent,
        borderRadius: BorderRadius.circular(PaneRow.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(PaneRow.radius),
          onTap: onTap,
          child: Container(
            height: PaneRow.pill,
            alignment: Alignment.center,
            padding: EdgeInsets.fromLTRB(
                S.of(10), 0, onClose != null ? S.s6 : S.of(10), 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(text,
                  style: sans(PaneRow.label,
                      color: on ? PaneRow.labelOn : PaneRow.labelOff)),
              if (onClose != null) ...[
                SizedBox(width: S.of(5)),
                TapDetector(
                  onTap: onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.all(S.s2),
                    child: AppIcon('x', size: 11, color: AppColors.fg3),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _headerBar() {
    if (widget.readouts.isEmpty) {
      return Container(
        height: PaneRow.height,
        padding: EdgeInsets.symmetric(horizontal: S.s12),
        alignment: Alignment.centerLeft,
        child: Row(children: [
          Text('Task board',
              style: sans(12.5, weight: W.label, color: PaneRow.labelOn)),
          const Spacer(),
          if (_activeCount > 0)
            Text('$_activeCount active',
                style: sans(12, color: AppColors.fg4)),
        ]),
      );
    }
    final reading = _readout;
    return Container(
      height: PaneRow.height,
      padding: EdgeInsets.fromLTRB(S.of(10), S.s2, S.s8, S.s2),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _seg('Board', reading == null,
                  () => widget.onClearReadout?.call()),
              for (final r in widget.readouts)
                _seg(r.label, r.key == widget.activeReadout,
                    () => widget.onSelectReadout?.call(r),
                    onClose: () => widget.onCloseReadout?.call(r)),
            ]),
          ),
        ),
        if (reading != null && widget.onExpandReadout != null)
          IconBtn('maximize-2',
              size: 28,
              iconSize: 13,
              tooltip: 'Open in main view',
              onTap: () => widget.onExpandReadout!(reading)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reading = _readout;
    if (reading != null && widget.readoutBody != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerBar(),
          Expanded(
            child: widget.readoutBody!(reading),
          ),
        ],
      );
    }
    final now = DateTime.now();
    bool today(int s) {
      final t = DateTime.fromMillisecondsSinceEpoch(s * 1000);
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }

    final review = _tasks.where((t) => t.status == 'in_review').toList();
    final flight = _tasks
        .where((t) => t.status == 'in_progress' || t.status == 'blocked')
        .toList();
    final done = _tasks
        .where((t) =>
            t.status == 'done' &&
            (_filter == _BoardFilter.done || today(t.updatedAt)))
        .toList();
    final showReview = _filter != _BoardFilter.done;
    final showFlight = _filter == _BoardFilter.active;
    final showDone = _filter != _BoardFilter.review;
    final doing = [...review, ...flight];
    return ColoredBox(
      color: Colors.transparent,
      child: !_loaded
          ? Center(child: DelayedSpinner(size: 16))
          : ListView(
              padding: EdgeInsets.only(bottom: S.s24),
              children: [
                _headerBar(),
                if (doing.isEmpty && _jobs.isEmpty && done.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 72, 24, 0),
                    child: TaskEmptyNote(
                      title: 'All quiet',
                      body: 'Work your agents pick up, scheduled runs and what finished today land here.',
                    ),
                  ),
                if (_tasks.isNotEmpty) _filterBar(),
                if (showReview && review.isNotEmpty) ...[
                  _label('Needs review'),
                  for (final t in review) _taskCard(t),
                ],
                if (showFlight && flight.isNotEmpty) ...[
                  _label('In flight'),
                  for (final t in flight) _taskCard(t),
                ],
                if (_filter != _BoardFilter.active &&
                    (showReview ? review.isEmpty : done.isEmpty))
                  Padding(
                    padding: EdgeInsets.fromLTRB(S.s12, S.s24, S.s12, 0),
                    child: Text(
                        showReview
                            ? 'Nothing waiting for review.'
                            : 'Nothing finished yet.',
                        textAlign: TextAlign.center,
                        style: sans(13, color: AppColors.fg4)),
                  ),
                if (showFlight && _jobs.isNotEmpty) ...[
                  _label('Up next'),
                  for (final j in _jobs.take(6))
                    Padding(
                      padding: EdgeInsets.fromLTRB(S.s12, S.s6, S.s12, S.s6),
                      child: Row(children: [
                        SizedBox(
                          width: 48,
                          child: Text(_at(j.nextRunAt),
                              style: mono(11, color: AppColors.fg4)),
                        ),
                        Expanded(
                          child: Text(j.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(13, color: AppColors.fg2)),
                        ),
                      ]),
                    ),
                ],
                if (showDone && done.isNotEmpty) ...[
                  _label(_filter == _BoardFilter.done ? 'Done' : 'Done today'),
                  for (final t
                      in done.take(_filter == _BoardFilter.done ? 30 : 8))
                    _taskCard(t),
                ],
              ],
            ),
    );
  }
}

enum _BoardFilter {
  active('Active'),
  review('Needs review'),
  done('Done');

  const _BoardFilter(this.label);
  final String label;
}
