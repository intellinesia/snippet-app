import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ink.dart';
import '../../mochi.dart';
import '../../notification_text.dart' show approvalOf;
import '../../theme.dart';
import '../../widgets.dart';
import '../phone_hero.dart' show heroAgentColor;
import 'home_data.dart';
import 'home_style.dart';

const double kAskCardHeight = 211;

/// The Needs you section: a swipeable pager of asks, collapsing when empty.
class NeedsYouSection extends StatefulWidget {
  const NeedsYouSection({
    super.key,
    required this.items,
    required this.names,
    required this.onOpen,
    this.onDecide,
  });

  final List<AskItem> items;

  /// Agent id to display name.
  final Map<String, String> names;
  final void Function(AskItem item) onOpen;

  /// Resolves true when the decision was sent.
  final Future<bool> Function(AskItem item, bool approve)? onDecide;

  @override
  State<NeedsYouSection> createState() => _NeedsYouSectionState();
}

class _NeedsYouSectionState extends State<NeedsYouSection> {
  final Set<String> _leaving = {}, _gone = {};
  String? _busy;
  int _page = 0;
  PageController? _pc;
  double _fraction = 0;

  List<AskItem> get _visible =>
      [for (final i in widget.items) if (!_gone.contains(i.id)) i];

  @override
  void didUpdateWidget(NeedsYouSection old) {
    super.didUpdateWidget(old);
    final live = {for (final i in widget.items) i.id};
    _gone.removeWhere((id) => !live.contains(id));
    _leaving.removeWhere((id) => !live.contains(id));
  }

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
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
        reduceMotion(context) ? const Duration(milliseconds: 150) : Motion.base);
    if (!mounted) return;
    setState(() {
      _gone.add(item.id);
      _leaving.remove(item.id);
      final n = _visible.length;
      if (_page >= n) _page = math.max(0, n - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    final reduce = reduceMotion(context);
    return AnimatedSize(
      duration: reduce ? const Duration(milliseconds: 1) : Motion.base,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: items.isEmpty
          ? const SizedBox(width: double.infinity)
          : _section(context, items),
    );
  }

  Widget _section(BuildContext context, List<AskItem> items) {
    final n = items.length;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final h = kAskCardHeight * math.max(1.0, scale);
    final page = _page.clamp(0, n - 1);
    return Semantics(
      container: true,
      label: 'Needs you, $n item${n == 1 ? '' : 's'}, item ${page + 1}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: M.gutter),
          child: HomeLabel('Needs you',
              count: n, tone: askAmber, trailing: n > 1 ? '${page + 1} of $n' : null),
        ),
        SizedBox(
          height: h,
          child: n == 1
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: M.gutter),
                  child: _card(items[0]),
                )
              : LayoutBuilder(builder: (context, box) {
                  final w = box.maxWidth - M.gutter;
                  final f = ((box.maxWidth - 2 * M.gutter - 45 + 10) / w)
                      .clamp(0.5, 1.0);
                  if (_pc == null || (_fraction - f).abs() > 0.001) {
                    _pc?.dispose();
                    _fraction = f;
                    _pc = PageController(
                        viewportFraction: f, initialPage: page);
                  }
                  return Padding(
                    padding: EdgeInsets.only(left: M.gutter),
                    child: PageView.builder(
                      controller: _pc,
                      padEnds: false,
                      clipBehavior: Clip.none,
                      itemCount: n,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _card(items[i]),
                      ),
                    ),
                  );
                }),
        ),
        if (n > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ExcludeSemantics(
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < n; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.fg1.withValues(alpha: i == page ? 1 : 0.28),
                    ),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 18),
      ]),
    );
  }

  Widget _card(AskItem item) => AskCard(
        key: ValueKey('ask-${item.id}'),
        item: item,
        name: widget.names[item.agentId] ?? _titleCase(item.agentId),
        leaving: _leaving.contains(item.id),
        busy: _busy == item.id,
        onOpen: () => widget.onOpen(item),
        onDecide: widget.onDecide == null ? null : (ok) => _decide(item, ok),
      );
}

String _titleCase(String id) =>
    id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}';

String askKindLabel(AskKind k) => switch (k) {
      AskKind.approval => 'Approval',
      AskKind.question => 'Question',
      AskKind.handoff => 'Handoff',
    };

Color askKindTone(AskKind k) => switch (k) {
      AskKind.approval => askAmber,
      AskKind.question => askCobalt,
      AskKind.handoff => askMint,
    };

/// What the agent is asking, in plain words, and the exact command if any.
({String ask, String? command}) askText(AskItem item) {
  final a = item.session.attention ?? const <String, dynamic>{};
  final title = item.session.title.trim();
  switch (item.kind) {
    case AskKind.approval:
      final ap = approvalOf(a)!;
      final label = '${a['label'] ?? ''}'.trim();
      final cmd = ap.shownCommand.split(RegExp(r'\s+')).join(' ');
      return (
        ask: label.isNotEmpty ? label : ap.headline('${a['tool'] ?? ''}'),
        command: cmd.isEmpty ? null : cmd,
      );
    case AskKind.question:
      final t = '${a['text'] ?? ''}'.trim();
      return (ask: t.isNotEmpty ? t : 'Needs your input', command: null);
    case AskKind.handoff:
      final t = '${a['text'] ?? ''}'.trim();
      return (
        ask: t.isNotEmpty ? t : (title.isEmpty ? 'Handed off to you' : title),
        command: null,
      );
  }
}

class AskCard extends StatelessWidget {
  const AskCard({
    super.key,
    required this.item,
    required this.name,
    required this.onOpen,
    this.onDecide,
    this.leaving = false,
    this.busy = false,
  });

  final AskItem item;
  final String name;
  final VoidCallback onOpen;
  final ValueChanged<bool>? onDecide;
  final bool leaving;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final colour = heroAgentColor(item.agentId);
    final tone = askKindTone(item.kind);
    final text = askText(item);
    final title = item.session.title.trim().isEmpty
        ? 'Untitled session'
        : item.session.title.trim();
    final canDecide = item.kind == AskKind.approval && onDecide != null;
    final dur = reduce ? const Duration(milliseconds: 150) : Motion.base;
    return AnimatedOpacity(
      duration: dur,
      opacity: leaving ? 0 : 1,
      child: AnimatedScale(
        duration: dur,
        scale: leaving && !reduce ? 0.96 : 1,
        child: Semantics(
          container: true,
          label: '$name, ${askKindLabel(item.kind)}, ${text.ask}',
          child: Material(
            color: AppColors.surface2.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(R.of(20)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: EdgeInsets.fromLTRB(S.s16, S.of(14), S.s16, S.of(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      AgentMochi(item.agentId,
                          size: 28, state: AgentCharacterState.waiting),
                      SizedBox(width: S.s8),
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(15,
                                weight: W.label, color: AppColors.fg1)),
                      ),
                      SizedBox(width: S.s8),
                      TonePill(askKindLabel(item.kind), tone: tone),
                    ]),
                    SizedBox(height: S.s8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(text.ask,
                            maxLines: text.command == null ? 3 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(17, height: 1.3, color: AppColors.fg1)),
                      ),
                    ),
                    if (text.command != null) ...[
                      Container(
                        key: const ValueKey('ask-command'),
                        height: 32,
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.symmetric(horizontal: S.s12),
                        decoration: BoxDecoration(
                          color: AppColors.surface3,
                          borderRadius: BorderRadius.circular(R.of(10)),
                        ),
                        child: Text('\$ ${text.command}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: codeMono(13, color: AppColors.fg2)),
                      ),
                      SizedBox(height: S.s8),
                    ],
                    Padding(
                      padding: EdgeInsets.only(bottom: S.s8),
                      child: Text(
                          '$title · ${homeAge(item.session.lastActive)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: AppColors.fg3)),
                    ),
                    _actions(colour, canDecide),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(Color colour, bool canDecide) {
    if (!canDecide) {
      return Row(children: [
        Expanded(
          child: AskAction(
            label: item.kind == AskKind.question ? 'Answer' : 'Open',
            fill: colour,
            ink: inkOn(colour),
            onTap: onOpen,
          ),
        ),
      ]);
    }
    return Row(children: [
      Expanded(
        flex: 34,
        child: AskAction(
          label: 'Deny',
          fill: AppColors.surface3,
          ink: AppColors.fg1,
          onTap: busy ? null : () => onDecide!(false),
        ),
      ),
      SizedBox(width: S.s8),
      Expanded(
        flex: 66,
        child: AskAction(
          label: 'Approve',
          icon: 'check',
          fill: colour,
          ink: inkOn(colour),
          onTap: busy ? null : () => onDecide!(true),
        ),
      ),
    ]);
  }
}

class AskAction extends StatelessWidget {
  const AskAction({
    super.key,
    required this.label,
    required this.fill,
    required this.ink,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String? icon;
  final Color fill;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: Material(
            color: onTap == null ? fill.withValues(alpha: 0.5) : fill,
            borderRadius: BorderRadius.circular(R.of(14)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap == null
                  ? null
                  : () {
                      tapHaptic();
                      onTap!();
                    },
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[
                      AppIcon(icon!, size: 16, color: ink),
                      SizedBox(width: S.s6),
                    ],
                    Text(label,
                        maxLines: 1,
                        style: sans(15, weight: W.label, color: ink)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
