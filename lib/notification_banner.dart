import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'mochi.dart';
import 'markdown_preview.dart';
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

/// Glyph for an information banner: merge, check or x for failed.
String informationGlyph(Map<String, dynamic> p) {
  final kind = notificationKind(p);
  if (kind.contains('merge')) return 'git-branch';
  if (const {'error', 'failed'}.contains(kind)) return 'x';
  return 'check';
}

/// NT-01 banner: a needs-you banner (amber tint, avatar, "Needs you") or an
/// information banner (surface2, glyph, title and sub). Opaque, no shadow.
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
    final needs = notificationKind(payload) == 'waiting';
    final failed = const {'error', 'failed'}.contains(notificationKind(payload));
    final title = '${payload['title'] ?? ''}'.trim();
    final body = notificationBody(payload);
    final ago = notificationAgo(payload['created_at']);
    final big = MediaQuery.textScalerOf(context).scale(13) / 13 >= 1.5;
    final name = title.isEmpty ? 'Snippet' : (failed ? 'Failed: $title' : title);
    final state = needs ? 'needs you' : (failed ? 'failed' : 'update');
    final amber = AppColors.run;

    final timeText = Text(ago, style: sans(11, color: AppColors.fg2));
    final nameText = Text(name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: sans(13, weight: W.label, color: AppColors.fg1));

    final Widget leading = needs
        ? Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: AppColors.surface2, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: AgentMochi('${payload['agent_id'] ?? 'snippet'}', size: 32),
          )
        : SizedBox(
            width: 32,
            height: 32,
            child: Center(
                child: AppIcon(informationGlyph(payload),
                    size: 20, color: AppColors.fg2)));

    final head = needs
        ? Row(children: [
            Flexible(child: nameText),
            const SizedBox(width: 6),
            AppIcon('hand', size: 14, color: amber),
            const SizedBox(width: 4),
            Text('Needs you',
                style: sans(11.5, weight: W.label, color: amber)),
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
            padding: const EdgeInsets.only(top: 6),
            child: needs
                ? Text(body,
                    maxLines: big ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1))
                : Text(body,
                    maxLines: big ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg2)),
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
        color: needs ? AppColors.attentionTint : AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  const SizedBox(width: 10),
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
