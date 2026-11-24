import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'canvas_models.dart';

/// Every canvas on the daemon, newest first, with a way to start a new one.
class CanvasListScreen extends StatefulWidget {
  const CanvasListScreen({
    super.key,
    required this.client,
    required this.onOpen,
    required this.onOpenWorkspace,
  });

  final DaemonClient client;
  final ValueChanged<CanvasSummary> onOpen;

  /// Used when the daemon predates `/canvases`: open its single canvas.
  final VoidCallback onOpenWorkspace;

  @override
  State<CanvasListScreen> createState() => _CanvasListScreenState();
}

class _CanvasListScreenState extends State<CanvasListScreen> {
  List<CanvasSummary>? _items;
  String? _error;
  bool _unsupported = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _unsupported = false;
    });
    try {
      final raw = await widget.client.getCanvases();
      if (!mounted) return;
      final items = [
        for (final j in raw) CanvasSummary.fromJson(j),
      ].where((s) => s.id.isNotEmpty).toList()
        ..sort((a, b) => (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      setState(() => _items = items);
    } on CanvasHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 404 || e.statusCode == 405) {
          _unsupported = true;
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _create() async {
    final title = await _askTitle();
    if (title == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final j = await widget.client.postCanvas(title);
      if (!mounted) return;
      final made = CanvasSummary.fromJson({'title': title, ...j});
      if (made.id.isEmpty) throw 'The daemon returned no canvas id';
      await _load();
      if (mounted) widget.onOpen(made);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not create canvas: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<String?> _askTitle() {
    final controller = TextEditingController(text: 'Untitled canvas');
    return showDialog<String>(
      context: context,
      barrierColor: AppColors.modalScrim,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('New canvas',
            style: sans(16, weight: W.title, color: AppColors.fg1)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: sans(14, color: AppColors.fg1),
          decoration: InputDecoration(
            hintText: 'Name',
            hintStyle: sans(14, color: AppColors.fg4),
          ),
          onSubmitted: (v) =>
              Navigator.of(ctx).pop(v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: sans(13, color: AppColors.fg2)),
            ),
          ),
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () {
                final t = controller.text.trim();
                Navigator.of(ctx).pop(t.isEmpty ? null : t);
              },
              child: Text('Create',
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
            ),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(S.s16, S.s16, S.s16, S.s8),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Back',
                      constraints:
                          const BoxConstraints.tightFor(width: 48, height: 48),
                      icon: AppIcon('arrow-left', size: 18, color: AppColors.fg1),
                    ),
                  Expanded(
                    child: Text('Canvases',
                        style:
                            sans(22, weight: W.title, color: AppColors.fg1)),
                  ),
                  if (!_unsupported)
                    Semantics(
                      button: true,
                      label: 'New canvas',
                      excludeSemantics: true,
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: _creating ? null : _create,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.accentFg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(R.sm),
                            ),
                          ),
                          icon: AppIcon('plus',
                              size: 16, color: AppColors.accentFg),
                          label: Text('New canvas',
                              style: sans(13,
                                  weight: W.label, color: AppColors.accentFg)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_unsupported) {
      return _message(
        'This daemon has a single canvas.',
        action: 'Open it',
        onAction: widget.onOpenWorkspace,
      );
    }
    if (_error != null) {
      return _message('Canvases unavailable: $_error',
          action: 'Retry', onAction: _load);
    }
    final items = _items;
    if (items == null) return const Center(child: DelayedSpinner(size: 22));
    if (items.isEmpty) {
      return _message('No canvases yet. Create one, or ask an agent to draw.');
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(S.s8, S.s4, S.s8, S.s24),
      itemCount: items.length,
      itemBuilder: (_, i) => _row(items[i]),
    );
  }

  Widget _row(CanvasSummary s) {
    final updated =
        s.updatedAt != null ? ' · ${formatCanvasRelativeTime(s.updatedAt!)}' : '';
    final detail =
        '${s.frames} ${s.frames == 1 ? 'frame' : 'frames'} · r${s.rev}$updated';
    return Semantics(
      button: true,
      label: 'Open canvas ${s.displayTitle}, $detail',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          onTap: () => widget.onOpen(s),
          borderRadius: BorderRadius.circular(R.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
              child: Row(
                children: [
                  AppIcon('grid', size: 20, color: AppColors.fg3),
                  SizedBox(width: S.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(14,
                                weight: W.label, color: AppColors.fg1)),
                        SizedBox(height: S.s2),
                        Text(detail,
                            style: sans(12, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  AppIcon('chevron-right', size: 16, color: AppColors.fg3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(String text, {String? action, VoidCallback? onAction}) =>
      Center(
        child: Padding(
          padding: EdgeInsets.all(S.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  textAlign: TextAlign.center,
                  style: sans(13, color: AppColors.fg3)),
              if (action != null) ...[
                SizedBox(height: S.s12),
                SizedBox(
                  height: 44,
                  child: TextButton(
                    onPressed: onAction,
                    child: Text(action,
                        style: sans(13, weight: W.label, color: AppColors.fg1)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
