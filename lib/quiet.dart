import 'package:flutter/material.dart';

import 'tap_detector.dart';
import 'theme.dart';
import 'widgets.dart';

// Quiet design language: shared pieces. Surfaces separate by tone, hairlines
// only where structure needs them, amber only for "needs you" (with the hand
// icon), and nothing moves at rest.

/// The one signal colour: something is waiting on the user.
Color get quietAmber => AppColors.run;

/// Section label: 13 / 500 in the secondary tone.
class QuietSectionLabel extends StatelessWidget {
  const QuietSectionLabel(this.label, {super.key, this.count, this.trailing});
  final String label;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s20, S.s16, S.s8),
        child: Row(children: [
          Text(count == null ? label : '$label $count',
              style: sans(13, height: 18 / 13, weight: W.label, color: AppColors.fg2)),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
      );
}

/// A list row: leading mark, one-line title, quiet second line, trailing meta.
/// 52pt tall on phone so the tap target clears 48.
class QuietRow extends StatefulWidget {
  const QuietRow({
    super.key,
    required this.title,
    this.sub,
    this.leading,
    this.trailing,
    this.meta,
    this.onTap,
    this.onLongPress,
    this.titleLines = 1,
    this.selected = false,
    this.disabled = false,
  });

  /// Two surface steps up and weight 500.
  final bool selected;

  /// fg4 text and no target.
  final bool disabled;
  final int titleLines;
  final String title;
  final String? sub;
  final Widget? leading;
  final Widget? trailing;
  final String? meta;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<QuietRow> createState() => _QuietRowState();
}

class _QuietRowState extends State<QuietRow> {
  bool _hover = false, _pressed = false;

  String get title => widget.title;
  String? get sub => widget.sub;
  Widget? get leading => widget.leading;
  Widget? get trailing => widget.trailing;
  String? get meta => widget.meta;
  int get titleLines => widget.titleLines;
  VoidCallback? get onTap => widget.disabled ? null : widget.onTap;
  VoidCallback? get onLongPress => widget.disabled ? null : widget.onLongPress;

  @override
  Widget build(BuildContext context) {
    final fg = widget.disabled ? AppColors.fg4 : AppColors.fg1;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: quietRowHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s8),
        child: Row(children: [
          if (leading != null) ...[leading!, SizedBox(width: S.s12)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: titleLines,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kQuietRowSize,
                        height: 20 / kQuietRowSize,
                        weight: widget.selected ? FontWeight.w500 : null,
                        color: fg)),
                if (sub != null && sub!.isNotEmpty)
                  Text(sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, height: 18 / 13, color: AppColors.fg3)),
              ],
            ),
          ),
          if (meta != null) ...[
            SizedBox(width: S.s8),
            Text(meta!,
                style: sans(12, height: 16 / 12, color: AppColors.fg3)),
          ],
          if (trailing != null) ...[SizedBox(width: S.s8), trailing!],
        ]),
      ),
    );
    // One surface step on hover, two on press or selection.
    final fill = widget.selected || _pressed
        ? AppColors.surface3
        : _hover
            ? AppColors.surface2
            : Colors.transparent;
    final body = AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: EdgeInsets.symmetric(horizontal: S.s4),
        decoration: BoxDecoration(
            color: fill, borderRadius: BorderRadius.circular(14)),
        child: row);
    if (onTap == null && onLongPress == null) return body;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: onTap,
          onLongPress: onLongPress,
          child: body),
    );
  }
}

const double kQuietRowSize = 15;
double get quietRowHeight => kMobileRowHeight;
const double kMobileRowHeight = 52;

/// Amber hand: the only mark that means "this needs you".
class QuietHand extends StatelessWidget {
  const QuietHand({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) =>
      AppIcon('hand', size: size, color: quietAmber, filled: true);
}

/// A failure the app recovered from: one muted collapsed line. Tap shows the
/// detail. Never red, never a card.
class QuietRecoveredLine extends StatefulWidget {
  const QuietRecoveredLine({super.key, required this.summary, this.detail});
  final String summary;
  final String? detail;

  @override
  State<QuietRecoveredLine> createState() => _QuietRecoveredLineState();
}

class _QuietRecoveredLineState extends State<QuietRecoveredLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail?.trim() ?? '';
    final expandable = detail.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: expandable ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: S.s6),
            child: Row(children: [
              Expanded(
                child: Text(widget.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, height: 18 / 13, color: AppColors.fg3)),
              ),
              if (expandable)
                AppIcon(_open ? 'chevron-down' : 'chevron-right',
                    size: 14, color: AppColors.fg4),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: EdgeInsets.only(bottom: S.s6),
            child: SelectableText(detail,
                style: codeMono(12, height: 18 / 12, color: AppColors.fg3)),
          ),
      ],
    );
  }
}

/// A failure that cannot recover on its own: the amber hand, what happened in
/// one sentence, and the one action that gets it going again.
class QuietNeedsYou extends StatelessWidget {
  const QuietNeedsYou(
      {super.key,
      required this.title,
      this.detail,
      this.action,
      this.onAction,
      this.secondary,
      this.onSecondary});
  final String? secondary;
  final VoidCallback? onSecondary;
  final String title;
  final String? detail;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(S.s12),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(14)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: EdgeInsets.only(top: S.s2), child: const QuietHand()),
          SizedBox(width: S.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: sans(15, height: 20 / 15, weight: W.label, color: AppColors.fg1)),
                if (detail != null && detail!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: S.s2),
                    child: Text(detail!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, height: 18 / 13, color: AppColors.fg3)),
                  ),
                if (action != null)
                  Padding(
                    padding: EdgeInsets.only(top: S.s12),
                    child: Row(children: [
                      Btn(action!,
                          small: true,
                          variant: BtnVariant.secondary,
                          onTap: onAction),
                      if (secondary != null) ...[
                        SizedBox(width: S.s8),
                        Btn(secondary!,
                            small: true,
                            variant: BtnVariant.ghost,
                            onTap: onSecondary),
                      ],
                    ]),
                  ),
              ],
            ),
          ),
        ]),
      );
}

/// Cannot reach the machine: what is on screen is the last copy, replies queue.
/// Amber hand, not red; one Retry.
class QuietOfflineBanner extends StatelessWidget {
  const QuietOfflineBanner(
      {super.key, required this.machine, this.since, this.onRetry});
  final String machine;
  final String? since;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s8),
        padding: EdgeInsets.fromLTRB(S.s12, S.s12, S.s12, S.s12),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(14)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: EdgeInsets.only(top: S.s2), child: const QuietHand()),
          SizedBox(width: S.s12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Can't reach $machine",
                      style: sans(15,
                          height: 20 / 15,
                          weight: W.label,
                          color: AppColors.fg1)),
                  Padding(
                    padding: EdgeInsets.only(top: S.s2),
                    child: Text(
                        '${since == null ? 'Showing what you saw earlier' : 'Showing what you saw at $since'}. Replies send when it is back.',
                        style: sans(13, height: 18 / 13, color: AppColors.fg3)),
                  ),
                ]),
          ),
          if (onRetry != null) ...[
            SizedBox(width: S.s8),
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: S.s2),
                child: Text('Retry',
                    style: sans(14,
                        weight: W.label, color: AppColors.fg1)),
              ),
            ),
          ],
        ]),
      );
}

/// The four places, in order. The same four sit in the desktop sidebar.
enum QuietPlace {
  home('Home', 'home'),
  sessions('Sessions', 'layers'),
  tasks('Tasks', 'list-checks'),
  agents('Agents', 'users');

  const QuietPlace(this.label, this.icon);
  final String label;
  final String icon;
}

/// Floating phone tab bar: four places on a raised pill, New set apart on its
/// own primary circle. 48pt targets; the selected place takes fill weight.
class QuietTabBar extends StatelessWidget {
  const QuietTabBar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNew,
    this.onNewLong,
    this.attention = const {},
    this.places = QuietPlace.values,
  });

  /// Which places the bar shows, in order. The phone leads with Agents.
  final List<QuietPlace> places;
  final QuietPlace? selected;
  final ValueChanged<QuietPlace> onSelect;
  final VoidCallback onNew;

  /// Long-press on New skips the sheet and starts a session.
  final VoidCallback? onNewLong;

  /// Places with something waiting: a quiet amber dot on the icon.
  final Set<QuietPlace> attention;

  /// 58 at normal text, growing with text size so labels never overflow.
  static double _barHeight(BuildContext context) {
    final scale = (MediaQuery.textScalerOf(context).scale(11) / 11).clamp(1.0, 2.0);
    return 58 + 14 * (scale - 1);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s8),
        child: Row(children: [
          Expanded(
            child: Container(
              height: _barHeight(context),
              padding: EdgeInsets.symmetric(horizontal: S.s4),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(29),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                for (final p in places)
                  Expanded(
                    child: _Tab(
                      place: p,
                      selected: p == selected,
                      dot: attention.contains(p),
                      onTap: () => onSelect(p),
                    ),
                  ),
              ]),
            ),
          ),
          SizedBox(width: S.s8),
          Semantics(
            button: true,
            label: 'New: session, agent or group',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onNew,
              onLongPress: onNewLong,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.accentFill,
                  shape: BoxShape.circle,
                ),
                child: Center(
                    child: AppIcon('edit', size: 22, color: AppColors.accentFg)),
              ),
            ),
          ),
        ]),
      );
}

class _Tab extends StatelessWidget {
  const _Tab(
      {required this.place,
      required this.selected,
      required this.dot,
      required this.onTap});
  final QuietPlace place;
  final bool selected, dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.fg1 : AppColors.fg3;
    return Semantics(
      button: true,
      selected: selected,
      label: place.label,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              AppIcon(place.icon, size: 22, color: color, filled: selected),
              if (dot)
                Positioned(
                  right: -2,
                  top: -1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: quietAmber, shape: BoxShape.circle),
                  ),
                ),
            ]),
            SizedBox(height: S.s2),
            Text(place.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(11,
                    height: 14 / 11,
                    weight: selected ? W.label : W.body,
                    color: color)),
          ],
        ),
        ),
      ),
    );
  }
}
