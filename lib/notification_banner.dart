import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'mochi.dart';
import 'markdown_preview.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart' show AppIcon;

/// Slides a banner down 8 and fades it in, 200 ms ease-out; reduced motion
/// is a 1 ms fade.
class BannerArrival extends StatelessWidget {
  const BannerArrival({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final calm = reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: calm ? 1 : 200),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
            offset: Offset(0, calm ? 0 : (t - 1) * 8), child: child),
      ),
      child: child,
    );
  }
}

String notificationKind(Map<String, dynamic> p) =>
    '${p['kind'] ?? ''}'.split('.').last;

String notificationBody(Map<String, dynamic> p) {
  final body = '${p['body'] ?? ''}'.trim();
  return plainPreview(body.isNotEmpty ? body : '${p['message'] ?? ''}'.trim());
}

String notificationAgo(Object? createdAt) {
  final DateTime? t = switch (createdAt) {
    final int s => DateTime.fromMillisecondsSinceEpoch(s * 1000),
    _ => DateTime.tryParse('${createdAt ?? ''}'),
  };
  if (t == null) return 'now';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// The locked needs-you mark: the 6 px dot is the only amber; the words stay
/// fg2 so state is never colour alone.
class NeedsYouMark extends StatelessWidget {
  const NeedsYouMark({super.key, this.fontSize = 11.5});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text('Needs you',
          style: sans(fontSize, weight: W.label, color: AppColors.fg2)),
    ]);
  }
}

/// Glyph for an information banner: merge, check or x for failed.
String informationGlyph(Map<String, dynamic> p) {
  final kind = notificationKind(p);
  if (kind.contains('merge')) return 'git-branch';
  if (const {'error', 'failed'}.contains(kind)) return 'x';
  return 'check';
}

/// A title that carries the terminal state in words, not in a colour. Daemon
/// events often already say "done" or "merged"; do not double-prefix those.
String informationTitle(Map<String, dynamic> p) {
  final raw = '${p['title'] ?? ''}'.trim();
  final kind = notificationKind(p);
  final fallback = switch (kind) {
    'done' || 'completed' => 'Done',
    'error' || 'failed' => 'Failed',
    'message' || 'term' => 'Message',
    'idle' => 'Standing by',
    _ => 'Notification',
  };
  final title = raw.isEmpty ? fallback : raw;
  final lower = title.toLowerCase();
  if (const {'error', 'failed'}.contains(kind) &&
      !lower.startsWith('failed') &&
      !lower.startsWith('error')) {
    return 'Failed: $title';
  }
  if (const {'done', 'completed'}.contains(kind) &&
      !RegExp(r'\b(done|finished|completed|complete|merged)\b')
          .hasMatch(lower)) {
    return 'Done: $title';
  }
  return title;
}

/// NT-01 banner. Desktop is the floating surface2 card for needs-you and
/// information alike, a 28 avatar or 20 glyph, and no hand/amber text. Mobile
/// keeps its roomier touch geometry.
class NotificationBanner extends StatelessWidget {
  const NotificationBanner({
    super.key,
    required this.payload,
    required this.onTap,
    this.onDismiss,
    this.onApprove,
  });

  final Map<String, dynamic> payload;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final compact = !kMobile;
    final kind = notificationKind(payload);
    final needs = kind == 'waiting';
    final failed = const {'error', 'failed'}.contains(kind);
    final body = notificationBody(payload);
    final ago = notificationAgo(payload['created_at']);
    final big = MediaQuery.textScalerOf(context).scale(13) / 13 >= 1.5;
    final rawName = '${payload['title'] ?? ''}'.trim();
    final name = needs
        ? (rawName.isEmpty ? 'Snippet' : rawName)
        : compact
            ? informationTitle(payload)
            : rawName;
    final state = needs ? 'needs you' : (failed ? 'failed' : 'update');
    final amber = AppColors.run;
    final leadingSize = compact ? 28.0 : 32.0;

    final timeText = Text(ago,
        style:
            sans(11, height: compact ? 15 / 11 : null, color: AppColors.fg2));
    final nameText = Text(name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: sans(13,
            weight: W.label,
            height: compact ? 17.6 / 13 : null,
            color: AppColors.fg1));

    final Widget leading = needs
        ? Container(
            width: leadingSize,
            height: leadingSize,
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(leadingSize / 2)),
            clipBehavior: Clip.antiAlias,
            child: AgentMochi('${payload['agent_id'] ?? 'snippet'}',
                size: leadingSize),
          )
        : SizedBox(
            width: leadingSize,
            height: leadingSize,
            child: Center(
                child: AppIcon(informationGlyph(payload),
                    size: 20, color: AppColors.fg2)));

    final needsMark = compact
        ? const NeedsYouMark()
        : Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('hand', size: 14, color: amber),
            const SizedBox(width: 4),
            Text('Needs you', style: sans(11.5, weight: W.label, color: amber)),
          ]);

    final head = needs
        ? Row(children: [
            Flexible(child: nameText),
            const SizedBox(width: 6),
            needsMark,
            if (!big) ...[const Spacer(), timeText],
          ])
        : Row(children: [
            Expanded(child: nameText),
            if (!big) ...[const SizedBox(width: 8), timeText],
          ]);

    final Widget lines = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head,
        if (big) timeText,
        if (body.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: compact ? 4 : 6),
            child: needs
                ? Text(body,
                    maxLines: big ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13,
                        height: compact ? 19 / 13 : null, color: AppColors.fg1))
                : Text(body,
                    maxLines: big ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12,
                        height: compact ? 17 / 12 : null,
                        color: AppColors.fg2)),
          ),
      ],
    );

    return Semantics(
      container: true,
      label: '$name, $state, $body, $ago',
      onTap: onTap,
      onDismiss: onDismiss,
      customSemanticsActions: {
        if (onDismiss != null)
          const CustomSemanticsAction(label: 'Dismiss'): onDismiss!,
        if (onApprove != null)
          const CustomSemanticsAction(label: 'Approve'): onApprove!,
      },
      excludeSemantics: true,
      child: Material(
        color: needs && !compact ? AppColors.attentionTint : AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 64 : 72),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  SizedBox(width: compact ? 10 : 10),
                  Expanded(child: lines),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
