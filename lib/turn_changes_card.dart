import 'package:flutter/material.dart';

import 'file_icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// End-of-turn summary of what the turn changed on disk. One line until
/// tapped; each file opens, and the footer opens every change.
class TurnChangesCard extends StatefulWidget {
  const TurnChangesCard({
    super.key,
    required this.event,
    this.onOpenFile,
    this.onReview,
  });

  final Map<String, dynamic> event;
  final void Function(String path)? onOpenFile;

  /// Opens the whole changes view (the Review changes button).
  final VoidCallback? onReview;

  @override
  State<TurnChangesCard> createState() => _TurnChangesCardState();
}

class _TurnChangesCardState extends State<TurnChangesCard> {
  bool _open = false;

  static int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final files = [
      for (final f in (e['files'] as List? ?? const []))
        if (f is Map)
          (
            path: f['path']?.toString() ?? '',
            add: _n(f['add']),
            del: _n(f['del'])
          ),
    ];
    final total =
        _n(e['total_files']) > 0 ? _n(e['total_files']) : files.length;
    if (total == 0) return const SizedBox.shrink();
    final hidden = total - files.length;
    // Phone spec CH-15: three rows, then "N more files", then Review changes.
    final shown = _open ? files : files.take(3).toList();
    final more = total - shown.length;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                AppIcon('file-diff', size: 20, color: AppColors.fg2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('$total ${total == 1 ? 'file' : 'files'} changed',
                      style: sans(15, weight: W.label, color: AppColors.fg1)),
                ),
                _Delta(_n(e['add']), _n(e['del']), size: 13),
              ]),
            ),
          ),
          for (final f in shown)
            InkWell(
              onTap: widget.onOpenFile == null
                  ? null
                  : () => widget.onOpenFile!(f.path),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    FileGlyph(f.path.split('/').last, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: _Path(f.path)),
                    const SizedBox(width: 10),
                    _Delta(f.add, f.del, size: 13, color: AppColors.fg3),
                  ]),
                ),
              ),
            ),
          if (more > 0)
            InkWell(
              // Shows the rest inline when the event carries them, else opens all.
              onTap: hidden > 0 && !_open
                  ? (widget.onReview ?? () => setState(() => _open = true))
                  : () => setState(() => _open = true),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('$more more ${more == 1 ? 'file' : 'files'}',
                        style: sans(13, color: AppColors.fg3)),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Semantics(
              button: true,
              label: 'Review changes',
              excludeSemantics: true,
              child: Material(
                color: AppColors.fg1,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: widget.onReview,
                  child: SizedBox(
                    height: 48,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      AppIcon('file-diff', size: 18, color: AppColors.bg),
                      const SizedBox(width: 8),
                      Text('Review changes',
                          style: sans(14, weight: W.label, color: AppColors.bg)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Path extends StatelessWidget {
  const _Path(this.path);
  final String path;

  @override
  Widget build(BuildContext context) {
    // Mono, trimmed from the start so the file name stays readable.
    final shown = path.length > 34 ? '\u2026${path.substring(path.length - 33)}' : path;
    return Text(shown,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: mono(12.5, color: AppColors.fg2));
  }
}

class _Delta extends StatelessWidget {
  const _Delta(this.add, this.del, {required this.size, this.color});

  final Color? color;

  final int add;
  final int del;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (add > 0)
        Text('+$add', style: sans(size, color: color ?? AppColors.fg1, tabular: true)),
      if (add > 0 && del > 0) SizedBox(width: S.s6),
      if (del > 0)
        Text('-$del',
            style: sans(size, color: color ?? AppColors.fg2, tabular: true)),
    ]);
  }
}
