import 'dart:async';

import 'package:flutter/material.dart';

import 'agent_card.dart' show WorkingRing;
import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../motion.dart';
import '../swr.dart';
import 'shell_nav.dart' show sessionIsActive;

/// Mission Control pinned at the top of the Chats list: what it is doing, one
/// tap from opening it.
class MissionControlCard extends StatefulWidget {
  final DaemonClient client;
  final SessionInfo session;
  final VoidCallback onOpen;
  final AgentLastMessage? lastMessage;

  const MissionControlCard({
    super.key,
    required this.client,
    required this.session,
    required this.onOpen,
    this.lastMessage,
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

  @override
  Widget build(BuildContext context) {
    if (!kMobile) {
      final status = widget.session.status;
      final waiting = status == 'waiting_for_input';
      final working = !waiting && sessionIsActive(status);
      final last = widget.lastMessage;
      final line = last == null
          ? 'Plans, routes and follows up on your work'
          : (last.fromUser ? 'You: ${last.text}' : last.text);
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
            child: Row(children: [
              SizedBox.square(
                dimension: 32,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    decoration: BoxDecoration(
                        color: AppColors.surface2, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const AgentMochi('mission-control', size: 20),
                  ),
                  if (working)
                    const Positioned(
                        left: -3,
                        top: -3,
                        right: -3,
                        bottom: -3,
                        child: WorkingRing(key: ValueKey('mc-working'))),
                  if (waiting)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.run,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.windowBg, width: 2),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Mission Control',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, weight: W.body, color: AppColors.fg1)),
                    const SizedBox(height: 2),
                    SwapText(waiting ? 'Waiting on you' : line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12,
                            color: waiting ? AppColors.run : AppColors.fg3)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: kMobile ? 10 : 6),
      child: Material(
        color: kMobile ? AppColors.surface1 : AppColors.surface2,
        borderRadius: BorderRadius.circular(kMobile ? 18 : 14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Padding(
            padding: EdgeInsets.fromLTRB(kMobile ? 18 : 14, kMobile ? 14 : 11,
                kMobile ? 12 : 10, kMobile ? 14 : 11),
            child: Row(children: [
              const AgentMochi('mission-control', size: 30),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 2),
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
              const SizedBox(width: 6),
              AppIcon('chevron-right', size: 16, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }
}
