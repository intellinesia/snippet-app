import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                : ListView(
                    padding:
                        EdgeInsets.fromLTRB(S.s16, S.s16, S.s16, S.s32),
                    children: laneSections(lanes,
                        liveLanes: widget.liveLanes,
                        client: widget.client,
                        sessionId: widget.sessionId),
                  ),
          ),
        ]),
      ),
    );
  }
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
          for (var i = 0; i < rows.length; i++)
            _activityRow(rows[i].$1, rows[i].$2,
                live: lane.running && i == rows.length - 1),
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
      padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s6),
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
              style: sans(13, height: 20 / 13, color: AppColors.fg1)),
        ),
        if (at.isNotEmpty) ...[
          SizedBox(width: S.s8),
          Text(at, style: TS.meta()),
        ],
      ]),
    );
  }

  Widget _textBlock(BuildContext context, String value, bool danger) {
    final text = sans(kMobile ? 14 : 13, height: 1.45, color: AppColors.fg2);
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
