import 'package:flutter/material.dart';

import '../crew_status.dart';
import '../mochi.dart';
import '../models.dart';
import '../notification_text.dart';
import '../theme.dart';
import '../widgets.dart';
import 'session_list_row.dart';

/// The agent's character colour, for the approval card and the stage.
Color heroAgentColor(String agentId) {
  final id = agentCharacterFor(agentId);
  final spec = id == null ? null : CharacterRoster.current?.character(id);
  return spec?.color ?? AppColors.accent;
}

Color _inkOn(Color c) =>
    c.computeLuminance() > 0.45 ? const Color(0xFF14141A) : Colors.white;

String _titleCase(String id) =>
    id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}';

/// "in 9 h" style distance to a unix-seconds time.
String heroWakeIn(int unixSec, {DateTime? now}) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000)
      .difference(now ?? DateTime.now());
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return 'in ${d.inMinutes} min';
  if (d.inHours < 24) return 'in ${d.inHours} h';
  return 'in ${d.inDays} d';
}

String _clock(int unixSec, {DateTime? now}) {
  final t = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  final n = now ?? DateTime.now();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  final today = t.year == n.year && t.month == n.month && t.day == n.day;
  if (today || t.difference(n).inHours < 24) return '$hh:$mm';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[t.weekday - 1]} $hh:$mm';
}

/// The phone home hero: the team stage, what needs you, and what is moving.
/// Every part is derived from [sessions] and [agents]; a part with no data is
/// left out and the whole hero collapses when nothing is left.
class PhoneHero extends StatefulWidget {
  const PhoneHero({
    super.key,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    this.onDecide,
    this.onReviewPr,
    this.onMergePr,
    this.now,
  });

  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final ValueChanged<SessionInfo> onOpenSession;

  /// Approve (true) or deny (false) the session's pending approval.
  final Future<void> Function(SessionInfo session, bool approve)? onDecide;
  final ValueChanged<SessionInfo>? onReviewPr;
  final ValueChanged<SessionInfo>? onMergePr;

  /// Clock override for tests.
  final DateTime? now;

  @override
  State<PhoneHero> createState() => _PhoneHeroState();
}

class _PhoneHeroState extends State<PhoneHero> {
  String? _busy;

  DateTime get _now => widget.now ?? DateTime.now();

  String _name(String id) {
    for (final a in widget.agents) {
      if (a.id == id) return a.displayName;
    }
    return _titleCase(id);
  }

  List<SessionInfo> get _live =>
      widget.sessions.where((s) => !s.settled).toList();

  List<CrewEntry> _stage() {
    final crew = deriveCrew(
        widget.agents
            .where((a) => !a.isMissionControl && a.status != 'archived')
            .toList(),
        _live);
    // Whoever needs you first, then the working ones, then agents standing by
    // with a session open, so the stage reads as the team.
    int rank(CrewEntry e) => e.state.index;
    var live = crew.where((e) => e.sessions.isNotEmpty).toList();
    // The stage always shows the team; with nothing open, the agents themselves.
    if (live.isEmpty) live = crew.take(5).toList();
    if (live.length <= 5) return live;
    final keep = ([...live]..sort((a, b) => rank(a).compareTo(rank(b))))
        .take(5)
        .toSet();
    return live.where(keep.contains).toList();
  }

  /// The most urgent ask: approvals before questions, newest first.
  SessionInfo? _top() {
    int rank(SessionInfo s) => switch ('${s.attention?['type']}') {
          'approval' => 0,
          'question' => 1,
          _ => 9,
        };
    final asks = _live
        .where((s) => sessionNeedsYou(s) && rank(s) < 9)
        .toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : b.lastActive.compareTo(a.lastActive);
      });
    return asks.firstOrNull;
  }

  SessionInfo? _prReady() {
    final prs = _live.where((s) => s.pr?.state == 'open').toList()
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    return prs.firstOrNull;
  }

  SessionInfo? _running() {
    final run = _live
        .where((s) => s.running && s.plan != null && s.plan!.total > 0)
        .toList()
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    return run.firstOrNull;
  }

  SessionInfo? _nextWake() {
    final nowSec = _now.millisecondsSinceEpoch ~/ 1000;
    final due = _live
        .where((s) => (s.nextWakeAt ?? 0) > nowSec)
        .toList()
      ..sort((a, b) => a.nextWakeAt!.compareTo(b.nextWakeAt!));
    return due.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage();
    final top = _top();
    final pr = _prReady();
    final run = _running();
    final wake = _nextWake();
    final lines = <Widget>[
      if (pr != null) _prLine(pr),
      if (run != null) _runLine(run),
      if (wake != null) _wakeLine(wake),
    ];
    if (stage.isEmpty && top == null && lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: S.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stage.isNotEmpty) _stageRow(stage),
          if (top != null) _approvalCard(top),
          for (final l in lines) ...[SizedBox(height: S.s6), l],
        ],
      ),
    );
  }

  // Stage ------------------------------------------------------------------

  Widget _stageRow(List<CrewEntry> crew) {
    final n = crew.length;
    double sizeAt(int i) {
      final d = (i - (n - 1) / 2).abs();
      return d <= 0 ? 66 : 66 - d * 9 - (d >= 1 ? 1 : 0);
    }

    return Padding(
      padding: EdgeInsets.only(top: S.s8, bottom: S.s16),
      child: SizedBox(
        height: 66 + 12 + 20,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _stageAgent(crew[i], sizeAt(i)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stageAgent(CrewEntry e, double size) {
    final needs = e.state == CrewState.needsYou;
    final name = e.agent.displayName;
    return Semantics(
      button: true,
      label: needs
          ? '$name needs you'
          : e.state == CrewState.working
              ? '$name is working'
              : name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: e.lead == null ? null : () => widget.onOpenSession(e.lead!),
        child: SizedBox(
          width: size + 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, needs ? -12 : 0),
                child: _avatar(
                  e.agent.id,
                  size,
                  needs
                      ? AgentCharacterState.needs
                      : e.state == CrewState.working
                          ? AgentCharacterState.working
                          : AgentCharacterState.idle,
                  badge: needs ? '?' : null,
                ),
              ),
              SizedBox(height: S.s2),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(11, color: AppColors.fg3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(String agentId, double size, AgentCharacterState state,
      {String? badge}) {
    return ListenableBuilder(
      listenable: agentCharacters,
      builder: (_, __) {
        final character = agentCharacterFor(agentId);
        if (character == null) {
          return AgentMochi(agentId, size: size, state: state);
        }
        return AgentCharacter(character,
            size: size,
            state: state,
            staggerKey: agentId,
            badge: badge);
      },
    );
  }

  // Approval card -----------------------------------------------------------

  Widget _approvalCard(SessionInfo s) {
    final a = s.attention ?? const {};
    final isApproval = a['type'] == 'approval';
    final approval = isApproval ? approvalOf(a) : null;
    final owner = s.displayAgentId ?? 'snippet';
    final colour = heroAgentColor(owner);
    final title = s.title.trim().isEmpty ? '(untitled)' : s.title.trim();
    final summary = approval != null
        ? approval.headline('${a['tool'] ?? ''}')
        : '${a['text'] ?? ''}'.trim();
    final command = approval?.shownCommand.split(RegExp(r'\s+')).join(' ');
    final busy = _busy == s.id;
    final canDecide = approval != null && widget.onDecide != null;

    Future<void> decide(bool ok) async {
      if (_busy != null) return;
      setState(() => _busy = s.id);
      try {
        await widget.onDecide!(s, ok);
      } finally {
        if (mounted) setState(() => _busy = null);
      }
    }

    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(R.of(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenSession(s),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.of(20)),
            border: Border.all(color: AppColors.line),
          ),
          padding: EdgeInsets.fromLTRB(S.s16, S.of(14), S.s16, S.of(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: colour, shape: BoxShape.circle),
                ),
                SizedBox(width: S.s8),
                Text('Needs you', style: sans(12, color: AppColors.fg3)),
                const Spacer(),
                Text(relativeAge(s.lastActive),
                    style: mono(12, color: AppColors.fg3)),
              ]),
              SizedBox(height: S.s12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _avatar(owner, 36, AgentCharacterState.waiting),
                SizedBox(width: S.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_name(owner)} · $title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(15,
                              weight: W.label, color: AppColors.fg1)),
                      if (summary.isNotEmpty)
                        Text(summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, height: 1.35, color: AppColors.fg2)),
                    ],
                  ),
                ),
              ]),
              if (command != null && command.isNotEmpty) ...[
                SizedBox(height: S.s12),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: S.s8, vertical: S.of(6)),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(R.of(10)),
                  ),
                  child: Text(command,
                      key: const Key('hero-command'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: codeMono(12, color: AppColors.fg1)),
                ),
              ],
              SizedBox(height: S.s12),
              if (canDecide)
                Row(children: [
                  Expanded(
                      child: _HeroButton(
                          label: 'Deny',
                          onTap: busy ? null : () => decide(false))),
                  SizedBox(width: S.s8),
                  Expanded(
                      flex: 2,
                      child: _HeroButton(
                          label: 'Approve',
                          icon: 'check',
                          color: colour,
                          ink: _inkOn(colour),
                          onTap: busy ? null : () => decide(true))),
                ])
              else
                _HeroButton(
                    label: 'Answer',
                    color: colour,
                    ink: _inkOn(colour),
                    onTap: () => widget.onOpenSession(s)),
            ],
          ),
        ),
      ),
    );
  }

  /// Age of an ask, in the card's own words.
  String relativeAge(int unixSec) {
    final m = _now
        .difference(DateTime.fromMillisecondsSinceEpoch(unixSec * 1000))
        .inMinutes;
    if (m < 1) return 'now';
    if (m < 60) return '$m min';
    if (m < 1440) return '${m ~/ 60} h';
    return '${m ~/ 1440} d';
  }

  // Lines -------------------------------------------------------------------

  Widget _line(SessionInfo s, List<Widget> children, String label) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(14)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onOpenSession(s),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.of(14)),
                border: Border.all(color: AppColors.line),
              ),
              padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s4),
              child: Row(children: children),
            ),
          ),
        ),
      );

  Widget _prLine(SessionInfo s) {
    final pr = s.pr!;
    final owner = s.displayAgentId ?? 'snippet';
    return _line(
      s,
      [
        _avatar(owner, 24, AgentCharacterState.done),
        SizedBox(width: S.s8),
        Expanded(
          child: Text('PR #${pr.number} ready',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, color: AppColors.fg1)),
        ),
        if (widget.onReviewPr != null) ...[
          _HeroMini(label: 'Review', onTap: () => widget.onReviewPr!(s)),
          SizedBox(width: S.s6),
        ],
        if (widget.onMergePr != null)
          _HeroMini(
              label: 'Merge',
              color: heroAgentColor(owner),
              onTap: () => widget.onMergePr!(s)),
      ],
      'PR #${pr.number} ready',
    );
  }

  Widget _runLine(SessionInfo s) {
    final plan = s.plan!;
    final owner = s.displayAgentId ?? 'snippet';
    final title = s.title.trim().isEmpty ? '(untitled)' : s.title.trim();
    final text = '${_name(owner)} · $title, ${sessionStepLabel(plan)}';
    final since = sessionDuration(plan.stepStartedAt ?? s.runningSince);
    return _line(
      s,
      [
        _avatar(owner, 24, AgentCharacterState.working),
        SizedBox(width: S.s8),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, color: AppColors.fg1)),
        ),
        if (since.isNotEmpty) ...[
          SizedBox(width: S.s8),
          Text(since, style: mono(12, color: AppColors.fg3)),
          SizedBox(width: S.s4),
        ],
      ],
      text,
    );
  }

  Widget _wakeLine(SessionInfo s) {
    final at = s.nextWakeAt!;
    final owner = s.displayAgentId ?? 'snippet';
    final title = s.title.trim().isEmpty ? '(untitled)' : s.title.trim();
    final text = 'Next: ${_name(owner)}, $title, ${_clock(at, now: _now)}';
    return _line(
      s,
      [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(R.of(8)),
          ),
          child: AppIcon('calendar-clock', size: 13, color: AppColors.fg2),
        ),
        SizedBox(width: S.s8),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, color: AppColors.fg1)),
        ),
        SizedBox(width: S.s8),
        Text(heroWakeIn(at, now: _now), style: mono(12, color: AppColors.fg3)),
        SizedBox(width: S.s4),
      ],
      text,
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton(
      {required this.label, this.icon, this.color, this.ink, this.onTap});

  final String label;
  final String? icon;
  final Color? color;
  final Color? ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = ink ?? AppColors.fg1;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: color ?? AppColors.surface3,
        borderRadius: BorderRadius.circular(R.of(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  tapHaptic();
                  onTap!();
                },
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  AppIcon(icon!, size: 15, color: fg),
                  SizedBox(width: S.s6),
                ],
                Text(label,
                    style: sans(14, weight: W.label, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroMini extends StatelessWidget {
  const _HeroMini({required this.label, required this.onTap, this.color});

  final String label;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color ?? AppColors.surface3,
        borderRadius: BorderRadius.circular(R.of(8)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            tapHaptic();
            onTap();
          },
          child: Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: S.s8 + 1),
            alignment: Alignment.center,
            child: Text(label,
                style: sans(12,
                    weight: W.label,
                    color: color == null ? AppColors.fg1 : _inkOn(color!))),
          ),
        ),
      );
}
