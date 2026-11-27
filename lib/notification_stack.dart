import 'package:flutter/material.dart';

import 'notification_banner.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart' show HoverSurface;

bool needsYou(Map<String, dynamic> p) =>
    '${p['kind'] ?? ''}'.split('.').last == 'waiting';

/// Builds one card; the stack wraps it with spacing and arrival motion.
typedef StackCardBuilder = Widget Function(Map<String, dynamic> payload);

/// NT-01: plain stacked cards, newest first, at most three, with a footer
/// when more are waiting. No pill, no ghost cards, no shadow.
class NotificationStack extends StatelessWidget {
  const NotificationStack({
    super.key,
    required this.items,
    required this.onClearAll,
    required this.onShowAll,
    required this.cardBuilder,
  });

  /// Newest first.
  final List<Map<String, dynamic>> items;
  final VoidCallback onClearAll;
  final VoidCallback onShowAll;
  final StackCardBuilder cardBuilder;

  static const maxVisible = 3;
  static const gap = 8.0;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = items.take(maxVisible).toList();
    final hasNeeds = shown.any(needsYou);
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: hasNeeds ? 'Notifications, needs you' : 'Notifications',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, p) in shown.indexed) ...[
              if (i > 0) SizedBox(height: kMobile ? gap : 6),
              BannerArrival(key: ObjectKey(p), child: cardBuilder(p)),
            ],
            if (items.length > maxVisible && !kMobile) ...[
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _FooterAction('+${items.length - maxVisible}', onShowAll),
                Text('\u00b7', style: sans(11.5, color: AppColors.fg4)),
                _FooterAction('Clear', onClearAll),
              ]),
            ] else if (items.length > maxVisible) ...[
              const SizedBox(height: gap),
              Row(children: [
                _FooterAction('Show all ${items.length}', onShowAll),
                const Spacer(),
                _FooterAction('Dismiss all', onClearAll),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = !kMobile;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: HoverSurface(
        onTap: onTap,
        radius: 6,
        hoverColor: AppColors.surface3,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: compact ? 24 : 48, minWidth: compact ? 24 : 48),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 0),
            child: Center(
              widthFactor: 1,
              child: Text(label,
                  style: compact
                      ? sans(11.5, color: AppColors.fg4)
                      : sans(13, weight: W.label, color: AppColors.fg2)),
            ),
          ),
        ),
      ),
    );
  }
}
