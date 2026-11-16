import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Open state and current page of the phone composer tray. Also the
/// [TapRegion] group shared by the tray and the "+" that toggles it.
class ComposerTrayController extends ChangeNotifier {
  static const menu = 'menu';

  bool _open = false;
  String _view = menu;

  bool get open => _open;
  String get view => _view;

  void toggle() => _open ? close() : _show(menu);

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  /// Swaps the tray's content in place, opening it if needed.
  void show(String view) => _show(view);

  /// Back steps out of a sub-page first, then closes.
  void back() => _view != menu ? _show(menu) : close();

  void _show(String view) {
    if (_open && _view == view) return;
    _open = true;
    _view = view;
    notifyListeners();
  }
}

/// A surface that opens in place above the composer, growing up out of the
/// "+" at its bottom-left, and swaps its content with a smooth height change.
class ComposerTray extends StatefulWidget {
  const ComposerTray(
      {super.key, required this.controller, required this.child});

  final ComposerTrayController controller;

  /// The current page; keyed by [ComposerTrayController.view] for the swap.
  final Widget child;

  @override
  State<ComposerTray> createState() => _ComposerTrayState();
}

class _ComposerTrayState extends State<ComposerTray>
    with SingleTickerProviderStateMixin {
  static const _in = Duration(milliseconds: 220);
  static const _out = Duration(milliseconds: 160);

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: _in,
    reverseDuration: _out,
    value: widget.controller.open ? 1 : 0,
  )..addStatusListener((_) {
      if (mounted) setState(() {});
    });

  late final CurvedAnimation _curve = CurvedAnimation(
      parent: _anim, curve: Motion.enter, reverseCurve: Motion.exit);

  // Content kept while the tray folds away, so it does not swap mid-close.
  Widget? _shown;
  String? _shownView;

  @override
  void didUpdateWidget(ComposerTray old) {
    super.didUpdateWidget(old);
    if (widget.controller.open) {
      if (_anim.status != AnimationStatus.forward && _anim.value < 1) {
        _anim.forward();
      }
    } else if (_anim.status != AnimationStatus.reverse && _anim.value > 0) {
      _anim.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final calm = reduceMotion(context);
    _anim.duration = calm ? Duration.zero : _in;
    _anim.reverseDuration = calm ? Duration.zero : _out;
    if (c.open) {
      _shown = widget.child;
      _shownView = c.view;
    }
    final shown = _shown;
    final body = (_anim.isDismissed && !c.open) || shown == null
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.only(bottom: S.s8),
            child: TapRegion(
              groupId: c,
              onTapOutside: (_) => c.close(),
              child: Container(
                padding: EdgeInsets.all(S.s6),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border2),
                ),
                child: AnimatedSize(
                  duration: calm ? Duration.zero : _in,
                  curve: Motion.enter,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSwitcher(
                    duration: calm ? Duration.zero : Motion.fast,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    child:
                        KeyedSubtree(key: ValueKey(_shownView), child: shown),
                  ),
                ),
              ),
            ),
          );
    return PopScope(
      canPop: !c.open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: FadeTransition(
        opacity: _curve,
        child: calm
            ? body
            : SizeTransition(
                sizeFactor: _curve,
                alignment: Alignment.bottomCenter,
                child: ScaleTransition(
                  alignment: Alignment.bottomLeft,
                  scale: Tween<double>(begin: 0.9, end: 1).animate(_curve),
                  child: body,
                ),
              ),
      ),
    );
  }
}

/// One tray action: icon, label and an optional right-aligned detail.
class ComposerTrayRow extends StatelessWidget {
  const ComposerTrayRow(
      {super.key,
      required this.icon,
      required this.label,
      this.detail,
      required this.onTap});

  final String icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: () {
            tapHaptic();
            onTap();
          },
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: S.of(10)),
            child: Row(children: [
              AppIcon(icon, size: 18, color: AppColors.fg3),
              SizedBox(width: S.s12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, color: AppColors.fg2)),
              ),
              if (detail != null) ...[
                SizedBox(width: S.s8),
                Text(detail!, style: sans(12, color: AppColors.fg4)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A sub-page's back and title row, with an optional line beneath.
class ComposerTrayHeader extends StatelessWidget {
  const ComposerTrayHeader(
      {super.key, required this.title, this.subtitle, required this.onBack});

  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Semantics(
            button: true,
            label: 'Back',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(R.md),
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(R.md),
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                      child: AppIcon('chevron-left',
                          size: 18, color: AppColors.fg3)),
                ),
              ),
            ),
          ),
          SizedBox(width: S.s4),
          Expanded(
            child: Text(title,
                style: sans(15, weight: W.label, color: AppColors.fg1)),
          ),
        ]),
        if (subtitle != null)
          Padding(
            padding: EdgeInsets.fromLTRB(S.of(10), 0, S.of(10), S.s8),
            child: Text(subtitle!, style: sans(13, color: AppColors.fg3)),
          ),
      ],
    );
  }
}
