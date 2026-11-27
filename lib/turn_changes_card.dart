import 'package:flutter/material.dart';

import 'file_icons.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';
import 'tap_detector.dart';

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

  String get _status =>
      (widget.event['status'] ?? widget.event['state'] ?? '').toString();

  Widget _deskAction(BuildContext context) {
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onReview,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('file-diff', size: 12.5, color: AppColors.fg1),
          const SizedBox(width: 6),
          Text('Review changes',
              style: sans(11.5, weight: W.label, color: AppColors.fg1)),
        ]),
      ),
    );
  }

  Widget _desktop(
    BuildContext context, {
    required List<({String path, int add, int del})> files,
    required int total,
    required int hidden,
  }) {
    final e = widget.event;
    final shown = _open ? files : files.take(3).toList();
    final status = _status;
    final reverting = status == 'reverting';
    final reverted = status == 'reverted';
    final title = reverting
        ? 'Reverting $total ${total == 1 ? 'file' : 'files'}'
        : reverted
            ? 'Reverted $total ${total == 1 ? 'file' : 'files'}'
            : '$total ${total == 1 ? 'file' : 'files'} changed';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
                child: Row(children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: Center(
                      child: reverting
                          ? Spinner(size: 13, color: AppColors.fg2)
                          : AppIcon(reverted ? 'undo' : 'file-diff',
                              size: 13,
                              color: reverted ? AppColors.fg3 : AppColors.fg2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12,
                            color: reverting ? AppColors.fg1 : AppColors.fg2)),
                  ),
                  const SizedBox(width: 10),
                  _Delta(_n(e['add']), _n(e['del']), size: 11),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: AnimatedRotation(
                        turns: _open ? 0.25 : 0,
                        duration: Motion.fast,
                        child: AppIcon('chevron-right',
                            size: 12, color: AppColors.fg3),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          if (_open) ...[
            Container(height: 1, color: AppColors.line),
            for (final f in shown)
              TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpenFile == null
                    ? null
                    : () => widget.onOpenFile!(f.path),
                child: SizedBox(
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(children: [
                      FileGlyph(f.path.split('/').last, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(12,
                                weight: W.label, color: AppColors.fg1)),
                      ),
                      const SizedBox(width: 10),
                      _Delta(f.add, f.del, size: 11, color: AppColors.fg3),
                    ]),
                  ),
                ),
              ),
            if (hidden > 0 || files.length > shown.length)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 10, 0),
                child: SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        '${total - shown.length} more ${total - shown.length == 1 ? 'file' : 'files'}',
                        style: sans(11, color: AppColors.fg3)),
                  ),
                ),
              ),
            Container(
              height: 36,
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.line))),
              child: Row(children: [
                if (reverted)
                  Text('Reverted', style: sans(11.5, color: AppColors.fg3))
                else if (reverting)
                  Text('Reverting', style: sans(11.5, color: AppColors.fg2))
                else
                  const SizedBox.shrink(),
                const Spacer(),
                _deskAction(context),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

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
    if (!kMobile) {
      return _desktop(context, files: files, total: total, hidden: hidden);
    }
    // v19 TC-09: the collapsed entry is the row itself. Opening it reveals
    // per-file rows; there is no full-width review CTA on phone.
    final status = _status;
    final reverting = status == 'reverting';
    final reverted = status == 'reverted';
    final title = reverting
        ? 'Reverting $total ${total == 1 ? 'file' : 'files'}'
        : reverted
            ? 'Reverted $total ${total == 1 ? 'file' : 'files'}'
            : '$total ${total == 1 ? 'file' : 'files'} changed';
    final names = files.take(3).map((f) => f.path.split('/').last).join(', ');
    final fileLine = [
      names,
      if (total > 3) '+${total - 3}'
    ].where((x) => x.isNotEmpty).join(' ');

    Widget action(String label, double width, VoidCallback? onTap) {
      return TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: width,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(label,
              style: sans(12.5, weight: W.label, color: AppColors.fg1)),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(7, 0, 8, 0),
                  child: Row(children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Center(
                        child: reverting
                            ? Spinner(size: 13, color: AppColors.fg2)
                            : AppIcon(reverted ? 'check' : 'file-diff',
                                size: 14,
                                color: reverted ? AppColors.fg3 : AppColors.fg2),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(14, color: AppColors.fg2)),
                    ),
                    const SizedBox(width: 10),
                    _Delta(_n(e['add']), _n(e['del']), size: 12.5),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: Motion.fast,
                      child: AppIcon('chevron-right',
                          size: 12, color: AppColors.fg3),
                    ),
                  ]),
                ),
              ),
            ),
            if (_open) ...[
              Container(height: 1, color: AppColors.line),
              for (final f in files)
                TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpenFile == null
                      ? null
                      : () => widget.onOpenFile!(f.path),
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(children: [
                        FileGlyph(f.path.split('/').last, size: 15),
                        const SizedBox(width: 9),
                        Expanded(child: _Path(f.path)),
                        const SizedBox(width: 10),
                        _Delta(f.add, f.del, size: 12.5, color: AppColors.fg3),
                      ]),
                    ),
                  ),
                ),
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 10, 0),
                  child: SizedBox(
                    height: 32,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('$hidden more ${hidden == 1 ? 'file' : 'files'}',
                          style: sans(12, color: AppColors.fg3)),
                    ),
                  ),
                ),
              Container(
                height: 48,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.line))),
                child: Row(children: [
                  if (reverting)
                    Text('Reverting', style: sans(12, color: AppColors.fg2))
                  else if (reverted)
                    Text('Reverted', style: sans(12, color: AppColors.fg3)),
                  const Spacer(),
                  if (reverted)
                    action('Undo', 90, widget.onReview)
                  else if (!reverting)
                    action('Revert all', 120, widget.onReview),
                ]),
              ),
            ],
          ]),
        ),
        if (!_open && fileLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2),
            child: Text(fileLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, color: AppColors.fg3)),
          ),
      ]),
    );
  }
}

class _Path extends StatelessWidget {
  const _Path(this.path);
  final String path;

  @override
  Widget build(BuildContext context) {
    // Mono, trimmed from the start so the file name stays readable.
    final shown =
        path.length > 34 ? '\u2026${path.substring(path.length - 33)}' : path;
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
        Text('+$add',
            style: kMobile
                ? sans(size, color: color ?? AppColors.fg1, tabular: true)
                : mono(size, color: color ?? AppColors.fg2)),
      if (add > 0 && del > 0) SizedBox(width: S.s6),
      if (del > 0)
        Text(kMobile ? '-$del' : '−$del',
            style: kMobile
                ? sans(size, color: color ?? AppColors.fg2, tabular: true)
                : mono(size, color: color ?? AppColors.fg3)),
    ]);
  }
}
