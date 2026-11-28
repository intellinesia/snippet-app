import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/ask_kit.dart';
import '../platform.dart';
import '../state_cards.dart';
import '../theme.dart';
import '../toast.dart';
import '../widgets.dart';
import 'routing_screen.dart' show limitLabel;

/// The limit window is not sent with the event, so the progress track assumes
/// the common five hour window.
const _window = Duration(hours: 5);

class LimitCard extends StatefulWidget {
  const LimitCard({
    super.key,
    required this.client,
    required this.session,
    required this.profile,
    required this.resetsAt,
    required this.options,
    required this.settled,
  });

  final DaemonClient client;
  final String session;
  final String profile;
  final int resetsAt;
  final List<String> options;
  final bool settled;

  @override
  State<LimitCard> createState() => _LimitCardState();
}

class _LimitCardState extends State<LimitCard> {
  String? _busy;

  Future<void> _act(String action, {String? profile}) async {
    setState(() => _busy = action);
    try {
      await widget.client
          .resolveLimit(widget.session, action, profile: profile);
    } catch (e) {
      if (mounted) toast(context, "Couldn't do that: $e", danger: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickProfile() async {
    final p = await showAppMenu<String>(
      context,
      title: 'Switch profile',
      items: [
        for (final o in widget.options)
          appMenuItem(value: o, label: o, icon: 'cpu'),
      ],
    );
    if (p != null && mounted) _act('switch', profile: p);
  }

  static String _in(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.resetsAt > 0;
    final reset = has ? limitLabel(widget.resetsAt) : null;
    if (widget.settled) {
      return NoteLine(
          reset == null
              ? '${widget.profile} hit its usage limit. Handled.'
              : '${widget.profile} hit its usage limit. Resets at $reset.',
          icon: 'clock');
    }
    final left = has
        ? DateTime.fromMillisecondsSinceEpoch(widget.resetsAt * 1000)
            .difference(DateTime.now())
        : Duration.zero;
    final share =
        has ? (1 - left.inSeconds / _window.inSeconds).clamp(0.0, 1.0) : 0.0;
    final one = widget.options.length == 1;
    final busy = _busy != null;
    final switchLabel = _busy == 'switch'
        ? 'Switching...'
        : one
            ? 'Continue on ${widget.options.first}'
            : 'Switch profile';
    if (!kMobile) {
      final title = has
          ? '${widget.profile} limit reached, resets $reset'
          : '${widget.profile} limit reached';
      return DesktopAskCard(
        key: const ValueKey('limit-card'),
        kindLabel: 'Usage limit',
        needsYou: widget.options.isNotEmpty,
        meta: widget.profile,
        title: title,
        payload: Text(
            has
                ? 'Resets in ${_in(left.isNegative ? Duration.zero : left)}. Continue on another model now, or wait.'
                : 'Continue on another model now, or wait.',
            style: sans(12, height: 17 / 12, color: AppColors.fg2)),
        actions: [
          if (widget.options.isNotEmpty)
            AskButton(switchLabel,
                variant: AskButtonVariant.secondary,
                busy: _busy == 'switch',
                onTap: busy
                    ? null
                    : (one
                        ? () => _act('switch', profile: widget.options.first)
                        : _pickProfile)),
          AskButton(_busy == 'wait' ? 'Waiting' : 'Wait for reset',
              variant: AskButtonVariant.ghost,
              busy: _busy == 'wait',
              onTap: busy ? null : () => _act('wait')),
        ],
      );
    }
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          key: const ValueKey('limit-card'),
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(minHeight: 206),
          decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AppIcon('clock', size: 16, color: AppColors.fg2)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('${widget.profile} usage limit reached',
                            style: sans(15,
                                weight: FontWeight.w500, color: AppColors.fg1)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                          has
                              ? 'Resets at $reset, in ${_in(left.isNegative ? Duration.zero : left)}.'
                              : 'It resets later. Continue on another model now, or wait.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(13, height: 18 / 13, color: AppColors.fg2)),
                    ]),
              ),
            ]),
            if (has) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  key: const ValueKey('limit-track'),
                  height: 4,
                  width: double.infinity,
                  child: Stack(children: [
                    Positioned.fill(
                        child: ColoredBox(color: AppColors.surface3)),
                    Positioned.fill(
                        child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: share,
                            child: ColoredBox(color: AppColors.fg2))),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (widget.options.isNotEmpty)
              PanelButton(switchLabel,
                  primary: true,
                  onTap: busy
                      ? null
                      : (one
                          ? () => _act('switch', profile: widget.options.first)
                          : _pickProfile)),
            if (widget.options.isNotEmpty) const SizedBox(height: 8),
            PanelButton(_busy == 'wait' ? 'Waiting...' : 'Wait for reset',
                primary: false, onTap: busy ? null : () => _act('wait')),
          ]),
        ));
  }
}
