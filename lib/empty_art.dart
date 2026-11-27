import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// Which empty-state drawing to show.
enum EmptyArtKind { overview, clean, tasks, search }

/// Snippet's own empty-state drawings: the headphone mascot in flat theme
/// greys, one scene per surface.
class EmptyArt extends StatelessWidget {
  const EmptyArt(this.kind, {super.key, this.width = 96});

  final EmptyArtKind kind;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bright = AppColors.fg4;
    final dim = Color.lerp(AppColors.fg4, AppColors.panelBg, 0.55)!;
    // Eyes read darker than the body: the panel in dark themes, the line ink in light.
    final eyes =
        AppColors.panelBg.computeLuminance() > 0.5 ? bright : AppColors.panelBg;
    final svg = _art[kind]!
        .replaceAll('{b}', _hex(bright))
        .replaceAll('{d}', _hex(dim))
        .replaceAll('{e}', _hex(eyes));
    return ExcludeSemantics(
      child: SvgPicture.string(svg,
          key: ValueKey(svg.hashCode), width: width, height: width * 80 / 96),
    );
  }
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

const _art = <EmptyArtKind, String>{
  EmptyArtKind.overview:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 80"> <rect x="50" y="22" width="32" height="26" rx="3.5" fill="{b}"/> <path d="M50 29 h32" stroke="{d}" stroke-width="1.4"/> <circle cx="54" cy="25.5" r="1.1" fill="{d}"/><circle cx="57.5" cy="25.5" r="1.1" fill="{d}"/> <path d="M55 35 l3.5 3 l-3.5 3" fill="none" stroke="{d}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/> <path d="M61 41 h7" stroke="{d}" stroke-width="1.8" stroke-linecap="round"/> <path d="M66 48 v16 M59 64 h14" stroke="{b}" stroke-width="2.2" stroke-linecap="round"/> <circle cx="34" cy="49" r="15" fill="{d}"/> <path d="M17.5 48 A16.5 16.5 0 0 1 50.5 48" fill="none" stroke="{b}" stroke-width="2.2" stroke-linecap="round"/> <rect x="15" y="43" width="6.5" height="11" rx="2.6" fill="{b}"/> <rect x="46.5" y="43" width="6.5" height="11" rx="2.6" fill="{b}"/> <ellipse cx="32.0" cy="47.8" rx="1.9500000000000002" ry="3.5999999999999996" fill="{e}"/> <ellipse cx="41.0" cy="47.8" rx="1.9500000000000002" ry="3.5999999999999996" fill="{e}"/> <path d="M14 64 h70" stroke="{d}" stroke-width="2" stroke-linecap="round"/> <path d="M22 16 l1 2.4 l2.4 1 l-2.4 1 l-1 2.4 l-1 -2.4 l-2.4 -1 l2.4 -1 z" fill="{b}"/></svg>',
  EmptyArtKind.clean:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 80"> <circle cx="36" cy="49" r="15" fill="{d}"/> <path d="M19.5 48 A16.5 16.5 0 0 1 52.5 48" fill="none" stroke="{b}" stroke-width="2.2" stroke-linecap="round"/> <rect x="17" y="43" width="6.5" height="11" rx="2.6" fill="{b}"/> <rect x="48.5" y="43" width="6.5" height="11" rx="2.6" fill="{b}"/> <ellipse cx="33.5" cy="47.8" rx="1.9500000000000002" ry="3.5999999999999996" fill="{e}"/> <ellipse cx="42.5" cy="47.8" rx="1.9500000000000002" ry="3.5999999999999996" fill="{e}"/> <path d="M60 51 h20 l-2.5 13 h-15 z" fill="{b}"/> <rect x="58" y="48" width="24" height="5" rx="1.5" fill="{b}"/> <path d="M70 49 C70 40 70 34 70 28" stroke="{b}" stroke-width="2" stroke-linecap="round" fill="none"/> <path d="M70 36 C62 36 58 30 58 24 C65 24 70 29 70 36 z" fill="{b}"/> <path d="M70 31 C76 31 81 26 81 19 C74 19 70 24 70 31 z" fill="{b}"/> <path d="M14 64 h70" stroke="{d}" stroke-width="2" stroke-linecap="round"/> <path d="M22 14 l1 2.4 l2.4 1 l-2.4 1 l-1 2.4 l-1 -2.4 l-2.4 -1 l2.4 -1 z" fill="{b}"/></svg>',
  EmptyArtKind.tasks:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 80"> <rect x="50" y="18" width="28" height="38" rx="3" fill="{b}"/> <rect x="58" y="15" width="12" height="6" rx="2" fill="{d}"/> <path d="M55 29 l2 2 l3.5 -4" fill="none" stroke="{d}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/> <path d="M64 29 h9" stroke="{d}" stroke-width="2" stroke-linecap="round"/> <path d="M55 38 l2 2 l3.5 -4" fill="none" stroke="{d}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/> <path d="M64 38 h9" stroke="{d}" stroke-width="2" stroke-linecap="round"/> <rect x="55" y="45" width="5" height="5" rx="1.2" fill="none" stroke="{d}" stroke-width="1.6"/> <path d="M64 47.5 h7" stroke="{d}" stroke-width="2" stroke-linecap="round"/> <circle cx="32" cy="49" r="15" fill="{d}"/> <path d="M15.5 48 A16.5 16.5 0 0 1 48.5 48" fill="none" stroke="{b}" stroke-width="2.2" stroke-linecap="round"/> <rect x="13" y="43" width="6.5" height="11" rx="2.6" fill="{b}"/> <rect x="44.5" y="43" width="6.5" height="11" rx="2.6" fill="{b}"/> <ellipse cx="30.0" cy="47.8" rx="1.9500000000000002" ry="3.5999999999999996" fill="{e}"/> <ellipse cx="39.0" cy="47.8" rx="1.9500000000000002" ry="3.5999999999999996" fill="{e}"/> <path d="M14 64 h70" stroke="{d}" stroke-width="2" stroke-linecap="round"/></svg>',
  EmptyArtKind.search:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 80"> <circle cx="36" cy="49" r="15" fill="{d}"/> <path d="M19.5 48 A16.5 16.5 0 0 1 52.5 48" fill="none" stroke="{b}" stroke-width="2.2" stroke-linecap="round"/> <rect x="17" y="43" width="6.5" height="11" rx="2.6" fill="{b}"/> <rect x="48.5" y="43" width="6.5" height="11" rx="2.6" fill="{b}"/> <ellipse cx="33.5" cy="47.8" rx="1.9500000000000002" ry="3.5999999999999996" fill="{e}"/> <ellipse cx="42.5" cy="47.8" rx="1.9500000000000002" ry="3.5999999999999996" fill="{e}"/> <circle cx="70" cy="30" r="9" fill="none" stroke="{b}" stroke-width="3"/> <path d="M64 37 l-6 7" stroke="{b}" stroke-width="3.5" stroke-linecap="round"/> <path d="M66.5 26.5 a5 5 0 0 1 4 -1.5" stroke="{b}" stroke-width="1.6" stroke-linecap="round" fill="none"/> <path d="M14 64 h70" stroke="{d}" stroke-width="2" stroke-linecap="round"/></svg>',
};
