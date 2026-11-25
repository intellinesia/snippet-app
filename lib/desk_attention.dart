import 'package:flutter/material.dart';

import 'api.dart';
import 'approval_code.dart';
import 'mochi.dart';
import 'models.dart';
import 'toast_avoid.dart';

/// A session asking the user to approve something or answer a question.
bool deskAsk(SessionInfo s) {
  if (s.settled) return false;
  final t = '${s.attention?['type'] ?? ''}'.toLowerCase();
  return t == 'approval' || t == 'question';
}

/// Desktop: the sessions waiting on the user, published by the shell so the
/// pane can carry the compact needs-you strip.
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

/// ASK-18: a flat s1 strip, 30 high, with the locked amber dot and one
/// right-aligned Review target. It stays collapsed; the session itself is
/// where the approval or question is answered.
class DeskAttentionBar extends StatelessWidget {
  const DeskAttentionBar({super.key, this.exclude});

  /// The session already on screen; its ask is in its own transcript.
  final String? exclude;

  @override
  Widget build(BuildContext context) => ToastAvoid(
        child: Builder(builder: (context) {
          final scope = DeskAttentionScope.of(context);
          final asks = [
            for (final s in scope?.asks ?? const <SessionInfo>[])
              if (s.id != exclude) s
          ];
          if (scope == null || asks.isEmpty) return const SizedBox.shrink();
          void review() => scope.onOpen(asks.first);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SizedBox(
              key: const Key('deskAttention'),
              child: AskAttentionStrip(
                count: asks.length,
                avatars: [
                  for (final s in asks.take(3))
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child:
                          AgentMochi(s.displayAgentId ?? 'snippet', size: 20),
                    ),
                ],
                onReview: review,
              ),
            ),
          );
        }),
      );
}
