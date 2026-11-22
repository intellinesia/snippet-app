import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets.dart';

const Color askAmber = Color(0xFFF8BB54);
const Color askCobalt = Color(0xFF7C9CFF);
const Color askMint = Color(0xFF5EE0B0);

/// Tone for a tinted pill: a grey cream character keeps its warmth.
Color pillTone(Color agent) {
  final hsl = HSLColor.fromColor(agent);
  return hsl.saturation < 0.2 && hsl.lightness > 0.6
      ? const Color(0xFFD9C9A0)
      : agent;
}

/// Short age for a unix-seconds time: 2m, 3h, 5d.
String homeAge(int unixSec, {DateTime? now}) {
  final d = (now ?? DateTime.now())
      .difference(DateTime.fromMillisecondsSinceEpoch(unixSec * 1000));
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// A tinted pill: tone at 0.2 alpha, text in the tone mixed towards white.
class TonePill extends StatelessWidget {
  const TonePill(this.label,
      {super.key, required this.tone, this.icon, this.height = 24});

  final String label;
  final Color tone;
  final String? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ink = Color.lerp(tone, Colors.white, 0.45)!;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: S.of(10)),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          AppIcon(icon!, size: 14, color: ink),
          SizedBox(width: S.s6),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, weight: W.label, color: ink)),
        ),
      ]),
    );
  }
}

/// Section label: name, a mono count and an optional right-aligned note.
class HomeLabel extends StatelessWidget {
  const HomeLabel(this.label,
      {super.key, this.count, this.tone, this.trailing, this.top = 0});

  final String label;
  final int? count;
  final Color? tone;
  final String? trailing;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s4, top, S.s4, S.s6),
        child: Row(children: [
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: W.label, color: tone ?? AppColors.fg2)),
          ),
          if (count != null) ...[
            SizedBox(width: S.s6),
            Text('$count', style: mono(12, color: AppColors.fg3)),
          ],
          if (trailing != null) ...[
            const Spacer(),
            Text(trailing!, style: mono(12, color: AppColors.fg3)),
          ],
        ]),
      );
}

/// Group card: surface1 at 0.84, radius 20, no outline; keeps row ink inside.
class HomeCard extends StatelessWidget {
  const HomeCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface1.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(R.of(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

/// 0.33 pt divider inset to line up with the row text.
class HomeDivider extends StatelessWidget {
  const HomeDivider({super.key, this.inset = 66});

  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: inset),
        child: Container(
            height: 0.33, color: AppColors.fg1.withValues(alpha: 0.06)),
      );
}

/// Interleaves dividers between rows.
List<Widget> withDividers(List<Widget> rows, {double inset = 66}) => [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) HomeDivider(inset: inset),
        rows[i],
      ],
    ];

/// A fold row ("Asleep 4", "Settled 10") that expands its card in place.
class FoldRow extends StatelessWidget {
  const FoldRow({
    super.key,
    required this.label,
    required this.count,
    required this.open,
    required this.onTap,
    this.lead,
  });

  final String label;
  final int count;
  final bool open;
  final VoidCallback onTap;
  final Widget? lead;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        expanded: open,
        label: '$label, $count',
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.of(14)),
                child: Row(children: [
                  if (lead != null) ...[lead!, SizedBox(width: S.s12)],
                  Text(label, style: sans(15, color: AppColors.fg2)),
                  SizedBox(width: S.s8),
                  Text('$count', style: mono(12, color: AppColors.fg3)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: reduceMotion(context) ? Duration.zero : Motion.base,
                    curve: Curves.easeOutCubic,
                    child: AppIcon('chevron-right',
                        size: 14, color: AppColors.fg3),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// A 44 pt hit box around a visual that may be smaller.
class Hit44 extends StatelessWidget {
  const Hit44({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.width = 44,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    tapHaptic();
                    onTap!();
                  },
            child: SizedBox(
                width: width, height: 44, child: Center(child: child)),
          ),
        ),
      );
}
