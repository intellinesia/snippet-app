import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ambient_loop.dart';
import '../api.dart';
import '../media_views.dart';
import '../models.dart';
import '../motion_routes.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../crew_widgets.dart' show AgentProviderMark;
import '../mochi.dart';
import '../transcript.dart'
    show LaneControlButton, LaneWho, laneAgentName;
import 'mobile_chrome.dart' show MobileBackBar;
import 'mobile_session_home.dart' show MobileGroupCard;
import 'session.dart';

/// A focused view of delegated work. The session owns the live state; this
/// screen polls the getter so progress continues updating while it is open.
class LanesScreen extends StatefulWidget {
  final List<LaneInfo> Function() liveLanes;
  final VoidCallback? onClose;
  final DaemonClient? client;
  final String? sessionId;

  const LanesScreen({
    super.key,
    required this.liveLanes,
    this.onClose,
    this.client,
    this.sessionId,
  });

  @override
  State<LanesScreen> createState() => _LanesScreenState();
}

class _LanesScreenState extends State<LanesScreen> {
  Timer? _ticker;
  List<LaneInfo>? _shown;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final lanes = widget.liveLanes();
      if (identical(lanes, _shown) && !lanes.any((l) => l.running)) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final lanes = widget.liveLanes();
    _shown = lanes;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (kMobile)
            MobileBackBar(
              title: 'Delegated lanes',
              keepBack: true,
              onBack: widget.onClose ?? () => Navigator.pop(context),
            )
          else
            SnAppBar(
              title: 'Delegated lanes',
              titleSize: 14,
              compact: true,
              onBack: widget.onClose ?? () => Navigator.pop(context),
            ),
          Expanded(
            child: lanes.isEmpty
                ? const EmptyState(
                    icon: 'layers',
                    title: 'No delegated lanes',
                    body: 'Parallel agent work will appear here when started.')
                : LaneBoard(
                    lanes: lanes,
                    liveLanes: widget.liveLanes,
                    client: widget.client,
                    sessionId: widget.sessionId),
          ),
        ]),
      ),
    );
  }
}

/// The lanes panel as a board: a summary and status strip, then what needs
/// the user, then live work, then finished lanes folded into one row.
class LaneBoard extends StatefulWidget {
  final List<LaneInfo> lanes;
  final List<LaneInfo> Function()? liveLanes;
  final DaemonClient? client;
  final String? sessionId;

  const LaneBoard({
    super.key,
    required this.lanes,
    this.liveLanes,
    this.client,
    this.sessionId,
  });

  @override
  State<LaneBoard> createState() => _LaneBoardState();
}

enum _Mark { ok, run, danger, faint }

class _LaneBoardState extends State<LaneBoard> {
  bool _showFinished = false;

  @override
  Widget build(BuildContext context) {
    final lanes = widget.lanes;
    final running = lanes.where((l) => l.running).toList();
    final failed = lanes.where((l) => l.status == 'failed').toList();
    final paused = lanes.where((l) => l.status == 'paused').toList();
    final cancelled = lanes.where((l) => l.status == 'cancelled').toList();
    final completed = lanes
        .where((l) =>
            !l.running &&
            !const ['failed', 'paused', 'cancelled'].contains(l.status))
        .toList();
    final side = kMobile ? M.gutter : S.s16;
    final children = <Widget>[
      _group([
        Padding(
          padding: EdgeInsets.symmetric(vertical: S.s12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _summary(lanes.length, completed.length, running),
                SizedBox(height: S.s12),
                _strip([
                  for (final _ in completed) _Mark.ok,
                  for (final _ in running) _Mark.run,
                  for (final _ in failed) _Mark.danger,
                  for (final _ in [...paused, ...cancelled]) _Mark.faint,
                ]),
              ]),
        ),
      ]),
    ];
    void section(String label, List<Widget> rows) {
      if (rows.isEmpty) return;
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(S.s4, S.s20, S.s4, S.s8),
        child: Text(label, style: sans(13, color: AppColors.fg3)),
      ));
      children.add(_group(rows));
    }

    section('Needs you', [
      for (final l in failed)
        _row(l, _Mark.danger, _firstSentence(l.error ?? l.summary),
            action: _control(l)),
      for (final l in paused)
        _row(l, _Mark.faint, 'Paused at its time limit'),
    ]);
    section('Working', [
      for (final l in running)
        _row(
            l,
            _Mark.run,
            [
              if ((l.activity ?? '').trim().isNotEmpty) l.activity!.trim(),
              _elapsed(l.startedAt),
            ].where((s) => s.isNotEmpty).join(' · '),
            monoSub: true,
            action: _control(l)),
    ]);
    if (completed.isNotEmpty || cancelled.isNotEmpty) {
      section('Finished', [
        _foldRow(completed.length, cancelled.length),
        if (_showFinished) ...[
          for (final l in completed) _row(l, _Mark.ok, _firstSentence(l.summary)),
          for (final l in cancelled)
            _row(l, _Mark.faint, _firstSentence(l.summary)),
        ],
      ]);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(side, S.s16, side, S.s32),
      children: children,
    );
  }

  /// One grouped surface with hairlines between rows, as on the agent page.
  Widget _group(List<Widget> rows) => MobileGroupCard(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Container(height: 1, color: AppColors.border),
          rows[i],
        ],
      ]);

  Widget _summary(int total, int done, List<LaneInfo> running) {
    String oldest = '';
    if (running.isNotEmpty) {
      final starts = running
          .map((l) => DateTime.tryParse(l.startedAt))
          .whereType<DateTime>()
          .toList()
        ..sort();
      if (starts.isNotEmpty) oldest = _elapsed(starts.first.toIso8601String());
    }
    final right = running.isEmpty
        ? ''
        : [
            '${running.length} running',
            if (oldest.isNotEmpty) oldest,
          ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text('$done of $total done',
              style: sans(20, weight: W.title, color: AppColors.fg1)),
        ),
        if (right.isNotEmpty)
          Text(right, style: mono(12, color: AppColors.fg3)),
      ],
    );
  }

  /// One segment per lane; past 12 lanes each status keeps its share.
  Widget _strip(List<_Mark> marks) {
    const cap = 12;
    var segs = marks;
    if (marks.length > cap) {
      final counts = {
        for (final m in _Mark.values) m: marks.where((x) => x == m).length,
      };
      final share = {
        for (final m in _Mark.values)
          m: counts[m]! == 0
              ? 0
              : (counts[m]! * cap / marks.length).floor().clamp(1, cap),
      };
      var left = cap - share.values.fold(0, (a, b) => a + b);
      final present = _Mark.values.where((m) => counts[m]! > 0).toList()
        ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      for (var i = 0; left > 0; i = (i + 1) % present.length, left--) {
        share[present[i]] = share[present[i]]! + 1;
      }
      for (; left < 0; left++) {
        share[present.first] = share[present.first]! - 1;
      }
      segs = [
        for (final m in _Mark.values)
          for (var i = 0; i < share[m]!; i++) m,
      ];
    }
    return Row(children: [
      for (var i = 0; i < segs.length; i++) ...[
        if (i > 0) SizedBox(width: S.of(3)),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: _markColor(segs[i]),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    ]);
  }

  Color _markColor(_Mark m) => switch (m) {
        _Mark.ok => AppColors.ok,
        _Mark.run => AppColors.run,
        _Mark.danger => AppColors.danger,
        _Mark.faint => AppColors.fg4.withValues(alpha: 0.45),
      };

  Widget _row(LaneInfo lane, _Mark mark, String sub,
      {bool monoSub = false, Widget? action}) {
    return KeyedSubtree(
      key: ValueKey('lane-row-${lane.id}'),
      child: InkWell(
        onTap: () => openLaneView(context, lane,
            client: widget.client,
            sessionId: widget.sessionId,
            liveLanes: widget.liveLanes),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 44 : 36),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: kMobile ? S.of(10) : S.s6),
            child: Row(children: [
              _LaneMark(mark: mark, color: _markColor(mark)),
              SizedBox(width: S.of(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(lane.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 15 : 13,
                            weight: W.label, color: AppColors.fg1)),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: S.s2),
                        child: Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoSub
                                ? mono(12, color: AppColors.fg3)
                                : sans(kMobile ? 13 : 12,
                                    color: AppColors.fg3)),
                      ),
                  ],
                ),
              ),
              if (action != null) ...[SizedBox(width: S.s8), action],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _foldRow(int finished, int cancelled) {
    final label = [
      if (finished > 0) '$finished finished',
      if (cancelled > 0) '$cancelled cancelled',
    ].join(', ');
    return InkWell(
      onTap: () => setState(() => _showFinished = !_showFinished),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 48 : 36),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: sans(kMobile ? 15 : 13, color: AppColors.fg2)),
          ),
          AppIcon(_showFinished ? 'chevron-down' : 'chevron-right',
              size: 16, color: AppColors.fg4),
        ]),
      ),
    );
  }

  Widget? _control(LaneInfo lane) {
    final client = widget.client ?? DaemonScope.maybeOf(context);
    final sessionId = widget.sessionId ?? lane.trimmedIn;
    if (client == null || sessionId == null) return null;
    if (!lane.running && !lane.retryable) return null;
    return LaneControlButton(
        client: client, sessionId: sessionId, lane: lane, quiet: true);
  }
}

String _firstSentence(String? raw) {
  final text = (raw ?? '')
      .replaceAll(RegExp(r'[*`#>]'), '')
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
      .trim();
  final end = RegExp(r'[.!?](\s|$)').firstMatch(text);
  return end == null ? text : text.substring(0, end.start + 1);
}

String _elapsed(String startedAt) {
  final time = DateTime.tryParse(startedAt);
  if (time == null) return '';
  final delta = DateTime.now().toUtc().difference(time.toUtc());
  if (delta.inSeconds < 60) return '${delta.inSeconds.clamp(0, 59)}s';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  return '${delta.inHours}h ${delta.inMinutes % 60}m';
}

/// The 14px status mark leading a board row; the run ring turns unless
/// motion is reduced.
class _LaneMark extends StatefulWidget {
  final _Mark mark;
  final Color color;
  const _LaneMark({required this.mark, required this.color});

  @override
  State<_LaneMark> createState() => _LaneMarkState();
}

class _LaneMarkState extends State<_LaneMark> {
  final _spin = AmbientLoop(const Duration(milliseconds: 1000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spin.bind(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LaneMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.mark == _Mark.run && !reduceMotion(context)) {
      _spin.start();
    } else {
      _spin.stop(at: 0);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      size: const Size.square(14),
      painter: _MarkPainter(widget.mark, widget.color),
    );
    return SizedBox.square(
      dimension: 14,
      child: widget.mark == _Mark.run
          ? RepaintBoundary(
              child: RotationTransition(turns: _spin, child: paint))
          : paint,
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.mark, this.color);
  final _Mark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    switch (mark) {
      case _Mark.run:
        final rect = (Offset.zero & size).deflate(1.5);
        canvas.drawArc(rect, 0, 6.2832, false,
            stroke
              ..strokeWidth = 2
              ..color = color.withValues(alpha: 0.2));
        canvas.drawArc(rect, -1.5708, 4.712, false, stroke..color = color);
      case _Mark.ok:
        canvas.drawCircle(c, size.width / 2, Paint()..color = color);
        final tick = Path()
          ..moveTo(size.width * 0.29, size.height * 0.52)
          ..lineTo(size.width * 0.44, size.height * 0.67)
          ..lineTo(size.width * 0.72, size.height * 0.37);
        canvas.drawPath(
            tick,
            stroke
              ..strokeWidth = 1.6
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.bg);
      case _Mark.danger:
        canvas.drawCircle(c, size.width / 2 - 1, Paint()..color = color);
      case _Mark.faint:
        canvas.drawCircle(
            c,
            size.width / 2 - 1,
            stroke
              ..strokeWidth = 1.5
              ..color = AppColors.fg4);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.color != color;
}

List<Widget> laneSections(List<LaneInfo> lanes,
    {List<LaneInfo> Function()? liveLanes,
    DaemonClient? client,
    String? sessionId,
    String? sessionProfile}) {
  final running = lanes.where((l) => l.running).toList();
  final failed = lanes.where((l) => l.status == 'failed').toList();
  final cancelled = lanes.where((l) => l.status == 'cancelled').toList();
  final paused = lanes.where((l) => l.status == 'paused').toList();
  final completed = lanes
      .where((l) =>
          !l.running &&
          l.status != 'failed' &&
          l.status != 'cancelled' &&
          l.status != 'paused')
      .toList();
  final out = <Widget>[];
  void section(String label, List<LaneInfo> items, Tone tone) {
    if (items.isEmpty) return;
    if (out.isNotEmpty) out.add(SizedBox(height: S.s20));
    out.add(PaneLabel(label));
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(SizedBox(height: S.s8));
      out.add(LaneDetailCard(
          key: ValueKey(items[i].id),
          lane: items[i],
          liveLanes: liveLanes,
          client: client,
          sessionId: sessionId,
          sessionProfile: sessionProfile));
    }
  }

  section('In progress', running, Tone.run);
  section('Paused', paused, Tone.neutral);
  section('Failed', failed, Tone.danger);
  section('Completed', completed, Tone.ok);
  section('Cancelled', cancelled, Tone.neutral);
  return out;
}

void openLaneView(BuildContext context, LaneInfo lane,
    {DaemonClient? client,
    String? sessionId,
    List<LaneInfo> Function()? liveLanes}) {
  final daemon = client ?? DaemonScope.maybeOf(context);
  final live = liveLanes ?? () => [lane];
  final transcript = lane.transcript;
  Widget screen() => daemon != null && transcript != null && transcript.isNotEmpty
      ? LaneTranscriptScreen(client: daemon, laneId: lane.id, liveLanes: live)
      : LaneDetailScreen(
          laneId: lane.id,
          liveLanes: live,
          client: daemon,
          sessionId: sessionId,
        );
  if (!kMobile &&
      ShellPanelRoot.of(context) == null &&
      ShellPanelScope.maybeOf(context) != null) {
    presentScreen(context,
        style: PanelStyle.drawer,
        purpose: ShellPanelPurpose.lanes,
        panelId: lane.id,
        originClient: daemon,
        builder: (_, __) => screen());
    return;
  }
  Navigator.of(context).push(AppPageRoute<void>(builder: (_) => screen()));
}

class LaneDetailCard extends StatefulWidget {
  final LaneInfo lane;
  final List<LaneInfo> Function()? liveLanes;
  final bool detail;
  final DaemonClient? client;
  final String? sessionId;
  final String? sessionProfile;
  const LaneDetailCard(
      {super.key,
      required this.lane,
      this.liveLanes,
      this.detail = false,
      this.client,
      this.sessionId,
      this.sessionProfile});

  @override
  State<LaneDetailCard> createState() => _LaneDetailCardState();
}

class _LaneDetailCardState extends State<LaneDetailCard> {
  LaneInfo? _full;

  LaneInfo get lane => _full ?? widget.lane;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = widget.lane.trimmedIn;
    if (!widget.detail || session == null || _full != null) return;
    final client = widget.client ?? DaemonScope.maybeOf(context);
    client?.sessionLane(session, widget.lane.id).then((full) {
      if (mounted) setState(() => _full = full);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final failed = lane.status == 'failed';
    final cancelled = lane.status == 'cancelled';
    final paused = lane.status == 'paused';
    final tone = lane.running
        ? Tone.run
        : failed
            ? Tone.danger
            : cancelled || paused
                ? Tone.neutral
                : Tone.ok;
    final (toneFg, _) = toneColors(tone);
    final status = lane.running
        ? 'running · ${_elapsed(lane.startedAt)}'
        : failed
            ? 'failed'
            : cancelled
                ? 'cancelled'
                : paused
                    ? 'paused · time limit'
                    : 'done';
    final activity = lane.activity?.trim();
    final summary = lane.summary?.trim();
    final error = lane.error?.trim();
    if (widget.detail) {
      return _detailView(context, tone: tone, status: status);
    }
    final dense = !kMobile;
    final meta = sans(dense ? 12 : 13, color: AppColors.fg4);
    final body = sans(dense ? 13 : 14, height: 1.45, color: AppColors.fg2);
    // Everything under the header lines up with the title, past the dot.
    Widget indented(Widget child, {double top = 6}) =>
        Padding(padding: EdgeInsets.only(left: S.s16, top: top), child: child);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.tint1,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _open(context),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                S.s12,
                dense ? S.of(9) : S.s12,
                S.s12,
                dense
                    ? S.of(10)
                    : (_controlButton(context) != null ? S.s2 : S.s12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: EdgeInsets.only(top: dense ? S.s6 : S.s8),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: toneFg, shape: BoxShape.circle),
                    ),
                  ),
                  SizedBox(width: S.of(10)),
                  Expanded(
                    child: Text(lane.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: dense
                            ? sans(13, weight: W.label, color: AppColors.fg1)
                            : TS.rowTitle()),
                  ),
                  SizedBox(width: S.of(10)),
                  Padding(
                    padding: EdgeInsets.only(top: dense ? S.of(3) : S.s4),
                    child: _who(context, toneFg),
                  ),
                  SizedBox(width: S.s8),
                  Padding(
                    padding: EdgeInsets.only(top: dense ? S.of(3) : S.s4),
                    child: Text(status,
                        style: sans(12, weight: W.label, color: toneFg)),
                  ),
                ]),
                if (activity != null && activity.isNotEmpty && lane.running)
                  indented(Row(children: [
                    AppIcon('terminal', size: 11, color: AppColors.fg3),
                    SizedBox(width: S.s6),
                    Expanded(
                      child: Text(activity,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: mono(11, color: AppColors.fg3)),
                    ),
                  ])),
                if (summary != null && summary.isNotEmpty)
                  indented(
                      MarkdownPreview(data: summary, maxLines: 2, style: body)),
                if (failed && error != null && error.isNotEmpty)
                  indented(Text(error,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: body.copyWith(color: AppColors.danger))),
                if (_controlButton(context) case final ctrl?)
                  indented(
                      Row(children: [
                        Text('View details', style: meta),
                        const Spacer(),
                        ctrl,
                      ]),
                      top: kMobile ? 0 : 8)
                else
                  indented(Text('View details', style: meta), top: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The lane page: title and status, then Activity, Summary and the rest as
  /// grouped cards under quiet section labels.
  Widget _detailView(BuildContext context,
      {required Tone tone, required String status}) {
    final (toneFg, toneBg) = toneColors(tone);
    final pill = lane.running
        ? 'In progress'
        : switch (lane.status) {
            'failed' => 'Failed',
            'cancelled' => 'Cancelled',
            'paused' => 'Paused',
            _ => 'Done',
          };
    final identity = LaneWho(
        client: widget.client,
        agent: MediaQuery.sizeOf(context).width < 360 ? null : lane.agent,
        profile: (lane.profile ?? '').isNotEmpty
            ? lane.profile
            : widget.sessionProfile,
        maxTextWidth: 96);
    final ctrl = _controlButton(context);
    final rows = <(String, String)>[
      for (final e in lane.activityLog) (e.text, _hhmm(e.at)),
    ];
    final now = lane.activity?.trim() ?? '';
    if (now.isNotEmpty && (rows.isEmpty || rows.last.$1 != now)) {
      rows.add((now, ''));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(lane.title, style: sans(17, weight: W.title, color: AppColors.fg1)),
      SizedBox(height: S.s8),
      Wrap(
          spacing: S.s8,
          runSpacing: S.s6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s2),
              decoration: BoxDecoration(
                  color: toneBg, borderRadius: BorderRadius.circular(R.pill)),
              child: Text(pill,
                  style: sans(12, weight: W.label, color: toneFg)),
            ),
            Text(status, style: sans(12, color: AppColors.fg3)),
            identity,
          ]),
      if (ctrl != null) ...[SizedBox(height: S.s12), Row(children: [ctrl])],
      if (rows.isNotEmpty)
        _section('Activity · ${rows.length}', [
          SizedBox(height: S.s6),
          for (var i = 0; i < rows.length; i++)
            _activityRow(rows[i].$1, rows[i].$2,
                live: lane.running && i == rows.length - 1),
          SizedBox(height: S.s6),
        ]),
      for (final (label, value, danger) in [
        ('Summary', lane.summary, false),
        ('Handoff', lane.handoff, false),
        ('Report', lane.report, false),
        ('Error', lane.error, true),
      ])
        if (value != null && value.trim().isNotEmpty)
          _section(label, [_textBlock(context, value, danger)],
              copy: value, danger: danger),
    ]);
  }

  String _hhmm(String raw) {
    final t = DateTime.tryParse(raw)?.toLocal();
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Widget _section(String label, List<Widget> children,
      {String? copy, bool danger = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(S.s4, S.s20, S.s4, S.s6),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: sans(13, color: danger ? AppColors.danger : AppColors.fg3)),
          ),
          if (copy != null)
            InkWell(
              borderRadius: BorderRadius.circular(R.xs),
              onTap: () {
                Clipboard.setData(ClipboardData(text: copy));
                toast(context, 'Copied');
              },
              child: Padding(
                padding: EdgeInsets.all(S.s4),
                child: Text('Copy', style: sans(12, color: AppColors.fg3)),
              ),
            ),
        ]),
      ),
      Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    ]);
  }

  Widget _activityRow(String text, String at, {required bool live}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.of(2)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 14,
          height: 20,
          child: Center(
            child: live
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle))
                : AppIcon('check', size: 13, color: toneColors(Tone.ok).$1),
          ),
        ),
        SizedBox(width: S.s8),
        Expanded(
          child: Text(text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: sans(13,
                  weight: W.body, height: 20 / 13, color: AppColors.fg2)),
        ),
        if (at.isNotEmpty) ...[
          SizedBox(width: S.s8),
          Text(at, style: TS.meta()),
        ],
      ]),
    );
  }

  Widget _textBlock(BuildContext context, String value, bool danger) {
    final text = sans(13, height: 1.5, color: AppColors.fg2);
    return Padding(
      padding: EdgeInsets.all(S.s12),
      child: MarkdownBody(
        data: value,
        selectable: true,
        styleSheet: markdownStyle(context).copyWith(
          p: danger ? text.copyWith(color: AppColors.danger) : text,
          listBullet: text,
          strong: text.copyWith(
              color: AppColors.fg1, fontWeight: weightFor(W.strong)),
        ),
        builders: {'pre': PreBlockBuilder()},
      ),
    );
  }

  Widget? _controlButton(BuildContext context) {
    final client = widget.client ?? DaemonScope.maybeOf(context);
    final sessionId = widget.sessionId ?? lane.trimmedIn;
    if (client == null || sessionId == null) return null;
    if (!lane.running && !lane.retryable) return null;
    return LaneControlButton(
        client: client, sessionId: sessionId, lane: lane, quiet: !widget.detail);
  }

  /// The agent's character and name, or the provider mark and profile when the
  /// lane runs under the session's own identity.
  Widget _who(BuildContext context, Color toneFg) {
    final agent = lane.agent?.trim() ?? '';
    final profile = ((lane.profile ?? '').trim().isNotEmpty
            ? lane.profile!
            : widget.sessionProfile ?? '')
        .trim();
    final client = widget.client ?? DaemonScope.maybeOf(context);
    final text = [
      if (agent.isNotEmpty) laneAgentName(agent),
      if (profile.isNotEmpty) profile,
    ].join(' · ');
    if (text.isEmpty && client == null) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (agent.isNotEmpty)
        AgentMochi(agent,
            size: 16,
            state: lane.running
                ? AgentCharacterState.working
                : lane.status == 'failed'
                    ? AgentCharacterState.needs
                    : AgentCharacterState.done)
      else if (client != null)
        AgentProviderMark(
            client: client, profile: profile, size: 12, orActive: true),
      if (text.isNotEmpty) ...[
        SizedBox(width: S.s4),
        ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width < 360 ? 56 : 96),
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg3)),
        ),
      ],
    ]);
  }

  void _open(BuildContext context) => openLaneView(context, lane,
      client: widget.client,
      sessionId: widget.sessionId,
      liveLanes: widget.liveLanes);

  String _elapsed(String startedAt) {
    final time = DateTime.tryParse(startedAt);
    if (time == null) return '';
    final delta = DateTime.now().toUtc().difference(time.toUtc());
    if (delta.inSeconds < 60) return '${delta.inSeconds}s';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    return '${delta.inHours}h ${delta.inMinutes % 60}m';
  }
}

class LaneDetailScreen extends StatefulWidget {
  final String laneId;
  final List<LaneInfo> Function() liveLanes;
  final DaemonClient? client;
  final String? sessionId;
  const LaneDetailScreen(
      {super.key,
      required this.laneId,
      required this.liveLanes,
      this.client,
      this.sessionId});

  @override
  State<LaneDetailScreen> createState() => _LaneDetailScreenState();
}

class _LaneDetailScreenState extends State<LaneDetailScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lane = widget
        .liveLanes()
        .where((lane) => lane.id == widget.laneId)
        .firstOrNull;
    return Scaffold(
      body: SafeArea(
          bottom: false,
          child: Column(children: [
            SnAppBar(
                title: 'Lane details',
                titleSize: 14,
                compact: true,
                onBack: () => Navigator.of(context).pop()),
            Expanded(
                child: lane == null
                    ? const EmptyState(
                        icon: 'layers',
                        title: 'Lane unavailable',
                        body: 'This delegated lane is no longer available.')
                    : ListView(padding: EdgeInsets.all(S.s16), children: [
                        LaneDetailCard(
                          lane: lane,
                          detail: true,
                          client: widget.client,
                          sessionId: widget.sessionId,
                        ),
                      ])),
          ])),
    );
  }
}

/// A lane at work, as it happens: its own transcript (every command, edit,
/// search and message) streamed read-only, under a banner saying who it is
/// and what it was asked to do.
class LaneTranscriptScreen extends StatelessWidget {
  final DaemonClient client;
  final String laneId;
  final List<LaneInfo> Function() liveLanes;
  const LaneTranscriptScreen(
      {super.key,
      required this.client,
      required this.laneId,
      required this.liveLanes});

  @override
  Widget build(BuildContext context) {
    final lane = liveLanes().where((l) => l.id == laneId).firstOrNull;
    final transcript = lane?.transcript;
    if (lane == null || transcript == null || transcript.isEmpty) {
      return LaneDetailScreen(laneId: laneId, liveLanes: liveLanes);
    }
    return SessionScreen(
      client: client,
      sessionId: transcript,
      title: lane.title,
      readOnly: true,
      acceptDrops: false,
      live: true,
      embedded: ShellPanelScope.maybeOf(context) != null,
    );
  }
}
