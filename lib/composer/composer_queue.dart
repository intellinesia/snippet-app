import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'composer_pill.dart';
import '../mobile_kit.dart' show MK, MkGlass, kAndroidLook;
import '../tap_detector.dart';

/// One held message as the queue shows it.
class ComposerQueueEntry {
  const ComposerQueueEntry({
    required this.label,
    required this.onSend,
    required this.onMore,
    this.muted = false,
    this.lead,
    this.extra,
  });

  final String label;
  final bool muted;

  /// Image thumbnails before the text.
  final Widget? lead;

  /// Attachment counts after the text.
  final Widget? extra;
  final VoidCallback onSend;
  final void Function(BuildContext anchor) onMore;
}

/// Queued messages above the composer: a numbered Duet group, with a header
/// to clear them or send them all now once there is more than one.
class ComposerQueueList extends StatelessWidget {
  const ComposerQueueList({
    super.key,
    required this.entries,
    required this.onClear,
    required this.onSendAll,
    this.maxHeight = 172,
  });

  final List<ComposerQueueEntry> entries;
  final VoidCallback onClear;
  final VoidCallback onSendAll;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final n = entries.length;
    if (n == 0) return const SizedBox.shrink();
    if (kMobile) return _phone(n);
    Widget link(String label, VoidCallback onTap, Color color,
            {bool strong = false}) =>
        Semantics(
          button: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 0, 4),
              child: Text(label,
                  style:
                      sans(14, weight: strong ? W.label : null, color: color)),
            ),
          ),
        );
    final rows = [
      for (var i = 0; i < n; i++) _row(i, n, entries[i]),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n > 1)
            // Its own surface, so the transcript never shows through the line.
            Container(
              decoration: BoxDecoration(
                  color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Row(children: [
                Expanded(
                  child: Text(
                      kMobile
                          ? 'Queued $n, sent after this run'
                          : '$n queued · sent in order when this turn ends',
                      maxLines: 2,
                      style: kMobile
                          ? sans(11.5,
                              weight: W.label, height: 16 / 11.5, color: AppColors.fg3)
                          : sans(14, height: 19 / 14, color: AppColors.fg3)),
                ),
                link('Clear', onClear, AppColors.fg2),
                link('Send all now', onSendAll, AppColors.accent, strong: true),
              ]),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              reverse: true,
              child: ComposerGroup(ends: 18, children: rows),
            ),
          ),
        ],
      ),
    );
  }

  // Phone: one control surface beside the composer, rows split by hairlines.
  Widget _phone(int n) {
    Widget link(String label, VoidCallback onTap, {bool strong = false}) =>
        Semantics(
          button: true,
          excludeSemantics: true,
          label: label,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tapHaptic();
              onTap();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: Text(label,
                      style: sans(14,
                          weight: strong ? W.label : null,
                          color: strong ? AppColors.fg1 : AppColors.fg2)),
                ),
              ),
            ),
          ),
        );
    final rows = <Widget>[
      for (var i = 0; i < n; i++) ...[
        if (i > 0)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: ColoredBox(
                color: MK.hairline, child: const SizedBox(height: 0.5)),
          ),
        _phoneRow(entries[i], single: n == 1),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MkGlass(
        radius: kAndroidLook ? 16 : 22,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (n > 1)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 6),
                child: Row(children: [
                  Expanded(
                    child: Text('$n queued',
                        style: sans(13, color: AppColors.fg3, tabular: true)),
                  ),
                  link('Clear', onClear),
                  link('Send all now', onSendAll, strong: true),
                ]),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneRow(ComposerQueueEntry e, {required bool single}) =>
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: single ? 56 : 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(children: [
            AppIcon('clock', size: 18, color: AppColors.fg3),
            const SizedBox(width: 10),
            if (e.lead != null) ...[e.lead!, const SizedBox(width: 8)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15,
                          color: e.muted ? AppColors.fg3 : AppColors.fg1)),
                  if (single)
                    Text('Sends when this turn ends',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg3)),
                ],
              ),
            ),
            if (e.extra != null) ...[const SizedBox(width: 6), e.extra!],
            Builder(
              builder: (ctx) => _action('more-horizontal', 'More',
                  AppColors.fg3, () => e.onMore(ctx)),
            ),
            _action('arrow-up', 'Send now', AppColors.fg1, e.onSend),
          ]),
        ),
      );

  Widget _row(int i, int n, ComposerQueueEntry e) {
    return Container(
      decoration: BoxDecoration(
          color: kMobile ? AppColors.surface3 : C7.row,
          borderRadius: BorderRadius.circular(kMobile ? 8 : 0)),
      constraints: BoxConstraints(minHeight: kMobile ? 48 : 56),
      padding: EdgeInsets.fromLTRB(kMobile ? 10 : 14, 6, 4, 6),
      child: Row(children: [
        if (kMobile) ...[
          AppIcon('grip', size: 16, color: AppColors.fg3),
          const SizedBox(width: 10),
        ] else if (n > 1) ...[
          SizedBox(
            width: 12,
            child: Text('${i + 1}', style: codeMono(12, color: AppColors.fg4)),
          ),
          const SizedBox(width: 8),
        ],
        if (e.lead != null) ...[e.lead!, const SizedBox(width: 6)],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 14 : 15,
                      height: 20 / (kMobile ? 14 : 15),
                      color: e.muted ? AppColors.fg3 : AppColors.fg1)),
              if (n == 1)
                Text('Queued · sent when this turn ends',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, height: 17 / 13, color: AppColors.fg3)),
            ],
          ),
        ),
        if (e.extra != null) ...[const SizedBox(width: 6), e.extra!],
        const SizedBox(width: 4),
        Builder(
          builder: (ctx) => _action(
              'more-horizontal', 'More', AppColors.fg3, () => e.onMore(ctx)),
        ),
        _action('arrow-up', 'Send now', AppColors.accent, e.onSend),
      ]),
    );
  }

  Widget _action(String icon, String tip, Color color, VoidCallback onTap) {
    final w = Semantics(
      button: true,
      label: tip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            tapHaptic();
            onTap();
          },
          child: SizedBox.square(
            dimension: C7.btn,
            child: Center(child: AppIcon(icon, size: 18, color: color)),
          ),
        ),
      ),
    );
    return kMobile ? w : Tooltip(message: tip, child: w);
  }
}
