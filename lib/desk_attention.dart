import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'approval_code.dart';
import 'mochi.dart';
import 'models.dart';
import 'notification_text.dart';
import 'session_quick_send.dart';
import 'theme.dart';
import 'widgets.dart';

/// A session asking the user to approve something or answer a question.
bool deskAsk(SessionInfo s) {
  if (s.settled) return false;
  final t = '${s.attention?['type'] ?? ''}'.toLowerCase();
  return t == 'approval' || t == 'question';
}

/// Desktop: the sessions waiting on the user, published by the shell so the
/// composer can carry them instead of a toast over the transcript.
class DeskAttentionScope extends InheritedWidget {
  const DeskAttentionScope({
    super.key,
    required this.client,
    required this.asks,
    required this.onOpen,
    required super.child,
  });

  final DaemonClient? client;
  final List<SessionInfo> asks;
  final void Function(SessionInfo) onOpen;

  static List<SessionInfo> asksFrom(List<SessionInfo>? all) => [
        ...?all?.where(deskAsk)
      ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));

  static DeskAttentionScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeskAttentionScope>();

  @override
  bool updateShouldNotify(DeskAttentionScope old) {
    if (client != old.client || asks.length != old.asks.length) return true;
    for (var i = 0; i < asks.length; i++) {
      if (_askKey(asks[i]) != _askKey(old.asks[i])) return true;
    }
    return false;
  }
}

String _askKey(SessionInfo s) => '${s.id}|${s.attention}';

/// One line on top of the composer: who wants what, and the buttons.
class DeskAttentionBar extends StatefulWidget {
  const DeskAttentionBar({super.key, this.exclude});

  /// The session already on screen; its ask is in its own transcript.
  final String? exclude;

  @override
  State<DeskAttentionBar> createState() => _DeskAttentionBarState();
}

class _DeskAttentionBarState extends State<DeskAttentionBar> {
  int _index = 0;
  bool _open = false;
  bool _busy = false;
  bool _failed = false;
  // Handled here; hidden until the session list catches up.
  final _done = <String>{};

  Future<void> _send(
      DaemonClient client, SessionInfo s, QuickAction action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await quickSend(client: client, session: s.id, action: action);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
      if (ok) {
        _done.add(_askKey(s));
        _open = false;
      }
    });
    if (ok) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final scope = DeskAttentionScope.of(context);
    final client = scope?.client;
    final live = {
      for (final s in scope?.asks ?? const <SessionInfo>[]) _askKey(s)
    };
    _done.retainAll(live);
    final asks = [
      for (final s in scope?.asks ?? const <SessionInfo>[])
        if (s.id != widget.exclude && !_done.contains(_askKey(s))) s
    ];
    if (scope == null || client == null || asks.isEmpty) {
      return const SizedBox.shrink();
    }
    final at = _index.clamp(0, asks.length - 1);
    final s = asks[at];
    final attention = s.attention!;
    final tool = '${attention['tool'] ?? ''}';
    final approval = approvalOf(attention);
    final question = '${attention['text'] ?? ''}'.trim();
    final title = s.title.trim().isEmpty ? 'A session' : s.title.trim();
    final ask = approval != null
        ? approval.headline(tool).toLowerCase()
        : 'has a question';
    final detail = approval != null
        ? approval.shownCommand.split('\n').first
        : question.split('\n').first;
    final choices = approval == null ? answerChoices(attention) : const [];

    final buttons = <Widget>[
      if (approval != null) ...[
        Btn('Deny',
            small: true,
            variant: BtnVariant.secondary,
            disabled: _busy,
            onTap: () => _send(client, s, const QuickDeny(via: 'desk'))),
        SizedBox(width: S.s6),
        Btn('Approve',
            small: true,
            disabled: _busy,
            onTap: () => _send(client, s, const QuickApprove(via: 'desk'))),
      ] else
        Btn('Answer',
            small: true,
            variant: BtnVariant.secondary,
            onTap: () => scope.onOpen(s)),
    ];

    final line = Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(R.of(6)),
        child: AgentMochi(s.displayAgentId ?? 'snippet', size: 20),
      ),
      SizedBox(width: S.s8),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: title,
                        style: sans(12.5,
                            weight: FontWeight.w500, color: AppColors.fg1)),
                    TextSpan(
                        text: approval != null ? ' wants to $ask' : ' $ask',
                        style: sans(12.5, color: AppColors.fg2)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (detail.isNotEmpty && !_open)
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: approval != null
                        ? mono(11.5, color: AppColors.fg3)
                        : sans(12, color: AppColors.fg3)),
            ]),
      ),
      SizedBox(width: S.s8),
      ...buttons,
    ]);

    final expanded = Padding(
      padding: EdgeInsets.only(left: 28, top: S.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (approval != null && approval.shownCommand.isNotEmpty)
            ApprovalCode(
                code: approval.shownCommand,
                shell: tool != 'change_files',
                collapsedLines: 8,
                selectable: true)
          else if (question.isNotEmpty)
            Text(question,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: sans(13, height: 1.45, color: AppColors.fg1)),
          if (choices.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: S.s8),
              child: Wrap(spacing: S.s6, runSpacing: S.s6, children: [
                for (final c in choices)
                  Btn(c.$1,
                      small: true,
                      variant: BtnVariant.secondary,
                      disabled: _busy,
                      onTap: () => _send(
                          client,
                          s,
                          QuickAnswer(answerText(attention, choiceAnswer(c)),
                              via: 'desk'))),
              ]),
            ),
        ],
      ),
    );

    Widget link(String label, VoidCallback onTap) =>
        TextButtonLite(label: label, onTap: onTap);

    final footer = (_open || asks.length > 1 || _failed)
        ? Padding(
            padding: EdgeInsets.only(left: 28, top: S.s4),
            child: Row(children: [
              if (_open) link('Open chat', () => scope.onOpen(s)),
              if (_failed)
                Text("  Couldn't send",
                    style: sans(12, color: AppColors.danger)),
              const Spacer(),
              if (asks.length > 1)
                link(
                    '${at + 1} of ${asks.length} waiting',
                    () => setState(() {
                          _index = (at + 1) % asks.length;
                          _open = false;
                        })),
            ]),
          )
        : null;

    return Padding(
      key: const Key('deskAttention'),
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: AnimatedSize(
            duration: MediaQuery.maybeDisableAnimationsOf(context) == true
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: const Cubic(0.23, 1, 0.32, 1),
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                line,
                if (_open) expanded,
                if (footer != null) footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet text action: 12px fg3, fg1 on hover.
class TextButtonLite extends StatefulWidget {
  const TextButtonLite({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<TextButtonLite> createState() => _TextButtonLiteState();
}

class _TextButtonLiteState extends State<TextButtonLite> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(widget.label,
                style: sans(12, color: _hover ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      );
}
