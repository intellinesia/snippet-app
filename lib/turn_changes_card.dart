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
  });

  final Map<String, dynamic> event;
  final void Function(String path)? onOpenFile;

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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.card),
        ),
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.of(10)),
                child: Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(R.md)),
                    child: AppIcon('file-diff', size: 15, color: AppColors.fg2),
                  ),
                  SizedBox(width: S.of(10)),
                  Expanded(
                    child: Text(
                        '$total ${total == 1 ? 'file' : 'files'} changed',
                        style:
                            sans(13, weight: W.label, color: AppColors.fg1)),
                  ),
                  _Delta(_n(e['add']), _n(e['del']), size: 12.5),
                  SizedBox(width: S.s6),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: Motion.base,
                    curve: Curves.easeOutCubic,
                    child: AppIcon('chevron-right',
                        size: 13, color: AppColors.fg4),
                  ),
                ]),
              ),
            ),
          ),
          Reveal(
            show: _open,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final f in files)
                    InkWell(
                      onTap: widget.onOpenFile == null
                          ? null
                          : () => widget.onOpenFile!(f.path),
                      child: SizedBox(
                        height: 32,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(S.of(14), 0, S.of(14), 0),
                          child: Row(children: [
                            FileGlyph(f.path.split('/').last, size: 15),
                            SizedBox(width: S.of(10)),
                            Expanded(child: _Path(f.path)),
                            SizedBox(width: S.of(10)),
                            SizedBox(
                                width: 74,
                                child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _Delta(f.add, f.del, size: 12))),
                          ]),
                        ),
                      ),
                    ),
                  if (hidden > 0)
                    SizedBox(
                      height: 28,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(S.of(39), 0, S.of(14), 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('+$hidden more files',
                              style: sans(12, color: AppColors.fg4)),
                        ),
                      ),
                    ),
                ]),
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
    final i = path.lastIndexOf('/');
    final name = i < 0 ? path : path.substring(i + 1);
    final dir = i < 0 ? '' : path.substring(0, i);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: name, style: sans(13, color: AppColors.fg1)),
        if (dir.isNotEmpty)
          TextSpan(text: '  $dir', style: sans(12, color: AppColors.fg4)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta(this.add, this.del, {required this.size});

  final int add;
  final int del;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (add > 0)
        Text('+$add', style: sans(size, color: AppColors.fg1, tabular: true)),
      if (add > 0 && del > 0) SizedBox(width: S.s6),
      if (del > 0)
        Text('-$del',
            style: sans(size, color: AppColors.fg2, tabular: true)),
    ]);
  }
}
