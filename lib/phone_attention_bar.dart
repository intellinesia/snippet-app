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
  final _key = Object();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    final key = _key;
    WidgetsBinding.instance.addPostFrameCallback((_) => TopZone.unregister(key));
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final active = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final h = box.size.height;
    if (!active || h <= 0.5) {
      TopZone.unregister(_key);
    } else {
      final top = box.localToGlobal(Offset.zero).dy;
      TopZone.register(_key, top + h);
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
                        key: const ValueKey('attention-review-target'),
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        child: Align(
                          alignment: Alignment.centerRight,
                          widthFactor: 1,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text('Review',
                                maxLines: 1,
                                softWrap: false,
                                style: sans(13,
                                    weight: W.label, color: AppColors.fg1)),
                          ),
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
