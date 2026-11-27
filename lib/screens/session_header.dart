import 'dart:async';

import 'package:flutter/material.dart';

import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../tap_detector.dart';

/// Desktop chat header: orb, title, status pill and a quiet agent line, with
/// the session actions at the right while the panel is hidden or folded.
class SessionChatHeader extends StatelessWidget {
  const SessionChatHeader({
    super.key,
    required this.agentId,
    required this.title,
    required this.status,
    this.startedAt,
    this.sub,
    this.actions,
    this.onTitleTap,
  });

  static const double height = 56;

  final String agentId;
  final String title;

  /// idle, running, needs-you or another daemon status.
  final String status;

  /// Turn start; the pill counts up from it while the turn runs.
  final DateTime? startedAt;
  final String? sub;
  final Widget? actions;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    final name = Text(title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            sans(15, weight: W.label, color: AppColors.fg1, spacing: -0.075));
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: S.s20),
        child: Row(children: [
          AgentMochi(agentId, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(children: [
                if (onTitleTap == null)
                  name
                else
                  TapDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTitleTap,
                      child: name),
                const SizedBox(width: 10),
                SessionStatusPill(status: status, startedAt: startedAt),
                if ((sub ?? '').isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(sub!,
                      maxLines: 1,
                      softWrap: false,
                      style: sans(12, color: AppColors.fg4)),
                ],
              ]),
            ),
          ),
          if (actions != null) actions!,
        ]),
      ),
    );
  }
}

class SessionStatusPill extends StatefulWidget {
  const SessionStatusPill({super.key, required this.status, this.startedAt});
  final String status;
  final DateTime? startedAt;

  @override
  State<SessionStatusPill> createState() => SessionStatusPillState();
}

class SessionStatusPillState extends State<SessionStatusPill> {
  Timer? _tick;

  bool get _running => widget.status == 'running';

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SessionStatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_running && widget.startedAt != null) {
      _tick ??= Timer.periodic(
          const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (widget.status) {
      'running' => (
          widget.startedAt == null
              ? 'Working'
              : 'Working ${_clock(DateTime.now().difference(widget.startedAt!))}',
          AppColors.fg2,
          AppColors.surface2
        ),
      'waiting_for_input' || 'needs_you' => (
          'Needs you',
          AppColors.run,
          AppColors.runBg
        ),
      'in_review' => ('In review', AppColors.fg2, AppColors.surface2),
      'failed' || 'error' => ('Failed', AppColors.fg1, AppColors.surface2),
      _ => ('Finished', AppColors.fg3, AppColors.surface2),
    };
    if (!kMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_running) ...[
            Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: sans(12,
                  color: widget.status == 'failed' || widget.status == 'error'
                      ? fg
                      : AppColors.fg3,
                  tabular: true),
              maxLines: 1,
              softWrap: false),
        ]),
      );
    }
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(R.of(5))),
      alignment: Alignment.center,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_running) ...[
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: sans(11.5, color: fg, tabular: true),
            maxLines: 1,
            softWrap: false),
      ]),
    );
  }
}

/// Window-bar tools each desktop session publishes; the shell shows the
/// active tab's, so the session has no header row of its own.
class SessionBarTools extends ChangeNotifier {
  final Map<String, (Object, Widget)> _tools = {};
  Widget? of(String? id) => id == null ? null : _tools[id]?.$2;
  void publish(String id, Object owner, Widget w) {
    _tools[id] = (owner, w);
    notifyListeners();
  }

  // Only the current owner may clear: a rebuilt publisher registers before
  // the old one is disposed.
  void clear(String id, Object owner) {
    if (_tools[id]?.$1 != owner) return;
    _tools.remove(id);
    notifyListeners();
  }
}

final SessionBarTools sessionBarTools = SessionBarTools();

/// Publishes [child] to [sessionBarTools] after each build; draws nothing.
class SessionBarPublisher extends StatefulWidget {
  const SessionBarPublisher(
      {super.key, required this.sessionId, required this.child});
  final String sessionId;
  final Widget child;

  @override
  State<SessionBarPublisher> createState() => _SessionBarPublisherState();
}

class _SessionBarPublisherState extends State<SessionBarPublisher> {
  bool _queued = false;

  @override
  void dispose() {
    final id = widget.sessionId;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => sessionBarTools.clear(id, this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_queued) {
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        if (mounted) {
          sessionBarTools.publish(widget.sessionId, this, widget.child);
        }
      });
    }
    return const SizedBox.shrink();
  }
}
