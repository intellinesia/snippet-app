import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../glass.dart';
import '../models.dart';
import '../mochi.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_chrome.dart';
import 'session_list_row.dart';

/// Phone home top bar: the Sessions / Agents switch with search and settings.
/// Search swaps the row for a field until it is cleared and closed.
class MobileHomeTopBar extends StatefulWidget {
  const MobileHomeTopBar({
    super.key,
    required this.agents,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSessions,
    required this.onAgents,
    this.onSettings,
  });

  final bool agents;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSessions;
  final VoidCallback onAgents;
  final VoidCallback? onSettings;

  @override
  State<MobileHomeTopBar> createState() => _MobileHomeTopBarState();
}

class _MobileHomeTopBarState extends State<MobileHomeTopBar> {
  late bool _searching = widget.controller.text.isNotEmpty;

  void _open() {
    HapticFeedback.selectionClick();
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  void _close() {
    widget.controller.clear();
    widget.onChanged('');
    widget.focusNode.unfocus();
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 6, M.gutter, 10),
        child: SizedBox(
          height: 44,
          child: AnimatedSwitcher(
            duration: Motion.base,
            child: _searching
                ? Row(key: const ValueKey('search'), children: [
                    Expanded(child: _field()),
                    const SizedBox(width: 8),
                    RoundBtn(
                        icon: 'x', tooltip: 'Close search', onTap: _close),
                  ])
                : Row(key: const ValueKey('tabs'), children: [
                    Expanded(child: _segment()),
                    const SizedBox(width: 8),
                    RoundBtn(icon: 'search', tooltip: 'Search', onTap: _open),
                    if (widget.onSettings != null) ...[
                      const SizedBox(width: 8),
                      RoundBtn(
                          icon: 'settings',
                          tooltip: 'Settings',
                          onTap: widget.onSettings),
                    ],
                  ]),
          ),
        ),
      );

  Widget _segment() => Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.tint2,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Row(children: [
          _seg('Sessions', !widget.agents, widget.onSessions),
          _seg('Agents', widget.agents, widget.onAgents),
        ]),
      );

  Widget _seg(String label, bool on, VoidCallback onTap) => Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: on
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            child: AnimatedContainer(
              duration: Motion.fast,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.surface3 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Text(label,
                  style: sans(14,
                      weight: on ? W.label : W.body,
                      color: on ? AppColors.fg1 : AppColors.fg3)),
            ),
          ),
        ),
      );

  Widget _field() => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.tint2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          AppIcon('search', size: 16, color: AppColors.fg4),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              style: sans(15, color: AppColors.fg1),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.agents ? 'Search agents' : 'Search sessions',
                hintStyle: sans(15, color: AppColors.fg4),
              ),
            ),
          ),
        ]),
      );
}

/// The phone home's bottom bar: Mission Control as an input, with its badge,
/// a live ring while voice is on, and the call button.
class MissionControlDock extends StatelessWidget {
  const MissionControlDock({
    super.key,
    required this.onOpen,
    this.onCall,
    this.live = false,
    this.badgeCount = 0,
  });

  final VoidCallback onOpen;
  final VoidCallback? onCall;
  final bool live;
  final int badgeCount;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Ask Mission Control',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Glass(
            radius: BorderRadius.circular(28),
            child: SizedBox(
              height: 56,
              child: Row(children: [
                const SizedBox(width: 6),
                LiveRing(
                  live: live,
                  child: RoundBtn(
                    tooltip: live ? 'Mission Control, voice on' : 'Mission Control',
                    size: 44,
                    bare: true,
                    badgeCount: badgeCount,
                    onTap: onOpen,
                    child: MochiIcon(
                        color: live ? AppColors.ok : AppColors.fg1, size: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Ask Mission Control',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15, color: AppColors.fg3)),
                ),
                if (onCall != null)
                  RoundBtn(
                    tooltip: live ? 'Voice call' : 'Start voice',
                    size: 44,
                    bare: true,
                    onTap: onCall,
                    child: AppIcon('phone',
                        size: 20, color: live ? AppColors.ok : AppColors.fg2),
                  ),
                const SizedBox(width: 6),
              ]),
            ),
          ),
        ),
      );
}

/// Section label over a group: an optional icon, the name and a count.
class MobileSectionLabel extends StatelessWidget {
  const MobileSectionLabel(this.label,
      {super.key, this.count, this.icon, this.tone, this.top = 18});

  final String label;
  final int? count;
  final String? icon;
  final Color? tone;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = tone ?? AppColors.fg3;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, top, 4, 8),
      child: Row(children: [
        if (icon != null) ...[
          AppIcon(icon!, size: 14, color: c),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, weight: W.label, color: c)),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('$count', style: mono(12, color: AppColors.fg4)),
        ],
      ]),
    );
  }
}

/// Rounded group surface; owns a Material so row ink stays inside the corners.
class MobileGroupCard extends StatelessWidget {
  const MobileGroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
}

/// A running or waiting session, shown large at the top of the phone list.
class LiveSessionCard extends StatelessWidget {
  const LiveSessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.leading,
  });

  final SessionInfo session;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? leading;

  static String _since(int? t) {
    if (t == null || t <= 0) return '';
    final secs = t > 100000000000 ? t ~/ 1000 : t;
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(secs * 1000));
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final needsYou = sessionNeedsYou(s);
    final tone = needsYou ? AppColors.run : AppColors.accent;
    final since = needsYou ? relativeTime(s.lastActive) : _since(s.runningSince);
    final label = needsYou ? sessionAttentionState(s).label : 'Working';
    final note = needsYou ? _attentionText(s) : null;
    final diff = sessionDiff(s);
    final branch = s.branch?.trim() ?? '';
    final title = s.title.trim().isEmpty ? '(untitled)' : s.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '$label. $title',
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onLongPress!();
                  },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    if (needsYou)
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: tone, shape: BoxShape.circle),
                      )
                    else
                      const WorkingDots(),
                    const SizedBox(width: 8),
                    Text(since.isEmpty ? label : '$label · $since',
                        style: sans(12, weight: W.label, color: tone)),
                    const Spacer(),
                    if (leading != null)
                      SizedBox.square(
                          dimension: 18, child: Center(child: leading)),
                  ]),
                  const SizedBox(height: 6),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(16,
                          weight: W.label, height: 1.35, color: AppColors.fg1)),
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Text(note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, height: 1.4, color: AppColors.fg2)),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    _Tag(projectLabel(s)),
                    if (branch.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      AppIcon('git-branch', size: 11, color: AppColors.fg4),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(branch,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.meta()),
                      ),
                    ] else
                      const Spacer(),
                    if (diff != null) ...[
                      const SizedBox(width: 8),
                      if (diff.added > 0)
                        Text('+${compactCount(diff.added)}',
                            style: TS.meta(AppColors.ok)),
                      if (diff.added > 0 && diff.removed > 0)
                        const SizedBox(width: 4),
                      if (diff.removed > 0)
                        Text('-${compactCount(diff.removed)}',
                            style: TS.meta(AppColors.danger)),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _attentionText(SessionInfo s) {
    final a = s.attention;
    if (a == null) return null;
    for (final k in const ['summary', 'text', 'question', 'message']) {
      final v = a[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.tint2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(11, color: AppColors.fg3)),
      );
}

/// A breathing ring that marks a control as live, such as Mission Control
/// while ambient voice is on.
class LiveRing extends StatefulWidget {
  const LiveRing({super.key, required this.live, required this.child});

  final bool live;
  final Widget child;

  @override
  State<LiveRing> createState() => _LiveRingState();
}

class _LiveRingState extends State<LiveRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LiveRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.live && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = widget.live ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.live) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: AppColors.ok.withValues(alpha: 0.45 + 0.5 * t),
                width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.ok.withValues(alpha: 0.10 + 0.22 * t),
                blurRadius: 6 + 8 * t,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// Faint dot grid painted behind the phone home lists.
class DotField extends StatelessWidget {
  const DotField({super.key, required this.child, this.strength = 0.07});

  /// Faint enough to sit behind a chat transcript.
  const DotField.chat({super.key, required this.child}) : strength = 0.06;

  final Widget child;
  final double strength;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DotGridPainter(AppColors.fg1.withValues(alpha: strength)),
        child: RepaintBoundary(child: child),
      );
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 12.0;
    final p = Paint()..color = color;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

/// One reading for the home hero.
class HeroStat {
  const HeroStat(this.value, this.label, [this.detail]);

  final String value;
  final String label;
  final String? detail;
}

/// The home hero: one dot-matrix reading from [stats], picked at random each
/// time the home is shown again ([visit] changes or a covering chat closes).
/// A tap moves to the next reading.
class HomeHero extends StatefulWidget {
  const HomeHero({super.key, required this.stats, this.visit = 0});

  final List<HeroStat> stats;
  final int visit;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  static final _rng = Random();
  String? _label;
  bool? _shown;

  @override
  void initState() {
    super.initState();
    _shuffle();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (_shown == false && shown) _shuffle();
    _shown = shown;
  }

  @override
  void didUpdateWidget(HomeHero old) {
    super.didUpdateWidget(old);
    if (old.visit != widget.visit) _shuffle();
  }

  void _shuffle() {
    final s = widget.stats;
    _label = s.isEmpty ? null : s[_rng.nextInt(s.length)].label;
  }

  int get _index {
    final i = widget.stats.indexWhere((s) => s.label == _label);
    return i < 0 ? 0 : i;
  }

  void _advance() {
    final s = widget.stats;
    if (s.length < 2) return;
    setState(() => _label = s[(_index + 1) % s.length].label);
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    if (stats.isEmpty) return const SizedBox.shrink();
    final stat = stats[_index];
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: [stat.value, stat.label, if (stat.detail != null) stat.detail]
          .join(' '),
      button: stats.length > 1,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _advance,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: _reading(stat),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reading(HeroStat stat) => SizedBox(
        key: ValueKey(stat.label),
        height: 63,
        child: _readingRow(stat),
      );

  Widget _readingRow(HeroStat stat) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DotMatrixNumber(stat.value,
              cell: _DotMatrixPainter.columns(stat.value) > 22 ? 7 : 9),
          const SizedBox(width: 12),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(stat.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(12, color: AppColors.fg2)),
                  if (stat.detail != null)
                    Text(stat.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(12, color: AppColors.accent)),
                ],
              ),
            ),
          ),
        ],
      );
}

/// Compact hero value: 842, 16.8k, 4.2M.
String heroCompact(int n) {
  final a = n.abs();
  String f(double v, String u) =>
      '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}$u';
  if (a >= 1000000) return f(n / 1000000, 'M');
  if (a >= 1000) return f(n / 1000, 'k');
  return n.toString().padLeft(2, '0');
}

/// Text drawn as a 7-row dot matrix: digits and `%.:kM+-`.
class DotMatrixNumber extends StatelessWidget {
  const DotMatrixNumber(this.digits, {super.key, this.cell = 9, this.color});

  final String digits;
  final double cell;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(cell * _DotMatrixPainter.columns(digits), cell * 7),
        painter: _DotMatrixPainter(digits, cell, color ?? AppColors.fg1),
      );
}

class _DotMatrixPainter extends CustomPainter {
  _DotMatrixPainter(this.digits, this.cell, this.color);

  final String digits;
  final double cell;
  final Color color;

  static const _glyphs = {
    '0': ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
    '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
    '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
    '3': ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
    '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
    '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
    '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
    '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
    '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
    '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
    '%': ['11001', '11010', '00010', '00100', '01000', '01011', '10011'],
    '.': ['0', '0', '0', '0', '0', '0', '1'],
    ':': ['0', '0', '1', '0', '1', '0', '0'],
    'k': ['1000', '1000', '1001', '1010', '1100', '1010', '1001'],
    'M': ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
    '+': ['000', '000', '010', '111', '010', '000', '000'],
    '-': ['000', '000', '000', '111', '000', '000', '000'],
  };

  static int columns(String text) {
    var w = 0;
    for (final ch in text.split('')) {
      final g = _glyphs[ch];
      if (g != null) w += g[0].length + 1;
    }
    return w == 0 ? 0 : w - 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final on = Paint()..color = color;
    final off = Paint()..color = color.withValues(alpha: color.a * 0.08);
    final r = cell * 0.36;
    var x = 0;
    for (final ch in digits.split('')) {
      final g = _glyphs[ch];
      if (g == null) continue;
      final w = g[0].length;
      for (var row = 0; row < 7; row++) {
        for (var col = 0; col < w; col++) {
          final c = Offset((x + col + 0.5) * cell, (row + 0.5) * cell);
          canvas.drawCircle(c, r, g[row][col] == '1' ? on : off);
        }
      }
      x += w + 1;
    }
  }

  @override
  bool shouldRepaint(_DotMatrixPainter old) =>
      old.digits != digits || old.cell != cell || old.color != color;
}
