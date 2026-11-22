import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ink.dart';
import '../../mochi.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'home_data.dart';
import 'home_style.dart';
import 'needs_you_pager.dart' show askKindLabel, askText;

const _kAskWhite = Color(0xFFFAFAFA);
const _kAskInk = Color(0xFF0A0A0A);

final _codeTokenRe = RegExp(
  r'`([^`]+)`|(?<![A-Za-z0-9_])([A-Za-z0-9._-]+/[A-Za-z0-9._/-]+|[A-Za-z0-9]+_[A-Za-z0-9_]+)(?![A-Za-z0-9_])',
);

/// Splits ask prose into Literata regular and italic spans so branch names,
/// paths, identifiers and backticked spans read in Literata italic.
List<InlineSpan> askHeadlineSpans(String text, TextStyle base) {
  final italic = base.copyWith(fontStyle: FontStyle.italic);
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final m in _codeTokenRe.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start), style: base));
    }
    final tok = m.group(1) ?? m.group(2) ?? m.group(0)!;
    spans.add(TextSpan(text: tok, style: italic));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: base));
  }
  return spans.isEmpty ? [TextSpan(text: text, style: base)] : spans;
}

/// Round 6 "One thing": the single highest-priority ask centred over Silk in
/// Literata, with its two actions and a plain "n more" control below.
class OneThingAsk extends StatefulWidget {
  const OneThingAsk({
    super.key,
    required this.items,
    required this.names,
    required this.onOpen,
    this.onDecide,
    this.onCountChanged,
  });

  final List<AskItem> items;
  final Map<String, String> names;
  final void Function(AskItem item) onOpen;
  final Future<bool> Function(AskItem item, bool approve)? onDecide;
  final ValueChanged<int>? onCountChanged;

  @override
  State<OneThingAsk> createState() => _OneThingAskState();
}

class _OneThingAskState extends State<OneThingAsk> {
  final Set<String> _leaving = {}, _gone = {};
  String? _busy;
  int _index = 0;

  List<AskItem> get _visible =>
      [for (final i in widget.items) if (!_gone.contains(i.id)) i];

  @override
  void didUpdateWidget(OneThingAsk old) {
    super.didUpdateWidget(old);
    final live = {for (final i in widget.items) i.id};
    _gone.removeWhere((id) => !live.contains(id));
    _leaving.removeWhere((id) => !live.contains(id));
  }

  void _advance(int delta) {
    final n = _visible.length;
    if (n <= 1) return;
    setState(() => _index = (_index + delta) % n);
  }

  Future<void> _decide(AskItem item, bool approve) async {
    final fn = widget.onDecide;
    if (fn == null || _busy != null) return;
    setState(() => _busy = item.id);
    var ok = false;
    try {
      ok = await fn(item, approve);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!ok || !mounted) return;
    setState(() => _leaving.add(item.id));
    await Future<void>.delayed(
        reduceMotion(context) ? const Duration(milliseconds: 120) : Motion.base);
    if (!mounted) return;
    setState(() {
      _gone.add(item.id);
      _leaving.remove(item.id);
      final n = _visible.length;
      if (_index >= n) _index = math.max(0, n - 1);
    });
    widget.onCountChanged?.call(_visible.length);
  }

  String _agentName(AskItem item) {
    final raw = widget.names[item.agentId];
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    final id = item.agentId;
    return id.isEmpty ? 'Snippet' : '${id[0].toUpperCase()}${id.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    if (items.isEmpty) return const SizedBox.shrink();
    final n = items.length;
    final i = _index.clamp(0, n - 1);
    final item = items[i];
    final name = _agentName(item);
    final text = askText(item);
    final title = item.session.title.trim().isEmpty
        ? 'Untitled session'
        : item.session.title.trim();
    final meta = '$title · ${homeAge(item.session.lastActive)}';
    final kicker =
        item.kind == AskKind.handoff ? '$name handed off' : '$name asks';
    final canDecide = item.kind == AskKind.approval && widget.onDecide != null;
    final leaving = _leaving.contains(item.id);
    final busy = _busy == item.id;
    final reduce = reduceMotion(context);
    final dur = reduce ? const Duration(milliseconds: 120) : Motion.base;
    final headlineStyle = serif(30, height: 39 / 30, color: _kAskWhite);

    final body = AnimatedOpacity(
      duration: dur,
      opacity: leaving ? 0 : 1,
      child: AnimatedScale(
        duration: dur,
        scale: leaving && !reduce ? 0.97 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: n > 1
              ? (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -180) _advance(1);
                  if (v > 180) _advance(-1);
                }
              : null,
          child: Semantics(
            container: true,
            label:
                'Needs you, $n item${n == 1 ? '' : 's'}, item ${i + 1}',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label:
                      '$name, ${askKindLabel(item.kind)}, ${text.ask}. Open request',
                  child: ExcludeSemantics(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.of(20)),
                      onTap: () => widget.onOpen(item),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: S.s8, vertical: S.s8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AskerAvatar(agentId: item.agentId),
                            SizedBox(height: S.of(14)),
                            Text(
                              kicker,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(13,
                                  weight: FontWeight.w600, color: askAmber),
                            ),
                            SizedBox(height: S.of(10)),
                            Text.rich(
                              TextSpan(
                                  children: askHeadlineSpans(
                                      text.ask, headlineStyle)),
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: S.s8),
                            Text(
                              meta,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(13, color: AppColors.fg3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: S.of(24)),
                _actions(item, canDecide, busy),
                if (n > 1) ...[
                  SizedBox(height: S.of(18)),
                  _MoreButton(
                    count: n - 1,
                    onTap: () => _advance(1),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : Motion.fast,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(key: ValueKey(item.id), child: body),
    );
  }

  Widget _actions(AskItem item, bool canDecide, bool busy) {
    if (!canDecide) {
      return _OneActionPill(
        label: item.kind == AskKind.question ? 'Answer' : 'Open',
        fill: _kAskWhite,
        ink: _kAskInk,
        minWidth: 150,
        onTap: () => widget.onOpen(item),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        _OneActionPill(
          label: 'Deny',
          fill: _kAskWhite.withValues(alpha: 0.12),
          ink: _kAskWhite,
          minWidth: 100,
          onTap: busy ? null : () => _decide(item, false),
        ),
        _OneActionPill(
          label: 'Approve',
          icon: 'check',
          fill: _kAskWhite,
          ink: inkOn(_kAskWhite),
          minWidth: 150,
          onTap: busy ? null : () => _decide(item, true),
        ),
      ],
    );
  }
}

class _AskerAvatar extends StatelessWidget {
  const _AskerAvatar({required this.agentId});
  final String agentId;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 56,
        height: 56,
        child: Stack(clipBehavior: Clip.none, children: [
          AgentMochi(agentId, size: 56, state: AgentCharacterState.needs),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: askAmber,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2),
              ),
            ),
          ),
        ]),
      );
}

class _OneActionPill extends StatelessWidget {
  const _OneActionPill({
    required this.label,
    required this.fill,
    required this.ink,
    required this.minWidth,
    this.icon,
    this.onTap,
  });

  final String label;
  final Color fill;
  final Color ink;
  final double minWidth;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap == null
                  ? null
                  : () {
                      tapHaptic();
                      onTap!();
                    },
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth, minHeight: 48),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: S.s20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        AppIcon(icon!, size: 17, color: ink),
                        SizedBox(width: S.s6),
                      ],
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(16, weight: FontWeight.w500, color: ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = '$count more';
    return Semantics(
      button: true,
      label: 'Next ask, $label',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(R.pill),
          onTap: () {
            tapHaptic();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 88, minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: S.s12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: sans(15,
                          weight: FontWeight.w500, color: AppColors.fg2)),
                  SizedBox(width: S.s4),
                  AppIcon('chevron-right', size: 13, color: AppColors.fg2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
