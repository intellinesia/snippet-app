import 'package:flutter/material.dart';

import 'attention_state.dart';
import 'theme.dart';
import 'top_zone.dart';
import 'widgets.dart' show AppIcon;

/// NT-03: the full-bleed amber attention bar under the page bar. Registers
/// its bottom edge in [TopZone] so banners and toasts sit 8 below it.
class PhoneAttentionBar extends StatefulWidget {
  const PhoneAttentionBar({super.key, required this.count, this.onReview});

  final int count;
  final VoidCallback? onReview;

  @override
  State<PhoneAttentionBar> createState() => _PhoneAttentionBarState();
}

class _PhoneAttentionBarState extends State<PhoneAttentionBar> {
  static const _key = 'attention-bar';

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => TopZone.unregister(_key));
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final h = box.size.height;
    if (h <= 0.5) {
      TopZone.unregister(_key);
    } else {
      TopZone.register(_key, TopZone.pageBarBottom(context) + h);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final count = widget.count;
    final onReview = widget.onReview;
    final calm = reduceMotion(context);
    final amber = AppColors.run;
    final label = count == 1 ? '1 needs you' : '$count need you';
    final bar = count <= 0
        ? const SizedBox(key: ValueKey('none'), width: double.infinity)
        : Semantics(
            key: const ValueKey('bar'),
            container: true,
            button: true,
            label: '$label, Review',
            onTap: onReview,
            excludeSemantics: true,
            child: Material(
              color: AppColors.attentionTint,
              child: InkWell(
                onTap: onReview,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(children: [
                    const SizedBox(width: 22),
                    AppIcon('alert-circle', size: 16, color: amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(14, weight: W.label, color: amber)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        child: Center(
                          widthFactor: 1,
                          child: Text('Review',
                              style: sans(13,
                                  weight: W.label, color: AppColors.fg1)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: AnimatedSize(
          duration: Duration(milliseconds: calm ? 1 : 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: bar,
        ),
      ),
    );
  }
}

/// Mounts [PhoneAttentionBar] from the shared count, hidden on composer
/// pages (see [AttentionBarHidden]).
class PhoneAttentionLayer extends StatelessWidget {
  const PhoneAttentionLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TopZone.attentionHolds,
      builder: (_, holds, __) => ValueListenableBuilder<int>(
        valueListenable: phoneNeedsYou,
        builder: (_, n, __) => PhoneAttentionBar(
          count: holds > 0 ? 0 : n,
          onReview: () => onReviewNeedsYou?.call(),
        ),
      ),
    );
  }
}
