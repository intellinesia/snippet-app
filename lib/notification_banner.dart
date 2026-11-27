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
    if (compact) {
      return _slim(context, needs: needs, body: body, ago: ago, state: state);
    }
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

    final needsMark = compact || !kMobile
        ? const NeedsYouMark()
        : Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('hand', size: 14, color: amber),
            const SizedBox(width: 4),
            Text('Needs you', style: sans(11.5, weight: W.label, color: amber)),
          ]);

    final head = needs
        ? Row(children: [
            // The marker rides after the title; the time keeps the right edge.
            Expanded(
              child: Row(children: [
                Flexible(child: nameText),
                const SizedBox(width: 6),
                needsMark,
              ]),
            ),
            if (!big) ...[const SizedBox(width: 8), timeText],
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

  /// Desktop slim toast: a 40 high one-line pill, avatar with a state badge,
  /// short name, body and time.
  Widget _slim(BuildContext context,
      {required bool needs,
      required String body,
      required String ago,
      required String state}) {
    final kind = notificationKind(payload);
    final raw = '${payload['title'] ?? ''}'.trim();
    final short = notificationShortName(
        raw.isEmpty ? (needs ? 'Snippet' : informationTitle(payload)) : raw);
    final line = body.isNotEmpty
        ? body.replaceAll(RegExp(r'\s+'), ' ')
        : (needs ? 'Needs you' : informationTitle(payload));
    return Semantics(
      container: true,
      label: '$short, $state, $body, $ago',
      onTap: onTap,
      onDismiss: onDismiss,
      customSemanticsActions: {
        if (onDismiss != null)
          const CustomSemanticsAction(label: 'Dismiss'): onDismiss!,
        if (onApprove != null)
          const CustomSemanticsAction(label: 'Approve'): onApprove!,
      },
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20), boxShadow: toastShadow),
        child: Material(
          color: AppColors.surface2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                  color: AppColors.fg1.withValues(alpha: 0.09), width: 0.8)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.only(left: 9, right: 14),
                child: Row(children: [
                  ToastAvatar(payload: payload, kind: kind),
                  const SizedBox(width: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(short,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            sans(12.5, weight: W.label, color: AppColors.fg1)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12.5, color: AppColors.fg2)),
                  ),
                  const SizedBox(width: 10),
                  Text(ago, style: sans(11.5, color: AppColors.fg4)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The name before any " | context" suffix the daemon appends.
String notificationShortName(String title) {
  final i = title.indexOf(' | ');
  return (i > 0 ? title.substring(0, i) : title).trim();
}

/// The context after " | ", if any.
String notificationContext(String title) {
  final i = title.indexOf(' | ');
  return i > 0 ? title.substring(i + 3).trim() : '';
}

/// Soft lift for desktop toasts: one wide ambient shadow, one contact shadow.
const toastShadow = [
  BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 10)),
  BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
];

/// 22 agent avatar with a 14 state badge: amber for needs-you, a check or
/// cross for done and failed, none for plain messages.
class ToastAvatar extends StatelessWidget {
  const ToastAvatar({super.key, required this.payload, required this.kind});
  final Map<String, dynamic> payload;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final needs = kind == 'waiting';
    final failed = const {'error', 'failed'}.contains(kind);
    final done =
        const {'done', 'completed'}.contains(kind) || kind.contains('merge');
    final glyph = failed
        ? 'x'
        : done
            ? informationGlyph(payload)
            : null;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 22,
          height: 22,
          decoration:
              BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: AgentMochi('${payload['agent_id'] ?? 'snippet'}', size: 22),
        ),
        if (needs || glyph != null)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: needs ? AppColors.run : AppColors.surface3,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface2, width: 2),
              ),
              child: glyph == null
                  ? null
                  : Center(
                      child: AppIcon(glyph, size: 7, color: AppColors.fg1)),
            ),
          ),
      ]),
    );
  }
}
