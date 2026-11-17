import 'dart:async';

import 'package:flutter/material.dart';

import 'agent_card.dart' show DeskRow, WorkingRing;
import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../motion.dart';
import '../swr.dart';
import 'shell_nav.dart' show sessionIsActive;

/// Totals shown under the desktop Mission Control card. [cameBack] is null
/// when the daemon sends no task counts, which drops that cell.
class McStats {
  const McStats({this.inFlight = 0, this.needsYou = 0, this.cameBack});
  final int inFlight;
  final int needsYou;
  final int? cameBack;
}

/// Mission Control pinned at the top of the Chats list: what it is doing, one
/// tap from opening it.
class MissionControlCard extends StatefulWidget {
  final DaemonClient client;
  final SessionInfo session;
  final VoidCallback onOpen;
  final AgentLastMessage? lastMessage;
  final bool selected;

  /// Desktop: the agent's presence detail, preferred over its last message.
  final String? presenceDetail;

  /// Desktop: the strip under the card; omitted when null.
  final McStats? stats;

  const MissionControlCard({
    super.key,
    required this.client,
    required this.session,
    required this.onOpen,
    this.lastMessage,
    this.selected = false,
    this.presenceDetail,
    this.stats,
  });

  @override
  State<MissionControlCard> createState() => _MissionControlCardState();
}

class _MissionControlCardState extends State<MissionControlCard> {
  Map<String, dynamic>? _autonomy;
  Revalidator? _live;

  @override
  void initState() {
    super.initState();
    _autonomy = widget.client.cachedMcAutonomy();
    _load();
    _bindLive();
  }

  @override
  void didUpdateWidget(MissionControlCard old) {
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
        on: (e) =>
            Swr.coordination(e) ||
            e['kind'] == 'config' ||
            e['session'] == 'mission-control',
        debounce: const Duration(seconds: 2),
        onRevalidate: ({required bool force}) => _load());
  }

  @override
  void dispose() {
    _live?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final autonomy = await widget.client.mcAutonomy();
      if (!mounted) return;
      setState(() => _autonomy = autonomy);
    } catch (_) {}
  }

  String _statusLine() {
    final status = widget.session.status;
    if (status == 'running') return 'Working now';
    if (status == 'waiting_for_input') return 'Waiting for you';
    final a = _autonomy;
    if (a != null && a['on'] == true) {
      if (a['in_quiet_hours'] == true) return 'Wakes on · quiet hours';
      final next = (a['next_round_at'] as num?)?.toInt();
      if (next != null && next > 0) {
        final offset = (a['utc_offset_minutes'] as num?)?.toInt() ??
            DateTime.now().timeZoneOffset.inMinutes;
        final t = DateTime.fromMillisecondsSinceEpoch(next * 1000, isUtc: true)
            .add(Duration(minutes: offset));
        final hh = t.hour.toString().padLeft(2, '0');
        final mm = t.minute.toString().padLeft(2, '0');
        final sign = offset < 0 ? '−' : '+';
        final oh = offset.abs() ~/ 60;
        final om = offset.abs() % 60;
        final tz = om == 0
            ? 'UTC$sign$oh'
            : 'UTC$sign$oh:${om.toString().padLeft(2, '0')}';
        return 'Next wake $hh:$mm $tz';
      }
      return 'Wakes on';
    }
    return 'Plans, routes and follows up on your work';
  }

  Widget _statCell(String label, int n, Color color, {String? tip}) {
    final cell = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(9)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n',
            style:
                sans(15, weight: FontWeight.w600, color: color, tabular: true)),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(10.5, color: AppColors.fg3)),
      ]),
    );
    return Expanded(
        child: tip == null ? cell : Tooltip(message: tip, child: cell));
  }

  @override
  Widget build(BuildContext context) {
    if (!kMobile) {
      final status = widget.session.status;
      final waiting = status == 'waiting_for_input';
      final working = !waiting && sessionIsActive(status);
      final last = widget.lastMessage;
      final detail = widget.presenceDetail?.trim() ?? '';
      final line = detail.isNotEmpty
          ? detail
          : last != null
              ? (last.fromUser ? 'You: ${last.text}' : last.text)
              : _statusLine();
      final stats = widget.stats;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          decoration: BoxDecoration(
              color: widget.selected ? AppColors.surface2 : AppColors.surface1,
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.all(10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: const ValueKey('mc-card-open'),
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onOpen,
                child: Row(children: [
                  SizedBox.square(
                    dimension: 30,
                    child: Stack(clipBehavior: Clip.none, children: [
                      const Center(
                          child: AgentMochi('mission-control', size: 30)),
                      if (working)
                        const Positioned(
                            left: -3,
                            top: -3,
                            right: -3,
                            bottom: -3,
                            child: WorkingRing(key: ValueKey('mc-working'))),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mission Control',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DeskRow.nameStyle()),
                        const SizedBox(height: 1),
                        SwapText(waiting ? 'Waiting on you' : line,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12,
                                height: 16 / 12,
                                color:
                                    waiting ? AppColors.run : AppColors.fg3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppIcon('chevron-right', size: 14, color: AppColors.fg4),
                ]),
              ),
            ),
            if (stats != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                _statCell('in flight', stats.inFlight, AppColors.fg1),
                const SizedBox(width: 2),
                _statCell('needs you', stats.needsYou,
                    stats.needsYou > 0 ? AppColors.run : AppColors.fg1),
                if (stats.cameBack != null) ...[
                  const SizedBox(width: 2),
                  _statCell('completed', stats.cameBack!, AppColors.fg1,
                      tip: 'Tasks finished in the last 7 days'),
                ],
              ]),
            ],
          ]),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: kMobile ? S.of(10) : S.s6),
      child: Material(
        color: kMobile ? AppColors.surface1 : AppColors.surface2,
        borderRadius: BorderRadius.circular(kMobile ? 18 : 14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                kMobile ? S.of(18) : S.of(14),
                kMobile ? S.of(14) : S.of(11),
                kMobile ? S.s12 : S.of(10),
                kMobile ? S.of(14) : S.of(11)),
            child: Row(children: [
              const AgentMochi('mission-control', size: 30),
              SizedBox(width: S.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mission Control',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 16 : 14,
                            spacing: -0.2,
                            height: kMobile ? 21 / 16 : 19 / 14,
                            color: AppColors.fg1)),
                    SizedBox(height: S.s2),
                    Row(children: [
                      Flexible(
                        child: SwapText(_statusLine(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12,
                                height: 16 / 12, color: AppColors.fg3)),
                      ),
                    ]),
                  ],
                ),
              ),
              SizedBox(width: S.s6),
              AppIcon('chevron-right', size: 16, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }
}
