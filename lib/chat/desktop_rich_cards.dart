import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';

enum DesktopRichButtonVariant { primary, secondary, ghost }

class DesktopRichButton extends StatelessWidget {
  const DesktopRichButton(
    this.label, {
    super.key,
    this.variant = DesktopRichButtonVariant.secondary,
    this.icon,
    this.onTap,
    this.disabled = false,
    this.busy = false,
    this.parentSurface = 1,
  });

  final String label;
  final DesktopRichButtonVariant variant;
  final String? icon;
  final VoidCallback? onTap;
  final bool disabled;
  final bool busy;
  final int parentSurface;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final inactive = disabled || busy || onTap == null;
    final phone = kMobile;
    final radius = phone ? 8.0 : 6.0;
    final fill = switch (variant) {
      DesktopRichButtonVariant.primary =>
        inactive ? AppColors.surface3 : AppColors.fg1,
      DesktopRichButtonVariant.secondary =>
        parentSurface >= 2 ? AppColors.surface3 : AppColors.surface2,
      DesktopRichButtonVariant.ghost => Colors.transparent,
    };
    final ink = switch (variant) {
      DesktopRichButtonVariant.primary =>
        inactive ? AppColors.fg2 : AppColors.bg,
      DesktopRichButtonVariant.secondary =>
        inactive ? AppColors.fg2 : AppColors.fg1,
      DesktopRichButtonVariant.ghost => AppColors.fg2,
    };
    return Semantics(
      button: true,
      enabled: !inactive,
      label: label,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: inactive ? null : onTap,
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox(
            height: phone ? 36 : 28,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: icon == null ? 12 : 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy) ...[
                    Spinner(size: 12, color: ink),
                    const SizedBox(width: 7),
                  ] else if (icon != null) ...[
                    AppIcon(icon!, size: 13.5, color: ink),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.2,
                          weight: FontWeight.w500, height: 1, color: ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopNeedsYouMark extends StatelessWidget {
  const DesktopNeedsYouMark(
      {super.key, this.size = 12, this.label = 'Needs you'});

  final double size;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              maxLines: 1,
              style: sans(size, weight: FontWeight.w500, color: AppColors.fg2)),
        ],
      );
}

class DesktopCardIconButton extends StatelessWidget {
  const DesktopCardIconButton(
    this.icon, {
    super.key,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: active ? AppColors.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: AppIcon(icon,
                    size: 13.5,
                    color: onTap == null ? AppColors.fg4 : AppColors.fg2),
              ),
            ),
          ),
        ),
      );
}

String desktopFileSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return '${kb < 10 ? kb.toStringAsFixed(1) : kb.round()} KB';
  }
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}

class DesktopFileChip extends StatelessWidget {
  const DesktopFileChip({
    super.key,
    required this.icon,
    required this.name,
    this.sizeLabel = '',
    this.onTap,
    this.trailing,
  });

  final String icon;
  final String name;
  final String sizeLabel;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: 28,
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 14, color: AppColors.fg2),
          const SizedBox(width: 7),
          Flexible(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12.5, height: 1, color: PaneRow.labelOn)),
          ),
          if (sizeLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(sizeLabel,
                maxLines: 1, style: sans(11, height: 1, color: AppColors.fg4)),
          ],
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: child,
        ),
      ),
    );
  }
}

enum DesktopVoiceNoteState { idle, loading, playing, paused, failed }

class DesktopVoiceNoteRow extends StatelessWidget {
  const DesktopVoiceNoteRow({
    super.key,
    required this.durationLabel,
    this.state = DesktopVoiceNoteState.idle,
    this.progress = 0,
    this.seed = 0,
    this.onToggle,
    this.onSeek,
    this.onRetry,
  });

  final String durationLabel;
  final DesktopVoiceNoteState state;
  final double progress;
  final int seed;
  final VoidCallback? onToggle;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = state == DesktopVoiceNoteState.failed;
    final playing = state == DesktopVoiceNoteState.playing;
    final loading = state == DesktopVoiceNoteState.loading;
    return Container(
      height: 48,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: playing ? 'Pause voice note' : 'Play voice note',
            child: Material(
              color: AppColors.surface2,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: failed ? null : onToggle,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: loading
                        ? Spinner(size: 12, color: AppColors.fg2)
                        : AppIcon(playing ? 'pause' : 'play',
                            size: 13, color: AppColors.fg1),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (failed) ...[
            AppIcon('x', size: 13, color: AppColors.fg2),
            const SizedBox(width: 6),
            Text('Could not load', style: sans(12, color: AppColors.fg2)),
            const SizedBox(width: 10),
            DesktopRichButton('Retry',
                variant: DesktopRichButtonVariant.ghost, onTap: onRetry),
          ] else ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: onSeek == null
                  ? null
                  : (d) => onSeek!((d.localPosition.dx / 168).clamp(0.0, 1.0)),
              onHorizontalDragUpdate: onSeek == null
                  ? null
                  : (d) => onSeek!((d.localPosition.dx / 168).clamp(0.0, 1.0)),
              child: SizedBox(
                width: 168,
                height: 28,
                child: CustomPaint(
                  painter: DesktopWaveformPainter(
                    seed: seed,
                    progress: progress.clamp(0.0, 1.0),
                    played: AppColors.fg1,
                    rest: AppColors.fg4,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(durationLabel,
                style: sans(12, tabular: true, color: AppColors.fg2)),
          ],
        ],
      ),
    );
  }
}

class DesktopWaveformPainter extends CustomPainter {
  const DesktopWaveformPainter({
    required this.seed,
    required this.progress,
    required this.played,
    required this.rest,
  });

  final int seed;
  final double progress;
  final Color played;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 42;
    final step = size.width / count;
    final rnd = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final wave = (math.sin((i + seed % 17) * 0.9) + 1) / 2;
      final noise = rnd.nextDouble() * 0.35;
      final h = 5 + (wave * 13 + noise * 8).clamp(0.0, 19.0);
      final x = i * step + step / 2;
      final paint = Paint()
        ..color = i / count <= progress ? played : rest
        ..strokeWidth = math.max(1.6, step * 0.34)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, size.height / 2 - h / 2),
          Offset(x, size.height / 2 + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(DesktopWaveformPainter old) =>
      old.seed != seed ||
      old.progress != progress ||
      old.played != played ||
      old.rest != rest;
}

enum DesktopAttachmentState { uploading, sent, failed }

class DesktopSentAttachmentRow extends StatelessWidget {
  const DesktopSentAttachmentRow({
    super.key,
    required this.icon,
    required this.name,
    this.state = DesktopAttachmentState.sent,
    this.progress = 0,
    this.onOpen,
    this.onCancel,
    this.onRetry,
  });

  final String icon;
  final String name;
  final DesktopAttachmentState state;
  final double progress;
  final VoidCallback? onOpen;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final stateLine = switch (state) {
      DesktopAttachmentState.sent =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('check', size: 12, color: AppColors.fg2),
          const SizedBox(width: 4),
          Text('Sent', style: sans(11.5, color: AppColors.fg2)),
        ]),
      DesktopAttachmentState.uploading =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 72,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                color: AppColors.fg3,
                backgroundColor: AppColors.surface2,
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('${(progress.clamp(0.0, 1.0) * 100).round()}%',
              style: sans(11.5, tabular: true, color: AppColors.fg2)),
        ]),
      DesktopAttachmentState.failed =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('x', size: 12, color: AppColors.fg2),
          const SizedBox(width: 4),
          Text('Upload failed', style: sans(11.5, color: AppColors.fg2)),
        ]),
    };
    if (kMobile) {
      final meta = switch (state) {
        DesktopAttachmentState.sent => 'Sent',
        DesktopAttachmentState.uploading =>
          'Uploading ${(progress.clamp(0.0, 1.0) * 100).round()}%',
        DesktopAttachmentState.failed => 'Upload failed',
      };
      return Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: state == DesktopAttachmentState.sent ? onOpen : null,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                      child: AppIcon(icon, size: 16, color: AppColors.fg2)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(15, height: 1, color: AppColors.fg1)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Flexible(
                          child: Text(meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(13, height: 1, color: AppColors.fg2)),
                        ),
                        if (state == DesktopAttachmentState.uploading) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(1.5),
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                color: AppColors.fg3,
                                backgroundColor: AppColors.surface2,
                                minHeight: 3,
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
                if (state == DesktopAttachmentState.failed) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 55,
                    child: DesktopRichButton('Retry',
                        variant: DesktopRichButtonVariant.secondary,
                        parentSurface: 1,
                        onTap: onRetry),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: state == DesktopAttachmentState.sent ? onOpen : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 52,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: AppIcon(icon, size: 15, color: AppColors.fg2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, height: 1.2, color: AppColors.fg1)),
                    const SizedBox(height: 3),
                    stateLine,
                  ],
                ),
              ),
              if (state == DesktopAttachmentState.uploading && onCancel != null)
                DesktopCardIconButton('x',
                    tooltip: 'Cancel upload', onTap: onCancel),
              if (state == DesktopAttachmentState.failed)
                DesktopRichButton('Retry',
                    variant: DesktopRichButtonVariant.secondary,
                    parentSurface: 1,
                    onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopPastedTextCard extends StatefulWidget {
  const DesktopPastedTextCard({super.key, required this.text});

  final String text;

  @override
  State<DesktopPastedTextCard> createState() => _DesktopPastedTextCardState();
}

class _DesktopPastedTextCardState extends State<DesktopPastedTextCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.text.split('\n');
    final shownCount =
        _expanded ? math.min(9, lines.length) : math.min(3, lines.length);
    final shown = lines.take(shownCount).join('\n');
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  AppIcon('file-text', size: 14, color: AppColors.fg2),
                  const SizedBox(width: 7),
                  Text('Pasted text',
                      style: sans(13,
                          weight: FontWeight.w500, color: AppColors.fg1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${lines.length} lines',
                        maxLines: 1, style: sans(11.5, color: AppColors.fg3)),
                  ),
                  AppIcon(_expanded ? 'chevron-up' : 'chevron-down',
                      size: 13, color: AppColors.fg3),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(shown,
                  maxLines: shownCount,
                  overflow: TextOverflow.ellipsis,
                  style: codeMono(12, height: 1.5, color: AppColors.fg2)),
            ),
          ),
          if (_expanded) ...[
            Container(height: 1, color: AppColors.border),
            SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  Expanded(
                    child: Text('Showing $shownCount of ${lines.length} lines',
                        style: sans(11.5, color: AppColors.fg3)),
                  ),
                  DesktopRichButton('Copy',
                      variant: DesktopRichButtonVariant.secondary,
                      parentSurface: 1, onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.text));
                    toast(context, 'Copied');
                  }),
                  const SizedBox(width: 8),
                  DesktopRichButton('Collapse',
                      variant: DesktopRichButtonVariant.ghost,
                      onTap: () => setState(() => _expanded = false)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum DesktopLinkPreviewState { loading, ready, failed }

class DesktopLinkPreviewCard extends StatelessWidget {
  const DesktopLinkPreviewCard({
    super.key,
    required this.url,
    this.title = '',
    this.host = '',
    this.snippet = '',
    this.favicon,
    this.state = DesktopLinkPreviewState.ready,
    this.onTap,
  });

  final String url;
  final String title;
  final String host;
  final String snippet;
  final ImageProvider? favicon;
  final DesktopLinkPreviewState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = switch (state) {
      DesktopLinkPreviewState.loading => Row(children: [
          Spinner(size: 14, color: AppColors.fg3),
          const SizedBox(width: 8),
          Text('Loading preview', style: sans(12, color: AppColors.fg3)),
        ]),
      DesktopLinkPreviewState.failed => Row(children: [
          AppIcon('link', size: 15, color: AppColors.fg2),
          const SizedBox(width: 8),
          Flexible(
            child: Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12.5, color: AppColors.fg1)),
          ),
        ]),
      DesktopLinkPreviewState.ready => Row(children: [
          Container(
            width: 32,
            height: 32,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(6),
            ),
            child: favicon == null
                ? AppIcon('globe', size: 16, color: AppColors.fg2)
                : Image(
                    image: favicon!, width: 32, height: 32, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? url : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13,
                        weight: FontWeight.w500,
                        height: 18 / 13,
                        color: AppColors.fg1)),
                const SizedBox(height: 2),
                Text(host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, height: 17 / 12, color: AppColors.fg3)),
                if (snippet.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, height: 17 / 12, color: AppColors.fg2)),
                ],
              ],
            ),
          ),
        ]),
    };
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420, minHeight: 56),
          padding: const EdgeInsets.all(10),
          child: content,
        ),
      ),
    );
  }
}

class DesktopDraftBlock extends StatelessWidget {
  const DesktopDraftBlock({
    super.key,
    required this.text,
    this.onUse,
    this.onDismiss,
  });

  final String text;
  final VoidCallback? onUse;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Draft',
                style: sans(11, weight: FontWeight.w500, color: AppColors.fg3)),
            const SizedBox(height: 6),
            Text(text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: sans(13, height: 19 / 13, color: AppColors.fg1)),
            const SizedBox(height: 10),
            Row(children: [
              DesktopRichButton('Use draft',
                  variant: DesktopRichButtonVariant.primary, onTap: onUse),
              const SizedBox(width: 8),
              DesktopRichButton('Dismiss',
                  variant: DesktopRichButtonVariant.ghost, onTap: onDismiss),
            ]),
          ],
        ),
      );
}

class DesktopCodeBlockCard extends StatefulWidget {
  const DesktopCodeBlockCard({
    super.key,
    required this.code,
    this.language = '',
    this.initiallyCollapsed = false,
  });

  final String code;
  final String language;
  final bool initiallyCollapsed;

  @override
  State<DesktopCodeBlockCard> createState() => _DesktopCodeBlockCardState();
}

class _DesktopCodeBlockCardState extends State<DesktopCodeBlockCard> {
  late bool _wrap = const {'md', 'markdown', 'mdx', 'text', 'txt'}
      .contains(widget.language.trim().toLowerCase());
  late int _visible = widget.initiallyCollapsed ? 5 : 10;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.code.split('\n');
    final hidden = math.max(0, lines.length - _visible);
    final expanded = hidden == 0;
    final shown = lines.take(math.min(_visible, lines.length)).join('\n');
    final label =
        widget.language.trim().isEmpty ? 'code' : widget.language.trim();
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Row(children: [
                Text(label,
                    style: sans(11,
                        weight: FontWeight.w500, color: AppColors.fg3)),
                const Spacer(),
                DesktopCardIconButton('wrap',
                    tooltip: _wrap ? 'Unwrap lines' : 'Wrap lines',
                    active: _wrap,
                    onTap: () => setState(() => _wrap = !_wrap)),
                if (_copied)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon('check', size: 13, color: AppColors.fg2),
                      const SizedBox(width: 4),
                      Text('Copied', style: sans(11.5, color: AppColors.fg2)),
                    ]),
                  )
                else
                  DesktopCardIconButton('copy',
                      tooltip: 'Copy code', onTap: _copy),
              ]),
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _wrap
                ? Text(shown,
                    style: codeMono(12, height: 1.5, color: AppColors.fg1))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(shown,
                        softWrap: false,
                        style: codeMono(12, height: 1.5, color: AppColors.fg1)),
                  ),
          ),
          if (lines.length > 10 || _visible > 10) ...[
            Container(height: 1, color: AppColors.border),
            InkWell(
              onTap: () => setState(() {
                if (expanded) {
                  _visible = 10;
                } else {
                  _visible += 5;
                }
              }),
              child: SizedBox(
                height: 28,
                child: Center(
                  child: Text(
                    expanded
                        ? 'Collapse'
                        : 'Show ${math.min(5, hidden)} more lines',
                    style: sans(12, height: 1, color: AppColors.fg2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DesktopMarkdownDiffCard extends StatefulWidget {
  const DesktopMarkdownDiffCard({
    super.key,
    required this.diff,
    this.file = '',
    this.initiallyExpanded = false,
  });

  final String diff;
  final String file;
  final bool initiallyExpanded;

  @override
  State<DesktopMarkdownDiffCard> createState() =>
      _DesktopMarkdownDiffCardState();
}

class _DesktopMarkdownDiffCardState extends State<DesktopMarkdownDiffCard> {
  late bool _expanded = widget.initiallyExpanded;

  List<(String kind, String text)> get _lines => [
        for (final raw in widget.diff.split('\n'))
          if (raw.startsWith('+') && !raw.startsWith('+++'))
            ('add', raw.substring(1))
          else if (raw.startsWith('-') && !raw.startsWith('---'))
            ('del', raw.substring(1))
          else if (raw.startsWith('@@'))
            ('hunk', raw)
          else if (raw.startsWith(' '))
            ('ctx', raw.substring(1))
      ];

  Widget _line((String kind, String text) line, int number) {
    if (line.$1 == 'hunk') {
      return Container(
        width: double.infinity,
        color: AppColors.surface3,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(line.$2,
            style: codeMono(11, height: 1.5, color: AppColors.fg3)),
      );
    }
    final add = line.$1 == 'add';
    final del = line.$1 == 'del';
    final fg = add
        ? AppColors.fg1
        : del
            ? AppColors.fg3
            : AppColors.fg2;
    return Semantics(
      label: add
          ? 'added line'
          : del
              ? 'removed line'
              : 'context line',
      child: Container(
        color: add ? AppColors.surface3 : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 34,
            child: Text('$number',
                textAlign: TextAlign.right,
                style: codeMono(11, height: 1.5, color: AppColors.fg3)),
          ),
          SizedBox(
            width: 18,
            child: Text(
                add
                    ? '+'
                    : del
                        ? '−'
                        : ' ',
                textAlign: TextAlign.center,
                style: codeMono(12, height: 1.5, color: fg)),
          ),
          Expanded(
            child: Text(line.$2.isEmpty ? ' ' : line.$2,
                style: codeMono(12, height: 1.5, color: fg)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final adds = lines.where((l) => l.$1 == 'add').length;
    final dels = lines.where((l) => l.$1 == 'del').length;
    final file = widget.file.isEmpty ? 'diff' : widget.file;
    final header = SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          AppIcon('file-diff', size: 14, color: AppColors.fg2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(file,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, weight: FontWeight.w500, color: AppColors.fg1)),
          ),
          Text('+$adds −$dels', style: codeMono(11.5, color: AppColors.fg2)),
          const SizedBox(width: 8),
          if (_expanded)
            DesktopCardIconButton('chevron-up',
                tooltip: 'Collapse diff',
                onTap: () => setState(() => _expanded = false))
          else
            AppIcon('chevron-down', size: 13, color: AppColors.fg3),
        ]),
      ),
    );
    if (!_expanded) {
      return Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _expanded = true),
          borderRadius: BorderRadius.circular(8),
          child: header,
        ),
      );
    }
    var oldNum = 0;
    var newNum = 0;
    final rows = <Widget>[];
    for (final line in lines) {
      var number = 0;
      if (line.$1 == 'del') number = ++oldNum;
      if (line.$1 != 'del' && line.$1 != 'hunk') number = ++newNum;
      rows.add(_line(line, number));
    }
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        header,
        Container(height: 1, color: AppColors.border),
        ...rows,
      ]),
    );
  }
}

class DesktopMarkdownTable extends StatelessWidget {
  const DesktopMarkdownTable(
      {super.key, required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            horizontalInside: BorderSide(color: AppColors.border),
            bottom: BorderSide(color: AppColors.border),
          ),
          children: [
            TableRow(children: [
              for (final c in columns)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(c,
                      style: sans(12,
                          weight: FontWeight.w500, color: AppColors.fg2)),
                ),
            ]),
            for (final row in rows)
              TableRow(children: [
                for (final cell in row)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(cell,
                        style: sans(12, height: 17 / 12, color: AppColors.fg1)),
                  ),
              ]),
          ],
        ),
      );
}

class DesktopBlockquote extends StatelessWidget {
  const DesktopBlockquote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.fg3, width: 2)),
        ),
        child:
            Text(text, style: sans(13, height: 19 / 13, color: AppColors.fg2)),
      );
}

enum DesktopPullRequestState { open, merged, closed, checksFailing }

class DesktopPullRequestCard extends StatelessWidget {
  const DesktopPullRequestCard({
    super.key,
    required this.number,
    required this.title,
    this.state = DesktopPullRequestState.open,
    this.checksPassed = 0,
    this.checksTotal = 0,
    this.onOpen,
  });

  final int number;
  final String title;
  final DesktopPullRequestState state;
  final int checksPassed;
  final int checksTotal;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final failing = state == DesktopPullRequestState.checksFailing;
    final stateLabel = switch (state) {
      DesktopPullRequestState.open => 'Open',
      DesktopPullRequestState.merged => 'Merged',
      DesktopPullRequestState.closed => 'Closed',
      DesktopPullRequestState.checksFailing => 'Checks failing',
    };
    if (kMobile) {
      final chipLabel = state == DesktopPullRequestState.checksFailing
          ? 'Open'
          : stateLabel;
      return TapDetector(
        onTap: onOpen,
        child: Container(
          width: double.infinity,
          height: 94,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AppIcon('pull-request', size: 14, color: AppColors.fg1),
              const SizedBox(width: 8),
              Expanded(
                child: Text('#$number $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15,
                        weight: FontWeight.w500, color: AppColors.fg1)),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6.5),
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(R.of(6)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('pull-request', size: 11, color: AppColors.fg1),
                  const SizedBox(width: 4),
                  Text(chipLabel,
                      style: sans(13,
                          weight: FontWeight.w500, color: AppColors.fg1)),
                ]),
              ),
              if (checksTotal > 0) ...[
                const SizedBox(width: 10),
                AppIcon(failing ? 'x' : 'check', size: 12, color: AppColors.fg2),
                const SizedBox(width: 4),
                Text(
                  failing
                      ? 'Checks failing: $checksPassed/$checksTotal'
                      : 'Checks $checksPassed/$checksTotal',
                  style: sans(13, color: AppColors.fg2),
                ),
              ],
            ]),
            const Spacer(),
            Text(
              switch (state) {
                DesktopPullRequestState.merged => 'Merged',
                DesktopPullRequestState.closed => 'Closed without merging',
                _ => 'Pull request',
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg3),
            ),
          ]),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        AppIcon('pull-request', size: 15, color: AppColors.fg2),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PR #$number $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      weight: FontWeight.w500,
                      height: 18 / 13,
                      color: AppColors.fg1)),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (failing) ...[
                  AppIcon('x', size: 12, color: AppColors.fg2),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    [
                      if (checksTotal > 0) 'checks $checksPassed/$checksTotal',
                      stateLabel,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg2),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        DesktopRichButton('Open PR',
            variant: DesktopRichButtonVariant.ghost, onTap: onOpen),
      ]),
    );
  }
}

class DesktopCommitCard extends StatelessWidget {
  const DesktopCommitCard({
    super.key,
    required this.hash,
    required this.message,
    this.authorAvatar,
    this.time = '',
    this.onOpen,
  });

  final String hash;
  final String message;
  final Widget? authorAvatar;
  final String time;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => kMobile
      ? Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 68,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      AppIcon('commit', size: 14, color: AppColors.fg2),
                      const SizedBox(width: 8),
                      Text(hash.length > 7 ? hash.substring(0, 7) : hash,
                          style: codeMono(12.5, color: AppColors.fg2)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(15,
                                weight: FontWeight.w500, color: AppColors.fg1)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: authorAvatar == null
                            ? null
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: authorAvatar),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, color: AppColors.fg3)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        )
      : Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Text(hash.length > 7 ? hash.substring(0, 7) : hash,
                    style: codeMono(12,
                        weight: FontWeight.w500, color: AppColors.fg1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg1)),
                ),
                if (authorAvatar != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(width: 18, height: 18, child: authorAvatar),
                ],
                if (time.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(time, style: sans(11.5, color: AppColors.fg3)),
                ],
              ]),
            ),
          ),
        ),
      );
}

class DesktopVoiceTranscriptCard extends StatefulWidget {
  const DesktopVoiceTranscriptCard({
    super.key,
    required this.lines,
    this.title = 'Voice transcript',
  });

  final List<String> lines;
  final String title;

  @override
  State<DesktopVoiceTranscriptCard> createState() =>
      _DesktopVoiceTranscriptCardState();
}

class _DesktopVoiceTranscriptCardState
    extends State<DesktopVoiceTranscriptCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 460),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  AppIcon('file-text', size: 14, color: AppColors.fg2),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(widget.title,
                        style: sans(13,
                            weight: FontWeight.w500, color: AppColors.fg1)),
                  ),
                  AppIcon(_open ? 'chevron-up' : 'chevron-down',
                      size: 13, color: AppColors.fg3),
                ]),
              ),
            ),
          ),
          if (_open) ...[
            Container(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in widget.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: DesktopBlockquote(text: line),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: DesktopRichButton('Copy',
                        variant: DesktopRichButtonVariant.ghost, onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.lines.join('\n')));
                      toast(context, 'Copied');
                    }),
                  ),
                ],
              ),
            ),
          ],
        ]),
      );
}

enum DesktopNotificationActionKind { none, approval, answer, reply, view }

class DesktopNotificationMessageCard extends StatelessWidget {
  const DesktopNotificationMessageCard({
    super.key,
    required this.name,
    required this.time,
    required this.title,
    this.avatar,
    this.needsYou = false,
    this.surface = 1,
    this.actionKind = DesktopNotificationActionKind.none,
    this.options = const [],
    this.sending = false,
    this.failed = false,
    this.onApprove,
    this.onDeny,
    this.onOption,
    this.onReply,
    this.onView,
    this.onRetry,
  });

  final String name;
  final String time;
  final String title;
  final Widget? avatar;
  final bool needsYou;
  final int surface;
  final DesktopNotificationActionKind actionKind;
  final List<String> options;
  final bool sending;
  final bool failed;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;
  final ValueChanged<String>? onOption;
  final VoidCallback? onReply;
  final VoidCallback? onView;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final fill = surface >= 2 ? AppColors.surface2 : AppColors.surface1;
    final actions = switch (actionKind) {
      DesktopNotificationActionKind.approval => [
          DesktopRichButton(sending ? 'Sending answer…' : 'Approve',
              variant: DesktopRichButtonVariant.primary,
              busy: sending,
              onTap: onApprove),
          DesktopRichButton('Deny',
              variant: DesktopRichButtonVariant.secondary,
              parentSurface: surface,
              onTap: onDeny),
        ],
      DesktopNotificationActionKind.answer => [
          for (final option in options)
            DesktopRichButton(option,
                variant: DesktopRichButtonVariant.secondary,
                parentSurface: surface,
                onTap: onOption == null ? null : () => onOption!(option)),
          DesktopRichButton('Reply',
              variant: DesktopRichButtonVariant.ghost, onTap: onReply),
        ],
      DesktopNotificationActionKind.reply => [
          DesktopRichButton('Reply',
              variant: DesktopRichButtonVariant.secondary,
              parentSurface: surface,
              onTap: onReply),
        ],
      DesktopNotificationActionKind.view => [
          DesktopRichButton('View',
              variant: DesktopRichButtonVariant.secondary,
              parentSurface: surface,
              onTap: onView),
        ],
      DesktopNotificationActionKind.none => const <Widget>[],
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: fill, borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
              width: 20,
              height: 20,
              child: avatar ??
                  Container(
                    decoration: BoxDecoration(
                        color: AppColors.surface3, shape: BoxShape.circle),
                  ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(12, weight: FontWeight.w500, color: AppColors.fg1)),
            ),
            Text(time, style: sans(11, color: AppColors.fg2)),
          ]),
          if (needsYou) ...[
            const SizedBox(height: 8),
            const DesktopNeedsYouMark(),
          ],
          const SizedBox(height: 6),
          Text(title, style: sans(13, height: 18 / 13, color: AppColors.fg1)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
          if (sending) ...[
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Spinner(size: 12, color: AppColors.fg2),
              const SizedBox(width: 6),
              Text('Sending answer…', style: sans(12, color: AppColors.fg2)),
            ]),
          ],
          if (failed) ...[
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('x', size: 12, color: AppColors.fg1),
              const SizedBox(width: 5),
              Text('Could not send', style: sans(12, color: AppColors.fg1)),
              const SizedBox(width: 8),
              DesktopRichButton('Retry',
                  variant: DesktopRichButtonVariant.secondary,
                  parentSurface: surface,
                  onTap: onRetry),
            ]),
          ],
        ],
      ),
    );
  }
}

class DesktopHoverThumbnail extends StatelessWidget {
  const DesktopHoverThumbnail({
    super.key,
    required this.name,
    this.image,
    this.dimensions = '',
    this.sizeLabel = '',
    this.loading = false,
    this.failed = false,
    this.onOpen,
  });

  final String name;
  final ImageProvider? image;
  final String dimensions;
  final String sizeLabel;
  final bool loading;
  final bool failed;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (dimensions.isNotEmpty) dimensions,
      if (sizeLabel.isNotEmpty) sizeLabel,
      'click to open',
    ].join(' - ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 264,
          height: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(8),
            boxShadow: overlayShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: double.infinity,
                    color: AppColors.surface2,
                    alignment: Alignment.center,
                    child: loading
                        ? Column(mainAxisSize: MainAxisSize.min, children: [
                            Spinner(size: 14, color: AppColors.fg3),
                            const SizedBox(height: 6),
                            Text('Loading',
                                style: sans(11, color: AppColors.fg3)),
                          ])
                        : failed
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                AppIcon('image',
                                    size: 14, color: AppColors.fg2),
                                const SizedBox(width: 5),
                                Text('Could not load',
                                    style: sans(11.5, color: AppColors.fg2)),
                              ])
                            : image == null
                                ? AppIcon('image',
                                    size: 20, color: AppColors.fg3)
                                : Image(image: image!, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(12, weight: FontWeight.w500, color: AppColors.fg1)),
              const SizedBox(height: 1),
              Text(meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(11, color: AppColors.fg3)),
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopImageGalleryGrid extends StatelessWidget {
  const DesktopImageGalleryGrid({
    super.key,
    required this.tiles,
    this.overflowCount = 0,
    this.onOverflowTap,
  });

  final List<Widget> tiles;
  final int overflowCount;
  final VoidCallback? onOverflowTap;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox(height: 124);
    final shown = tiles.take(math.min(4, tiles.length)).toList();
    Widget tile(int i, {bool overlay = false}) {
      final base = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.expand(child: shown[i]),
      );
      if (!overlay) return base;
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(fit: StackFit.expand, children: [
          shown[i],
          Material(
            color: const Color(0xBD121211),
            child: InkWell(
              onTap: onOverflowTap,
              child: Center(
                child: Text('+$overflowCount',
                    // The overlay is always dark, so the count is always white.
                    style: sans(15,
                        weight: FontWeight.w500, color: Colors.white)),
              ),
            ),
          ),
        ]),
      );
    }

    return SizedBox(
      height: 124,
      child: switch (shown.length) {
        1 => tile(0),
        2 => Row(children: [
            Expanded(child: tile(0)),
            const SizedBox(width: 4),
            Expanded(child: tile(1)),
          ]),
        3 => Row(children: [
            Expanded(flex: 60, child: tile(0)),
            const SizedBox(width: 4),
            Expanded(
              flex: 40,
              child: Column(children: [
                Expanded(child: tile(1)),
                const SizedBox(height: 4),
                Expanded(child: tile(2)),
              ]),
            ),
          ]),
        _ => Column(children: [
            Expanded(
              child: Row(children: [
                Expanded(child: tile(0)),
                const SizedBox(width: 4),
                Expanded(child: tile(1)),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Row(children: [
                Expanded(child: tile(2)),
                const SizedBox(width: 4),
                Expanded(child: tile(3, overlay: overflowCount > 0)),
              ]),
            ),
          ]),
      },
    );
  }
}
