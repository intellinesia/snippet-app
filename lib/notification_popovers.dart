import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'motion_routes.dart';
import 'api.dart';
import 'call_prompt_card.dart';
import 'call_tracking.dart';
import 'macos_notch.dart';
import 'notification_sync.dart';
import 'notifications.dart';
import 'theme.dart';

import 'platform.dart';
import 'notification_text.dart';
import 'notification_stack.dart';
import 'notification_banner.dart';
import 'notification_card.dart';
import 'top_zone.dart';
import 'screens/phone_tool_bar.dart' show PhoneBar;
import 'screens/shell_frame.dart' show kShellTabStripHeight;
import 'session_quick_send.dart' show resolveInstanceForPayload;

class NotificationPopovers extends StatefulWidget {
  const NotificationPopovers(
      {super.key, required this.child, this.navigatorKey});
  final Widget child;

  /// Used to push the full notification list; this widget sits above the
  /// navigator so it cannot look one up itself.
  final GlobalKey<NavigatorState>? navigatorKey;
  @override
  State<NotificationPopovers> createState() => _NotificationPopoversState();
}

class _NotificationPopoversState extends State<NotificationPopovers>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final List<Map<String, dynamic>> _pending = [];
  final _timers = <Map<String, dynamic>, Timer>{};
  bool _pointer = false;
  bool _cardHold = false;
  bool _background = false;
  Map<String, dynamic>? _expandedPayload;
  Map<String, dynamic>? _autoOpen;
  late final OverlayEntry _contentEntry;

  bool get _held => _pointer || _cardHold || _background;

  /// Desktop floats begin below the centre-column tab strip. If a registered
  /// top bar (for example an attention bar) reaches lower, it wins.
  static double get _desktopAnchorTop =>
      math.max(kShellTabStripHeight, TopZone.lowestBar.value) + TopZone.gap;

  /// Information banners leave after 6 s; a needs-you banner stays 30 s, then
  /// folds into the attention bar and does not return as a banner.
  Duration _life(Map<String, dynamic> p) =>
      Duration(seconds: needsYou(p) ? 30 : 6);

  /// Newest first. Information kinds with an empty title show nothing.
  List<Map<String, dynamic>> get _ordered => [
        for (final p in _pending.reversed)
          if (needsYou(p) || '${p['title'] ?? ''}'.trim().isNotEmpty) p
      ];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away == _background) return;
    _background = away;
    _arm();
  }

  void _arm() {
    _timers.removeWhere((p, t) {
      final gone = !_pending.any((q) => identical(q, p));
      if (gone || _held) t.cancel();
      return gone || _held;
    });
    if (_held) return;
    for (final p in _pending) {
      _timers.putIfAbsent(
          p,
          () => Timer(_life(p), () {
                _timers.remove(p);
                if (mounted) _remove(p);
              }));
    }
  }

  void _afterChange() => _arm();

  void _setHold({bool? pointer, bool? card}) {
    _pointer = pointer ?? _pointer;
    _cardHold = card ?? _cardHold;
    _arm();
  }

  void _remove(Map<String, dynamic> payload,
      {bool open = false, bool feedback = false}) {
    if (!_pending.any((p) => identical(p, payload))) return;
    if (feedback) HapticFeedback.lightImpact();
    setState(() {
      if (identical(_expandedPayload, payload)) {
        _expandedPayload = null;
        _cardHold = false;
      }
      _pending.removeWhere((p) => identical(p, payload));
      _afterChange();
    });
    if (open) onNotifTap?.call(payload);
  }

  void _clearAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _pending.clear();
      _expandedPayload = null;
      _cardHold = false;
      _afterChange();
    });
  }

  void _forgetIfExpanded(Map<String, dynamic> payload) {
    if (!identical(_expandedPayload, payload)) return;
    _expandedPayload = null;
    _cardHold = false;
  }

  void _forgetHiddenExpanded() {
    final expanded = _expandedPayload;
    if (expanded == null) return;
    final visible = _ordered.take(NotificationStack.maxVisible);
    if (!visible.any((p) => identical(p, expanded))) {
      _expandedPayload = null;
      _cardHold = false;
    }
  }

  String _contextLabel(Map<String, dynamic> payload) {
    // Preserve the daemon-facing subtitle used by the notch.
    final kind = payload['kind']?.toString().split('.').last;
    final label = switch (kind) {
      'idle' => 'Finished · standing by',
      'waiting' => '',
      'error' || 'failed' => 'Failed',
      'done' || 'completed' => 'Completed',
      'term' || 'message' => 'New message',
      _ => switch ((payload['destination'] as Map?)?['type']) {
          'task' => 'Task update',
          'conversation' => 'New message',
          _ => '',
        },
    };
    final body = payload['body']?.toString().trim() ?? '';
    return body.isEmpty ? label : (label.isEmpty ? body : '$label · $body');
  }

  void _forwardToMacNotch(Map<String, dynamic> payload) {
    if (!kMacOS) return;
    MacosNotch.showNotification(
      title: payload['title']?.toString() ?? 'Snippet',
      subtitle: _contextLabel(payload),
      kind: payload['kind']?.toString() ?? '',
      payload: payload,
    );
  }

  void _addPending(Map<String, dynamic> payload) {
    _pending.removeWhere((old) {
      final drop = toastSuperseded(old, payload);
      if (drop) _forgetIfExpanded(old);
      return drop;
    });
    _pending.add(payload);
    _forgetHiddenExpanded();
  }

  @override
  void initState() {
    super.initState();
    MacosNotch.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
    _contentEntry = OverlayEntry(builder: _buildContent);
    final initial = foregroundNotifications.drain();
    initial.forEach(_addPending);
    _arm();
    for (final p in initial) {
      _forwardToMacNotch(p);
    }
    callTracker.state.addListener(_callChanged);
    visibleNotificationSession.addListener(_visibilityChanged);
    _subscription = foregroundNotifications.stream.listen((payload) {
      _forwardToMacNotch(payload);
      if (!mounted) return;
      setState(() => _addPending(payload));
      _arm();
    });
  }

  void _callChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _callAction(CallStatus status, String action) async {
    final instance = await resolveInstanceForPayload({'url': status.url});
    if (instance == null) return false;
    return callTracker.act(
        DaemonClient(instance.url, instance.token), status.callId, action);
  }

  void _visibilityChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _pending.removeWhere((p) {
            final drop = suppressVisibleNotification(p);
            if (drop) _forgetIfExpanded(p);
            return drop;
          });
          _afterChange();
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    callTracker.state.removeListener(_callChanged);
    visibleNotificationSession.removeListener(_visibilityChanged);
    _subscription?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    _contentEntry.remove();
    _contentEntry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _contentEntry.markNeedsBuild();
    return Overlay(initialEntries: [_contentEntry]);
  }

  Widget _card(Map<String, dynamic> payload, bool reducedMotion) {
    final auto = identical(payload, _autoOpen);
    if (identical(payload, _expandedPayload) || auto) {
      return NotificationMessageCard(
        key: ObjectKey(payload),
        payload: payload,
        autoOpened: auto,
        onOpen: () => _remove(payload, open: true, feedback: true),
        onDismiss: () => _remove(payload, feedback: true),
        onHold: (hold) => _setHold(card: hold),
        onSent: () => _remove(payload),
      );
    }
    return Dismissible(
      key: ObjectKey(payload),
      direction: DismissDirection.horizontal,
      movementDuration: reducedMotion ? Duration.zero : Motion.fast,
      resizeDuration: null,
      onDismissed: (_) => _remove(payload, feedback: true),
      child: NotificationBanner(
        payload: payload,
        onTap: () {
          // Needs-you and message banners expand in place; others open.
          if (cardActionFor(payload)
              case CardAction.approval ||
                  CardAction.answer ||
                  CardAction.reply) {
            HapticFeedback.selectionClick();
            setState(() => _expandedPayload = payload);
          } else {
            _remove(payload, open: true, feedback: true);
          }
        },
        onDismiss: () => _remove(payload, feedback: true),
      ),
    );
  }

  void _showAll() {
    final nav = widget.navigatorKey?.currentState;
    if (nav == null) return;
    nav.push(AppPageRoute<void>(
      builder: (_) => NotificationListPage(
        items: _ordered,
        onOpen: (p) {
          nav.pop();
          _remove(p, open: true);
        },
      ),
    ));
  }

  Widget _buildContent(BuildContext context) {
    _pending.removeWhere((p) {
      final drop = suppressVisibleNotification(p);
      if (drop) _forgetIfExpanded(p);
      return drop;
    });
    final items = _ordered;
    // Desktop opens the newest actionable needs-you toast so its buttons show.
    _autoOpen = kMobile || _expandedPayload != null
        ? null
        : items.take(NotificationStack.maxVisible).where((p) {
            if (!needsYou(p)) return false;
            final a = cardActionFor(p);
            return a == CardAction.approval || a == CardAction.answer;
          }).firstOrNull;
    final call = callTracker.state.value;
    final reducedMotion = reduceMotion(context);
    final banner = call != null
        ? CallPromptCard(
            key: ValueKey('${call.callId}|${call.phase.name}'),
            status: call,
            onAction: (a) => _callAction(call, a))
        : AnimatedSwitcher(
            duration: reducedMotion ? Duration.zero : Motion.open,
            reverseDuration: reducedMotion ? Duration.zero : Motion.close,
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, -.08), end: Offset.zero)
                    .animate(animation),
                child: ScaleTransition(
                  alignment: Alignment.topRight,
                  scale: Tween(begin: .96, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
            ),
            child: const SizedBox.shrink(),
          );
    if (kMobile) {
      final stack = call != null
          ? banner
          : items.isEmpty
              ? const SizedBox.shrink()
              : MouseRegion(
                  onEnter: (_) => _setHold(pointer: true),
                  onExit: (_) => _setHold(pointer: false),
                  child: Listener(
                    onPointerDown: (_) => _setHold(pointer: true),
                    onPointerUp: (_) => _setHold(pointer: false),
                    onPointerCancel: (_) => _setHold(pointer: false),
                    child: NotificationStack(
                      items: items,
                      onClearAll: _clearAll,
                      onShowAll: _showAll,
                      cardBuilder: (payload) => _card(payload, reducedMotion),
                    ),
                  ),
                );
      // Banners float above the page: they never move content. The top edge
      // is the lowest registered top bar plus 8 (TopZone).
      return Stack(children: [
        Positioned.fill(child: widget.child),
        ValueListenableBuilder<double>(
          valueListenable: TopZone.lowestBar,
          builder: (context, _, __) => Positioned(
            top: TopZone.floatTop(context),
            left: 16,
            right: 16,
            child: stack,
          ),
        ),
      ]);
    }
    final desktopStack = call != null
        ? banner
        : items.isEmpty
            ? const SizedBox.shrink()
            : MouseRegion(
                onEnter: (_) => _setHold(pointer: true),
                onExit: (_) => _setHold(pointer: false),
                child: NotificationStack(
                  items: items,
                  onClearAll: _clearAll,
                  onShowAll: _showAll,
                  cardBuilder: (payload) => _card(payload, reducedMotion),
                ),
              );
    return Stack(children: [
      widget.child,
      ValueListenableBuilder<double>(
        valueListenable: TopZone.lowestBar,
        builder: (context, _, __) {
          final width = math.min(360.0, MediaQuery.sizeOf(context).width - 32);
          return Positioned(
            top: _desktopAnchorTop,
            right: 24,
            width: width,
            child: SafeArea(child: desktopStack),
          );
        },
      ),
    ]);
  }
}

/// "Show all": the notification list as a pushed page, rows 56 or taller
/// carrying the banner content.
class NotificationListPage extends StatelessWidget {
  const NotificationListPage(
      {super.key, required this.items, required this.onOpen});
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic>) onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          PhoneBar(
              title: 'Notifications',
              onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: items.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NotificationBanner(
                    payload: items[i], onTap: () => onOpen(items[i])),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
