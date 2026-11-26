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
import '../settings_form.dart';
import '../transcript.dart'
    show LaneControlButton, LaneWho, laneAgentName, laneElapsed;
import 'session.dart';
import '../tap_detector.dart';
import 'lanes_phone.dart';
import 'spec_bar.dart';

/// A focused view of delegated work. The session owns the live state; this
/// screen polls the getter so progress continues updating while it is open.
class LanesScreen extends StatefulWidget {
  final List<LaneInfo> Function() liveLanes;
  final VoidCallback? onClose;
  final DaemonClient? client;
  final String? sessionId;
  final String? sessionTitle;
  final String? sessionAgentId;
  final String? sessionAgentName;

  const LanesScreen({
    super.key,
    required this.liveLanes,
    this.onClose,
    this.client,
    this.sessionId,
    this.sessionTitle,
    this.sessionAgentId,
    this.sessionAgentName,
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
            SpecBar(
              title: 'Lanes',
              subtitle: lanesSubtitle(lanes),
              onBack: widget.onClose ?? () => Navigator.pop(context),
            )
          else
            // SnAppBar steps aside when a hosting panel already shows the title.
            SnAppBar(
              title: 'Lanes',
              titleSize: 20,
              compact: true,
              onBack: widget.onClose ?? () => Navigator.pop(context),
            ),
          Expanded(
            child: lanes.isEmpty
                ? const EmptyState(
                    icon: 'layers',
                    title: 'No delegated lanes',
                    body: 'Parallel agent work will appear here when started.')
                : LanesByAgent(
                    lanes: lanes,
                    liveLanes: widget.liveLanes,
                    client: widget.client,
                    sessionId: widget.sessionId,
                    sessionAgentId: widget.sessionAgentId,
                    sessionAgentName: widget.sessionAgentName,
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Phone header: 40px back circle, centred title and the session as a muted
/// subtitle. SettingsHeader's compact form has no subtitle line.
class LanesHeader extends StatelessWidget {
  const LanesHeader({super.key, this.subtitle, required this.onBack});
  final String? subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final sub = (subtitle ?? '').trim();
    return SizedBox(
      height: Grouped.headerHeight + (sub.isEmpty ? 0 : 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Grouped.gutter),
        child: Stack(alignment: Alignment.center, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Lanes',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: Grouped.pageTitleStyle()),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: sans(13, color: AppColors.fg3)),
            ]),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: GroupedCircleButton(
                icon: 'chevron-left', tooltip: 'Back', onTap: onBack),
          ),
        ]),
      ),
    );
  }
}

class _AgentGroup {
  _AgentGroup(this.id, this.name);
  final String id;
  final String name;
  final lanes = <LaneInfo>[];
}

int _rank(LaneInfo l) => switch (l.status) {
      'failed' || 'paused' => 0,
      'running' => 1,
      'cancelled' => 3,
      _ => 2,
    };

bool _needs(LaneInfo l) => l.status == 'failed' || l.status == 'paused';

/// Lanes grouped by the agent running them, the session's own first. Loads
/// the inference profiles once so each row can show its provider.
class LanesByAgent extends StatefulWidget {
  const LanesByAgent({
    super.key,
    required this.lanes,
    this.liveLanes,
    this.client,
    this.sessionId,
    this.sessionAgentId,
    this.sessionAgentName,
  });

  final List<LaneInfo> lanes;
  final List<LaneInfo> Function()? liveLanes;
  final DaemonClient? client;
  final String? sessionId;
  final String? sessionAgentId;
  final String? sessionAgentName;

  @override
  State<LanesByAgent> createState() => _LanesByAgentState();
}

class _LanesByAgentState extends State<LanesByAgent> {
  var _profiles = const <String, InferenceProfile>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profiles.isEmpty) _load();
  }

  Future<void> _load() async {
    final client = widget.client ?? DaemonScope.maybeOf(context);
    if (client == null) return;
    try {
      final cfg = await client.getConfig();
      if (mounted) {
        setState(() => _profiles = {for (final p in cfg.profiles) p.name: p});
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => _AgentLanesView(
        lanes: widget.lanes,
        liveLanes: widget.liveLanes,
        client: widget.client,
        sessionId: widget.sessionId,
        sessionAgentId: widget.sessionAgentId,
        sessionAgentName: widget.sessionAgentName,
        profiles: _profiles,
      );
}

class _AgentLanesView extends StatelessWidget {
  const _AgentLanesView({
    required this.profiles,
    required this.lanes,
    this.liveLanes,
    this.client,
    this.sessionId,
    this.sessionAgentId,
    this.sessionAgentName,
  });

  final List<LaneInfo> lanes;
  final List<LaneInfo> Function()? liveLanes;
  final DaemonClient? client;
  final String? sessionId;
  final String? sessionAgentId;
  final String? sessionAgentName;
  final Map<String, InferenceProfile> profiles;

  String get _ownId => sessionAgentId ?? '';
  String get _ownName =>
      sessionAgentName ??
      (_ownId.isEmpty ? 'This session' : laneAgentName(_ownId));

  List<_AgentGroup> _groups() {
    final byId = <String, _AgentGroup>{};
    for (final l in lanes) {
      final raw = (l.agent ?? '').trim();
      final id = raw.isEmpty ? _ownId : raw;
      byId
          .putIfAbsent(
              id,
              () =>
                  _AgentGroup(id, id == _ownId ? _ownName : laneAgentName(id)))
          .lanes
          .add(l);
    }
    final out = byId.values.toList();
    out.sort(
        (a, b) => (a.id == _ownId ? 0 : 1).compareTo(b.id == _ownId ? 0 : 1));
    for (final g in out) {
      g.lanes.sort((a, b) => _rank(a).compareTo(_rank(b)));
    }
    return out;
  }

  String _caption(_AgentGroup g) {
    final needs = g.lanes.where(_needs).length;
    if (needs > 0) return '${g.name} · $needs needs you';
    final working = g.lanes.where((l) => l.running).length;
    final cancelled = g.lanes.where((l) => l.status == 'cancelled').length;
    final done = g.lanes.length - working - cancelled;
    final parts = [
      if (working > 0) '$working working',
      if (done > 0) '$done done',
      if (cancelled > 0) '$cancelled cancelled',
    ];
    return '${g.name} · ${parts.join(', ')}';
  }

  String? _footnote(List<_AgentGroup> groups) {
    if (groups.length < 2) return null;
    final others = groups.where((g) => g.id != _ownId).toList();
    final names = others.map((g) => g.name).toList();
    final who = names.length == 1
        ? names.first
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    final what = others.length == 1 && others.first.lanes.length == 1
        ? 'handed ${others.first.lanes.first.title.trim()} to $who'
        : 'handed work to $who';
    final hold = !lanes.any((l) => l.running)
        ? (kMobile ? ' Tap a lane to open it.' : ' Click a lane to open it.')
        : kMobile
            ? ' Tap a lane to watch it; press and hold a working lane to stop it.'
            : ' Click a lane to watch it, or use Stop to end it.';
    return '$_ownName split this work and $what.$hold';
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    if (kMobile) {
      return LanesListPhone(
        groups: [for (final g in groups) (g.id, g.name, g.lanes)],
        onOpen: (l) => openLaneView(context, l,
            client: client, sessionId: sessionId, liveLanes: liveLanes),
      );
    }
    final foot = _footnote(groups);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Grouped.gutter, 8, Grouped.gutter, 32),
      children: [
        for (var i = 0; i < groups.length; i++)
          SettingsGroup(
            header: _caption(groups[i]),
            footer: i == groups.length - 1 ? foot : null,
            children: [
              for (final l in groups[i].lanes)
                _row(context, l, groups[i],
                    tagFinished:
                        groups[i].lanes.any((x) => x.running || _needs(x))),
            ],
          ),
      ],
    );
  }

  Widget _row(BuildContext context, LaneInfo lane, _AgentGroup group,
      {required bool tagFinished}) {
    final c = client ?? DaemonScope.maybeOf(context);
    final session = sessionId ?? lane.trimmedIn;
    final canAct = c != null && session != null;
    final failed = lane.status == 'failed';
    final tone = _needs(lane)
        ? AppColors.run
        : lane.running
            ? AppColors.fg1
            : lane.status == 'cancelled'
                ? AppColors.fg4
                : AppColors.fg2;
    final lead = Stack(clipBehavior: Clip.none, children: [
      AgentMochi(group.id.isEmpty ? 'snippet' : group.id,
          size: Grouped.leadCharacter,
          state: lane.running
              ? AgentCharacterState.working
              : failed
                  ? AgentCharacterState.needs
                  : AgentCharacterState.done),
      Positioned(
        right: -4,
        bottom: -1,
        child: Container(
          key: ValueKey('lane-badge-${lane.id}'),
          width: _needs(lane) ? 6 : 12,
          height: _needs(lane) ? 6 : 12,
          decoration: BoxDecoration(
              color: tone,
              shape: BoxShape.circle,
              border: Border.all(color: Grouped.row, width: 2)),
        ),
      ),
    ]);

    final provider = profiles[(lane.profile ?? '').trim()];
    final mark =
        provider == null || provider.provider.isEmpty ? null : provider;
    String? tag;
    Color tagColor = AppColors.fg3;
    var rest = '';
    var subLines = 1;
    String? value;
    Widget? trailing;
    final text = _firstSentence(lane.summary);
    if (failed) {
      subLines = 2;
      tag = 'Failed';
      tagColor = AppColors.fg1;
      rest = 'Needs you · ${_firstSentence(lane.error ?? lane.summary)}';
      if (canAct) {
        trailing = _RetryPill(client: c, session: session, lane: lane);
      }
    } else if (lane.status == 'paused') {
      rest = 'Needs you · Paused at its time limit';
    } else if (lane.running) {
      final act = (lane.activity ?? '').trim();
      rest = act.isEmpty ? 'Working' : act;
      value = laneElapsed(lane);
      if (!kMobile && canAct) {
        trailing = LaneControlButton(
            client: c, sessionId: session, lane: lane, quiet: true);
      }
    } else if (lane.status == 'cancelled') {
      tag = 'Cancelled';
      rest = text;
    } else if (tagFinished) {
      tag = 'Completed';
      tagColor = AppColors.fg2;
      rest = text;
    } else {
      rest = text;
    }
    final plain = tag == null && mark == null;
    final subWidget = plain
        ? null
        : Text.rich(
            TextSpan(children: [
              if (mark != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: '${mark.name} \u00b7 ${mark.model}',
                      child: AppIcon('provider:${mark.provider}', size: 15),
                    ),
                  ),
                ),
              if (tag != null)
                TextSpan(
                    text: tag,
                    style: TextStyle(
                        color: tag == 'Cancelled' ? AppColors.fg3 : tagColor)),
              if (rest.isNotEmpty)
                TextSpan(text: '${tag == null ? '' : ' \u00b7 '}$rest'),
            ]),
            maxLines: subLines,
            overflow: TextOverflow.ellipsis,
            style: Grouped.subStyle(),
          );
    return KeyedSubtree(
      key: ValueKey('lane-row-${lane.id}'),
      child: SettingsRow(
        label: lane.title,
        sub: plain ? rest : null,
        subWidget: subWidget,
        subMaxLines: subLines,
        leading: lead,
        value: value,
        trailing: trailing,
        chevron: trailing == null,
        onTap: () => openLaneView(context, lane,
            client: client, sessionId: sessionId, liveLanes: liveLanes),
        onLongPress: lane.running && canAct
            ? () => _stop(context, c, session, lane)
            : null,
      ),
    );
  }

  Future<void> _stop(BuildContext context, DaemonClient client, String session,
      LaneInfo lane) async {
    final ok = await confirmAction(context,
        title: 'Stop this lane?',
        body: lane.title.trim().isEmpty ? 'Stop this lane?' : lane.title.trim(),
        confirmLabel: 'Stop',
        danger: true);
    if (!ok || !context.mounted) return;
    try {
      await client.cancelLane(session, lane.id);
    } catch (e) {
      if (context.mounted) toast(context, '$e', danger: true);
    }
  }
}

class _RetryPill extends StatefulWidget {
  const _RetryPill(
      {required this.client, required this.session, required this.lane});
  final DaemonClient client;
  final String session;
  final LaneInfo lane;

  @override
  State<_RetryPill> createState() => _RetryPillState();
}

class _RetryPillState extends State<_RetryPill> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.client.retryLane(widget.session, widget.lane.id);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: _busy ? 0.5 : 1,
        child: Semantics(
          button: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _retry,
            child: Container(
              height: kMobile ? 44 : 28,
              padding: EdgeInsets.symmetric(horizontal: kMobile ? 18 : 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(kMobile ? 22 : R.sm)),
              child: Text('Retry',
                  style: sans(kMobile ? 15 : 12,
                      weight: kMobile ? FontWeight.w600 : FontWeight.w500,
                      color: AppColors.accentFg)),
            ),
          ),
        ),
      );
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
  Widget screen() => !kMobile &&
          daemon != null &&
          transcript != null &&
          transcript.isNotEmpty
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
  int _fullGen = 0;

  LaneInfo get lane => _full ?? widget.lane;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_full == null) _loadFull();
  }

  @override
  void didUpdateWidget(covariant LaneDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lane.id != widget.lane.id ||
        oldWidget.lane.trimmedIn != widget.lane.trimmedIn) {
      _full = null;
      _loadFull();
      return;
    }
    if (_full != null &&
        (oldWidget.lane.status != widget.lane.status ||
            oldWidget.lane.activityAt != widget.lane.activityAt ||
            oldWidget.lane.activity != widget.lane.activity)) {
      _loadFull();
    }
  }

  void _loadFull() {
    final lane = widget.lane;
    final session = lane.trimmedIn;
    if (!widget.detail || session == null) return;
    final client = widget.client ?? DaemonScope.maybeOf(context);
    if (client == null) return;
    final gen = ++_fullGen;
    client.sessionLane(session, lane.id).then((full) {
      if (!mounted || gen != _fullGen || widget.lane.id != lane.id) return;
      setState(() => _full = full);
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
    var (toneFg, _) = toneColors(tone);
    if (!kMobile) {
      toneFg = failed
          ? AppColors.fg1
          : cancelled || paused
              ? AppColors.fg3
              : AppColors.fg2;
    }
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
                      style: kMobile
                          ? body.copyWith(color: AppColors.danger)
                          : body)),
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
    var (toneFg, toneBg) = toneColors(tone);
    if (!kMobile) {
      toneFg = lane.status == 'failed' ? AppColors.fg1 : AppColors.fg2;
      toneBg = AppColors.surface2;
    }
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
      Text(lane.title,
          style: kMobile
              ? sans(17, weight: W.title, color: AppColors.fg1)
              : sans(16, weight: FontWeight.w500, color: AppColors.fg1)),
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
              child:
                  Text(pill, style: sans(12, weight: W.label, color: toneFg)),
            ),
            Text(status, style: sans(12, color: AppColors.fg3)),
            identity,
          ]),
      if (ctrl != null) ...[
        SizedBox(height: S.s12),
        Row(children: [ctrl])
      ],
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
                style: sans(13,
                    color:
                        danger && kMobile ? AppColors.danger : AppColors.fg3)),
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
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
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
          p: danger && kMobile ? text.copyWith(color: AppColors.danger) : text,
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
        client: client,
        sessionId: sessionId,
        lane: lane,
        quiet: !widget.detail);
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
    if (kMobile && lane != null) {
      final c = widget.client ?? DaemonScope.maybeOf(context);
      final session = widget.sessionId ?? lane.trimmedIn;
      final transcript = lane.transcript;
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SpecBar(
                title: lane.title.trim().isEmpty ? 'Lane' : lane.title.trim(),
                subtitle: [laneAgentName(lane.agent ?? ''), laneElapsed(lane)]
                    .where((e) => e.isNotEmpty)
                    .join(' ')),
            Expanded(
              child: SingleChildScrollView(
                child: LaneDetailPhone(
                  lane: lane,
                  onOpenTranscript:
                      c != null && transcript != null && transcript.isNotEmpty
                          ? () => Navigator.of(context).push(AppPageRoute<void>(
                              builder: (_) => LaneTranscriptScreen(
                                  client: c,
                                  laneId: lane.id,
                                  liveLanes: widget.liveLanes)))
                          : null,
                  onStop: c != null && session != null
                      ? () async {
                          try {
                            await c.cancelLane(session, lane.id);
                          } catch (e) {
                            if (context.mounted) {
                              toast(context, '$e', danger: true);
                            }
                          }
                        }
                      : null,
                ),
              ),
            ),
          ]),
        ),
      );
    }
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
