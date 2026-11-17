import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../composer/composer_pill.dart' show C7;
import '../theme.dart';
import '../widgets.dart';

/// Desktop sidebar's four page tiles with live count badges.
class SidebarTiles extends StatefulWidget {
  final DaemonClient? client;
  final List<SessionInfo>? sessions;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onOpenPullRequests;
  final VoidCallback? onOpenArtifacts;
  final VoidCallback? onOpenWakes;

  const SidebarTiles({
    super.key,
    required this.client,
    required this.sessions,
    this.onOpenTasks,
    this.onOpenPullRequests,
    this.onOpenArtifacts,
    this.onOpenWakes,
  });

  @override
  State<SidebarTiles> createState() => _SidebarTilesState();
}

class _SidebarTilesState extends State<SidebarTiles> {
  int? _tasks;
  int? _wakes;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void didUpdateWidget(SidebarTiles old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final c = widget.client;
    if (c == null) return;
    // Each count fails on its own: a missing badge beats a broken tile.
    final tasks = c
        .tasks(status: TaskStatus.blocked.wire, limit: 99)
        .then<int?>((l) => l.length)
        .catchError((_) => null);
    final wakes =
        c.wakes().then<int?>((l) => l.wakes.length).catchError((_) => null);
    final t = await tasks;
    final w = await wakes;
    if (!mounted || widget.client != c) return;
    setState(() {
      _tasks = t;
      _wakes = w;
    });
  }

  int get _prs => [
        for (final s in widget.sessions ?? const <SessionInfo>[])
          if (s.pr?.state == 'open') s
      ].length;

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks ?? 0;
    final prs = _prs;
    final wakes = _wakes ?? 0;
    Widget tile(String icon, String label, int count, VoidCallback? onTap,
            {bool attention = false}) =>
        Expanded(
          child: _Tile(
              icon: icon,
              label: label,
              count: count,
              attention: attention,
              onTap: onTap),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: Row(children: [
        tile('task', 'Tasks', tasks, widget.onOpenTasks, attention: tasks > 0),
        const SizedBox(width: 4),
        tile('git-branch', 'PRs', prs, widget.onOpenPullRequests),
        const SizedBox(width: 4),
        tile('file', 'Artifacts', 0, widget.onOpenArtifacts),
        const SizedBox(width: 4),
        tile('clock', 'Wakes', wakes, widget.onOpenWakes),
      ]),
    );
  }
}

class _Tile extends StatefulWidget {
  final String icon;
  final String label;
  final int count;
  final bool attention;
  final VoidCallback? onTap;
  const _Tile({
    required this.icon,
    required this.label,
    required this.count,
    required this.attention,
    required this.onTap,
  });

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          widget.count > 0 ? '${widget.label}, ${widget.count}' : widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: _hover ? C7.rowHi : AppColors.surface1,
              borderRadius: BorderRadius.circular(R.of(10)),
            ),
            child: Stack(children: [
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon(widget.icon, size: 15, color: AppColors.fg2),
                  const SizedBox(height: 3),
                  Text(widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: sans(11, color: AppColors.fg3)),
                ]),
              ),
              if (widget.count > 0)
                Positioned(
                  top: 4,
                  right: 6,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 15, minHeight: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          widget.attention ? AppColors.run : AppColors.surface3,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${widget.count}',
                        style: mono(10.5,
                            color: widget.attention
                                ? AppColors.bg
                                : AppColors.fg1)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
