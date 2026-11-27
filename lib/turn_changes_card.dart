import 'package:flutter/material.dart';

import 'file_icons.dart';
import 'mobile_kit/tokens.dart';
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
    final names = files.take(2).map((f) => f.path.split('/').last).join(', ');
    final more = total - (files.length < 2 ? files.length : 2);
    final fileLine = [names, if (more > 0) 'and $more more']
        .where((x) => x.isNotEmpty)
        .join(' ');
    final hair = Container(
        height: 0.5,
        margin: const EdgeInsets.only(left: 52),
        color: MK.hairline);

    Widget action(String label, VoidCallback? onTap) {
      return TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(label,
                style: sans(14, weight: W.label, color: AppColors.fg1)),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s6),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          // The phone transcript sits on surface1, so the card steps up one.
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(MK.groupRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: true,
            expanded: _open,
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                  child: Row(children: [
                    SizedBox(
                      width: 24,
                      child: Center(
                        child: reverting
                            ? Spinner(size: 16, color: AppColors.fg2)
                            : AppIcon(reverted ? 'check' : 'file-diff',
                                size: 20, color: AppColors.fg2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(15.5,
                                  weight: W.label, color: AppColors.fg1)),
                          if (fileLine.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(fileLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg3)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _Delta(_n(e['add']), _n(e['del']), size: 13.5, tint: true),
                    const SizedBox(width: 10),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: Motion.fast,
                      child: AppIcon('chevron-down',
                          size: 16, color: AppColors.fg3),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          if (_open) ...[
            Container(height: 0.5, color: MK.hairline),
            for (var i = 0; i < files.length; i++) ...[
              if (i > 0) hair,
              _PhoneFileRow(
                path: files[i].path,
                add: files[i].add,
                del: files[i].del,
                onTap: widget.onOpenFile == null
                    ? null
                    : () => widget.onOpenFile!(files[i].path),
              ),
            ],
            if (hidden > 0) ...[
              hair,
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 16, 0),
                child: SizedBox(
                  height: 44,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        '$hidden more ${hidden == 1 ? 'file' : 'files'}',
                        style: sans(13, color: AppColors.fg3)),
                  ),
                ),
              ),
            ],
            Container(height: 0.5, color: MK.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
              child: Row(children: [
                if (reverting)
                  Text('Reverting', style: sans(13, color: AppColors.fg2))
                else if (reverted)
                  Text('Reverted', style: sans(13, color: AppColors.fg3)),
                const Spacer(),
                if (reverted)
                  action('Undo', widget.onReview)
                else if (!reverting)
                  action('Revert all', widget.onReview),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// One changed file on phone: name over its folder, deltas trailing.
class _PhoneFileRow extends StatelessWidget {
  const _PhoneFileRow(
      {required this.path, required this.add, required this.del, this.onTap});
  final String path;
  final int add;
  final int del;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cut = path.lastIndexOf('/');
    final name = cut < 0 ? path : path.substring(cut + 1);
    final dir = cut <= 0 ? '' : path.substring(0, cut);
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          child: Row(children: [
            SizedBox(
                width: 24, child: Center(child: FileGlyph(name, size: 18))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(13.5, color: AppColors.fg1)),
                  if (dir.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(dir,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(11.5, color: AppColors.fg3)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Delta(add, del, size: 13, tint: true),
          ]),
        ),
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta(this.add, this.del,
      {required this.size, this.color, this.tint = false});

  /// Phone: the theme's diff colours.
  final bool tint;

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
                ? sans(size,
                    color: tint ? AppColors.diffAddFg : color ?? AppColors.fg1,
                    tabular: true)
                : mono(size, color: color ?? AppColors.fg2)),
      if (add > 0 && del > 0) SizedBox(width: S.s6),
      if (del > 0)
        Text('−$del',
            style: kMobile
                ? sans(size,
                    color: tint ? AppColors.diffDelFg : color ?? AppColors.fg2,
                    tabular: true)
                : mono(size, color: color ?? AppColors.fg3)),
    ]);
  }
}
