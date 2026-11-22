import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../crew_status.dart' show CrewState;
import '../../glass.dart';
import '../../mochi.dart';
import '../../models.dart';
import '../../pull_refresh.dart';
import '../../settled_sessions.dart' show settledDaysLeft;
import '../../markdown_preview.dart' show markdownPreviewSpan, plainPreview;
import '../../theme.dart';
import '../../widgets.dart';
import '../phone_hero.dart' show heroAgentColor;
import '../session_list_row.dart' show projectLabel, sessionCameBack;
import '../shell_nav.dart' show sessionBusy;
import 'agents_group.dart' show ManagedPill;
import 'home_data.dart';
import 'home_style.dart';

const double kHomeMargin = 20;

/// Pull-up "Everyone" sheet for Round 6 "One thing": dimmed home behind, glass
/// surface starting at 132 pt, composer staying above it. Organised by state:
/// Working, Your sessions, Asleep fold, Settled fold.
class EveryoneSheet extends StatelessWidget {
  const EveryoneSheet({
    super.key,
    required this.rows,
    required this.managed,
    required this.mainSessions,
    required this.settledSessions,
    required this.asleepOpen,
    required this.settledOpen,
    required this.onToggleAsleep,
    required this.onToggleSettled,
    required this.onOpenAgent,
    required this.onOpenManaged,
    required this.onOpenSession,
    required this.onClose,
    required this.progress,
    required this.onDrag,
    required this.onRelease,
    this.onSessionActions,
    this.onRefresh,
  });

  final ({List<AgentRow> working, List<AgentRow> needs, List<AgentRow> asleep})
      rows;
  final Map<String, List<SessionInfo>> managed;
  final List<SessionInfo> mainSessions;
  final List<SessionInfo> settledSessions;
  final bool asleepOpen;
  final bool settledOpen;
  final VoidCallback onToggleAsleep;
  final VoidCallback onToggleSettled;
  final void Function(CoordinationAgent a) onOpenAgent;
  final void Function(CoordinationAgent a) onOpenManaged;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(SessionInfo s)? onSessionActions;
  final VoidCallback onClose;
  final VoidCallback? onRefresh;

  /// 0 closed, 1 open; may pass either end while the finger rubber-bands.
  final Animation<double> progress;

  /// Finger drag in pixels (positive is down) and the release velocity in px/s.
  final void Function(double dy) onDrag;
  final void Function(double velocity) onRelease;

  Widget _hairline({double inset = kHomeMargin}) => Padding(
        padding: EdgeInsets.only(left: inset, right: kHomeMargin),
        child: Container(
          height: 0.33,
          color: AppColors.fg1.withValues(alpha: 0.08),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final top = math.max(132.0, mq.padding.top + 72.0);
    final bottom = mq.padding.bottom;
    final active = [...rows.working, ...rows.needs];
    final asleep = rows.asleep;
    final reduce = reduceMotion(context);
    final glass = Glass.effectiveEnabled;
    final radius = const BorderRadius.vertical(top: Radius.circular(30));

    final empty = active.isEmpty &&
        asleep.isEmpty &&
        mainSessions.isEmpty &&
        settledSessions.isEmpty;

    final listContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: 168 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kHomeMargin, 4, kHomeMargin, 18),
            child: Text('Everyone',
                style: sans(22, weight: FontWeight.w600, color: AppColors.fg1)),
          ),
          if (active.isNotEmpty) ...[
            _SectionHeader('Working', count: active.length),
            for (var i = 0; i < active.length; i++) ...[
              if (i > 0) _hairline(inset: kHomeMargin + 54),
              _SheetAgentRow(
                key: ValueKey('agent-row-${active[i].agent.id}'),
                row: active[i],
                managedCount: managed[active[i].agent.id]?.length ?? 0,
                onOpen: () => onOpenAgent(active[i].agent),
                onManaged: () => onOpenManaged(active[i].agent),
              ),
            ],
            SizedBox(height: S.of(14)),
          ],
          if (mainSessions.isNotEmpty) ...[
            _SectionHeader('Your sessions', count: mainSessions.length),
            for (var i = 0; i < mainSessions.length; i++) ...[
              if (i > 0) _hairline(inset: kHomeMargin + 44),
              _SheetSessionRow(
                key: ValueKey('session-row-${mainSessions[i].id}'),
                session: mainSessions[i],
                onOpen: () => onOpenSession(mainSessions[i]),
                onLongPress: onSessionActions == null
                    ? null
                    : () => onSessionActions!(mainSessions[i]),
              ),
            ],
            SizedBox(height: S.of(10)),
          ],
          if (asleep.isNotEmpty) ...[
            _hairline(),
            _SheetFoldRow(
              key: const ValueKey('asleep-fold'),
              label: 'Asleep',
              count: asleep.length,
              open: asleepOpen,
              onTap: onToggleAsleep,
              lead: SizedBox(
                width: 28.0 + (asleep.take(4).length - 1) * 20,
                height: 28,
                child: Stack(children: [
                  for (var i = 0; i < asleep.take(4).length; i++)
                    Positioned(
                      left: i * 20.0,
                      child: Opacity(
                        opacity: 0.55,
                        child: AgentMochi(asleep[i].agent.id,
                            size: 28, state: AgentCharacterState.sleeping),
                      ),
                    ),
                ]),
              ),
            ),
            AnimatedSize(
              duration: reduce ? const Duration(milliseconds: 1) : Motion.base,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: asleepOpen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < asleep.length; i++) ...[
                          _hairline(inset: kHomeMargin + 54),
                          _SheetAgentRow(
                            key: ValueKey('agent-row-${asleep[i].agent.id}'),
                            row: asleep[i],
                            dimmed: true,
                            managedCount:
                                managed[asleep[i].agent.id]?.length ?? 0,
                            onOpen: () => onOpenAgent(asleep[i].agent),
                            onManaged: () => onOpenManaged(asleep[i].agent),
                          ),
                        ],
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
          if (settledSessions.isNotEmpty) ...[
            _hairline(),
            _SheetFoldRow(
              key: const ValueKey('settled-fold'),
              label: 'Settled',
              count: settledSessions.length,
              open: settledOpen,
              onTap: onToggleSettled,
            ),
            AnimatedSize(
              duration: reduce ? const Duration(milliseconds: 1) : Motion.base,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: settledOpen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < settledSessions.length; i++) ...[
                          _hairline(inset: kHomeMargin + 44),
                          _SheetSessionRow(
                            key: ValueKey(
                                'session-row-${settledSessions[i].id}'),
                            session: settledSessions[i],
                            onOpen: () => onOpenSession(settledSessions[i]),
                            onLongPress: onSessionActions == null
                                ? null
                                : () => onSessionActions!(settledSessions[i]),
                          ),
                        ],
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
          if (empty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  kHomeMargin, S.s32, kHomeMargin, S.s24),
              child: EmptyState(
                icon: 'chat',
                title: 'No sessions yet',
                body: 'Start one with the plus and it shows up here.',
              ),
            ),
        ],
      ),
    );

    Widget sheet = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 44 pt handle at the top of the sheet: tap or drag down to close.
        Center(
          child: Semantics(
            button: true,
            label: 'Close Everyone sheet',
            child: ExcludeSemantics(
              child: GestureDetector(
                key: const ValueKey('everyone-sheet-handle'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  tapHaptic();
                  onClose();
                },
                onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
                onVerticalDragEnd: (d) => onRelease(d.primaryVelocity ?? 0),
                onVerticalDragCancel: () => onRelease(0),
                child: SizedBox(
                  width: 128,
                  height: 44,
                  child: Align(
                    alignment: const Alignment(0, -0.35),
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.fg1.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: onRefresh == null
              ? listContent
              : PullToRefresh(
                  onRefresh: () async => onRefresh!.call(),
                  child: listContent,
                ),
        ),
      ],
    );

    Widget surface = Material(
      color: AppColors.surface1.withValues(alpha: glass ? 0.78 : 0.96),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
                color: AppColors.fg1.withValues(alpha: 0.08), width: 0.5),
          ),
        ),
        child: sheet,
      ),
    );

    if (glass) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: surface,
      );
    }

    final height = mq.size.height - top;
    return Stack(children: [
      Positioned.fill(
        child: AnimatedBuilder(
          animation: progress,
          builder: (_, child) => IgnorePointer(
            ignoring: progress.value < 0.5,
            child: GestureDetector(
              key: const ValueKey('everyone-sheet-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: ColoredBox(
                  color: Colors.black.withValues(
                      alpha: 0.55 * progress.value.clamp(0.0, 1.0))),
            ),
          ),
        ),
      ),
      Positioned(
        top: top,
        left: 0,
        right: 0,
        // Extra height so an overshoot never shows a gap under the sheet.
        height: height + 48,
        child: AnimatedBuilder(
          animation: progress,
          child: ClipRRect(borderRadius: radius, child: surface),
          builder: (_, child) => Transform.translate(
            offset: Offset(0, (1 - progress.value) * (height + 48)),
            child: child,
          ),
        ),
      ),
    ]);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kHomeMargin, 0, kHomeMargin, 6),
        child: Row(children: [
          Text(label,
              style: sans(13, weight: FontWeight.w600, color: AppColors.fg2)),
          SizedBox(width: S.s6),
          Text('$count', style: mono(12, color: AppColors.fg3)),
        ]),
      );
}

class _SheetAgentRow extends StatelessWidget {
  const _SheetAgentRow({
    super.key,
    required this.row,
    required this.managedCount,
    required this.onOpen,
    required this.onManaged,
    this.dimmed = false,
  });

  final AgentRow row;
  final int managedCount;
  final VoidCallback onOpen;
  final VoidCallback onManaged;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final a = row.agent;
    final charState = switch (row.state) {
      CrewState.needsYou => AgentCharacterState.needs,
      CrewState.working => AgentCharacterState.working,
      CrewState.standingBy => AgentCharacterState.sleeping,
    };
    final avatar = SizedBox(
      width: 40,
      height: 40,
      child: Stack(clipBehavior: Clip.none, children: [
        Opacity(
          opacity: dimmed ? 0.55 : 1,
          child: AgentMochi(a.id, size: 40, state: charState),
        ),
        if (row.state == CrewState.working)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.ok,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.5),
              ),
            ),
          )
        else if (row.state == CrewState.needsYou)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: askAmber,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.5),
              ),
            ),
          ),
      ]),
    );
    final body = Row(children: [
      avatar,
      SizedBox(width: S.of(14)),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(17, weight: FontWeight.w500, color: AppColors.fg1)),
            Row(children: [
              if (row.state == CrewState.working) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: AppColors.ok, shape: BoxShape.circle),
                ),
                SizedBox(width: S.s6),
              ],
              Expanded(
                child: Text.rich(
                    markdownPreviewSpan(
                        row.line, sans(13, color: AppColors.fg3)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ],
        ),
      ),
    ]);
    final tapArea = Semantics(
      button: true,
      label: '${a.displayName}, ${plainPreview(row.line)}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: EdgeInsets.only(
                left: kHomeMargin, right: managedCount > 0 ? S.s8 : kHomeMargin),
            child: managedCount > 0
                ? body
                : Row(children: [
                    Expanded(child: body),
                    SizedBox(width: S.s8),
                    AppIcon('chevron-right', size: 14, color: AppColors.fg3),
                  ]),
          ),
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: managedCount == 0
          ? tapArea
          : Row(children: [
              Expanded(child: tapArea),
              ManagedPill(
                name: a.displayName,
                count: managedCount,
                tone: pillTone(heroAgentColor(a.id)),
                onTap: onManaged,
              ),
              SizedBox(width: S.of(14)),
            ]),
    );
  }
}

class _SheetSessionRow extends StatelessWidget {
  const _SheetSessionRow({
    super.key,
    required this.session,
    required this.onOpen,
    this.onLongPress,
  });

  final SessionInfo session;
  final VoidCallback onOpen;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final title = s.title.trim().isEmpty ? 'Untitled session' : s.title.trim();
    final branch = (s.branch ?? '').trim();
    final meta = branch.isEmpty
        ? projectLabel(s)
        : '${projectLabel(s)} · $branch';
    final done = sessionCameBack(s) && !s.settled;
    final charState = sessionBusy(s)
        ? AgentCharacterState.working
        : AgentCharacterState.idle;
    final left = s.settled ? settledDaysLeft(s) : null;
    final age = left != null ? '${left}d left' : homeAge(s.lastActive);
    return Semantics(
      button: true,
      label: '$title, ${done ? 'Completed' : age}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpen,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: kHomeMargin, vertical: 8),
              child: Row(children: [
                AgentMochi(s.displayAgentId ?? 'snippet',
                    size: 32, state: charState),
                SizedBox(width: S.s12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(17,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: AppColors.fg3)),
                    ],
                  ),
                ),
                SizedBox(width: S.s8),
                Text(done ? 'Completed' : age,
                    maxLines: 1,
                    style: done
                        ? sans(13, color: AppColors.ok)
                        : mono(12, color: AppColors.fg3)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetFoldRow extends StatelessWidget {
  const _SheetFoldRow({
    super.key,
    required this.label,
    required this.count,
    required this.open,
    required this.onTap,
    this.lead,
  });

  final String label;
  final int count;
  final bool open;
  final VoidCallback onTap;
  final Widget? lead;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        expanded: open,
        label: '$label, $count',
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: kHomeMargin),
                child: Row(children: [
                  if (lead != null) ...[lead!, SizedBox(width: S.s12)],
                  Text(label, style: sans(17, color: AppColors.fg2)),
                  SizedBox(width: S.s8),
                  Text('$count', style: mono(12, color: AppColors.fg3)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration:
                        reduceMotion(context) ? Duration.zero : Motion.base,
                    curve: Curves.easeOutCubic,
                    child: AppIcon('chevron-right',
                        size: 14, color: AppColors.fg3),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
