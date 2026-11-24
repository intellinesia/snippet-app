import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../tap_detector.dart';

/// Desktop "/" command popover: pure parse/filter logic, a controller driven
/// by the composer input, and the popover widget. Phone never mounts it.

enum SlashCmd { goal, compact, fork, handoff, wakes, resume, settle, warm }

/// A "/query" token found before the caret. [rest] only carries text for
/// "/goal some text" so the goal can be set without the editor.
class SlashQuery {
  const SlashQuery(this.start, this.end, this.query, [this.rest = '']);
  final int start; // offset of the '/'
  final int end; // caret
  final String query;
  final String rest;
}

final _slashRe = RegExp(r'(?:^|\s)/([\w\-]*)$');
final _goalRe = RegExp(r'^/goal[ \t]+([^\n]*)$');

SlashQuery? parseSlash(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  final before = text.substring(0, caret);
  final g = _goalRe.firstMatch(before);
  if (g != null) return SlashQuery(0, caret, 'goal', g.group(1)!);
  final m = _slashRe.firstMatch(before);
  if (m == null) return null;
  final slash = before.lastIndexOf('/');
  return SlashQuery(slash, caret, m.group(1)!);
}

class SlashItem {
  const SlashItem(this.cmd, this.label, this.command, this.icon,
      {this.value, this.drill = false});
  final SlashCmd cmd;
  final String label;
  final String command;
  final String icon;
  final String? value;
  final bool drill;
}

List<SlashItem> slashItems({
  required bool goalOngoing,
  required bool isMc,
  required String resumeMode,
  required bool settleOn,
  bool? warmOn,
}) =>
    [
      SlashItem(SlashCmd.goal, goalOngoing ? 'Cancel goal' : 'Set goal',
          '/goal', 'goal'),
      const SlashItem(SlashCmd.compact, 'Compact history', '/compact', 'wrap'),
      const SlashItem(SlashCmd.fork, 'Fork from here', '/fork', 'git-fork'),
      if (!isMc)
        const SlashItem(SlashCmd.handoff, 'Hand off', '/handoff', 'send',
            drill: true),
      if (isMc)
        const SlashItem(
            SlashCmd.wakes, 'Automated wakes', '/wakes', 'activity'),
      SlashItem(SlashCmd.resume, 'Cold resume', '/resume', 'history',
          value: switch (resumeMode) {
            'lean' => 'Lean',
            'full' => 'Full',
            _ => 'Ask',
          },
          drill: true),
      SlashItem(SlashCmd.settle, 'Auto-settle', '/settle', 'clock',
          value: settleOn ? 'On' : 'Off', drill: true),
      if (warmOn != null)
        SlashItem(SlashCmd.warm, 'Keep warm', '/warm', 'zap',
            value: warmOn ? 'On' : 'Off', drill: true),
    ];

List<SlashItem> filterSlash(List<SlashItem> items, String query) {
  final q = query.toLowerCase();
  if (q.isEmpty) return items;
  return items
      .where((i) =>
          i.label.toLowerCase().contains(q) ||
          i.command.toLowerCase().contains(q))
      .toList();
}

String formatTokens(int n) => n >= 1000 ? '~${(n / 1000).round()}k' : '~$n';

/// Live session facts and actions the controller needs; refreshed each build.
class SlashEnv {
  const SlashEnv({
    required this.goalOngoing,
    required this.isMc,
    required this.resumeMode,
    required this.settleOn,
    required this.resumeTokens,
    required this.onCommand,
    required this.onResume,
    required this.onSettle,
    this.warmOn,
    this.onWarm,
    this.handoffAgents,
    this.onHandOff,
  });
  final bool goalOngoing;
  final bool isMc;
  final String resumeMode;
  final bool settleOn;
  final int? resumeTokens;
  final void Function(SlashCmd cmd, String rest) onCommand;
  final void Function(String mode) onResume;
  final void Function(bool on) onSettle;

  /// Keep warm, once known; null hides the command.
  final bool? warmOn;
  final void Function(bool on)? onWarm;

  /// (id, name) of agents this session can pass to; null while loading.
  final List<(String, String)>? handoffAgents;
  final void Function(String id, String name)? onHandOff;
}

class SlashController extends ChangeNotifier {
  SlashController(this.input) {
    input.addListener(_onInput);
  }
  final TextEditingController input;
  SlashEnv? env;

  SlashQuery? _q;
  SlashCmd? _sub;
  int _subStart = 0;
  String? _subText;
  bool _dismissed = false;
  bool _own = false;
  int index = 0;

  SlashCmd? get sub => _sub;
  SlashQuery? get query => _q;

  List<SlashItem> get rootItems {
    final e = env;
    if (e == null || _q == null) return const [];
    return filterSlash(
        slashItems(
            goalOngoing: e.goalOngoing,
            isMc: e.isMc,
            resumeMode: e.resumeMode,
            settleOn: e.settleOn,
            warmOn: e.warmOn),
        _q!.query);
  }

  /// Sub-list option count, including the leading "Back to commands" row.
  int get _subCount => switch (_sub) {
        SlashCmd.resume => 4,
        SlashCmd.handoff => 1 + (env?.handoffAgents?.length ?? 0),
        _ => 3,
      };

  bool get isOpen =>
      env != null &&
      (_sub != null || (!_dismissed && rootItems.isNotEmpty));

  int get _count => _sub != null ? _subCount : rootItems.length;

  void _onInput() {
    if (_own) return;
    if (_sub != null) {
      if (input.text != _subText) {
        _sub = null;
        _dismissed = true;
        _q = null;
        notifyListeners();
      }
      return;
    }
    final v = input.value;
    final q = v.selection.isValid && v.selection.isCollapsed
        ? parseSlash(v.text, v.selection.baseOffset)
        : null;
    final changed = q?.query != _q?.query || q?.rest != _q?.rest;
    if (q == null || (changed && q.query != _q?.query)) _dismissed = false;
    _q = q;
    if (changed) index = 0;
    notifyListeners();
  }

  void _removeToken() {
    final q = _q;
    if (q == null) return;
    final t = input.text;
    final text = t.replaceRange(q.start, q.end.clamp(0, t.length), '');
    _own = true;
    input.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: q.start));
    _own = false;
    _subStart = q.start;
    _subText = text;
  }

  void close() {
    _dismissed = true;
    _sub = null;
    notifyListeners();
  }

  void move(int d) {
    final n = _count;
    if (n == 0) return;
    index = (index + d + n) % n;
    notifyListeners();
  }

  void hover(int i) {
    if (i == index) return;
    index = i;
    notifyListeners();
  }

  void back() {
    if (_sub == null) return;
    final t = input.text;
    final at = _subStart.clamp(0, t.length);
    _sub = null;
    _dismissed = false;
    index = 0;
    _own = true;
    input.value = TextEditingValue(
        text: t.replaceRange(at, at, '/'),
        selection: TextSelection.collapsed(offset: at + 1));
    _own = false;
    _q = SlashQuery(at, at + 1, '');
    notifyListeners();
  }

  /// Picks the row at [i]; in a sub-list row 0 is "Back to commands".
  void pick(int i) {
    final e = env;
    if (e == null) return;
    if (_sub != null) {
      if (i == 0) return back();
      final cmd = _sub!;
      _sub = null;
      _dismissed = true;
      _q = null;
      notifyListeners();
      switch (cmd) {
        case SlashCmd.resume:
          e.onResume(const ['ask', 'lean', 'full'][i - 1]);
        case SlashCmd.warm:
          e.onWarm?.call(i == 1);
        case SlashCmd.handoff:
          final a = e.handoffAgents;
          if (a != null && i - 1 < a.length) {
            e.onHandOff?.call(a[i - 1].$1, a[i - 1].$2);
          }
        default:
          e.onSettle(i == 1);
      }
      return;
    }
    final items = rootItems;
    if (i < 0 || i >= items.length) return;
    final item = items[i];
    final rest = _q!.rest.trim();
    _removeToken();
    if (item.drill) {
      _sub = item.cmd;
      _q = null;
      index = 0;
      notifyListeners();
      return;
    }
    _dismissed = true;
    _q = null;
    notifyListeners();
    e.onCommand(item.cmd, rest);
  }

  /// Returns true when the key was consumed by the open menu.
  KeyEventResult handleKey(KeyEvent event) {
    if (!isOpen) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final hk = HardwareKeyboard.instance;
    final plain = !hk.isMetaPressed && !hk.isControlPressed && !hk.isAltPressed;
    if (k == LogicalKeyboardKey.arrowDown) {
      move(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      move(-1);
    } else if (k == LogicalKeyboardKey.escape) {
      close();
    } else if (k == LogicalKeyboardKey.backspace && _sub != null) {
      back();
    } else if ((k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.tab) &&
        plain) {
      pick(index);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.handled; // never send while the menu is open
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    input.removeListener(_onInput);
    super.dispose();
  }
}

/// Wraps the composer field so the open menu sees keys before the send shortcut.
class SlashKeys extends StatelessWidget {
  const SlashKeys({super.key, required this.controller, required this.child});
  final SlashController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) => controller.handleKey(e),
        child: child,
      );
}

class SlashMenuPopover extends StatelessWidget {
  const SlashMenuPopover({super.key, required this.controller});
  final SlashController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (_, __) {
          if (!controller.isOpen) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 4, bottom: S.s6),
              child: SlashMenuView(controller: controller),
            ),
          );
        },
      );
}

/// The popover body alone, so renders and tests can mount it directly.
class SlashMenuView extends StatelessWidget {
  const SlashMenuView({super.key, required this.controller});
  final SlashController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final e = c.env!;
    final sub = c.sub;
    final rows = <Widget>[];
    if (sub == null) {
      final items = c.rootItems;
      rows.add(_group('Session'));
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        rows.add(_Row(
          icon: it.icon,
          label: it.label,
          on: i == c.index,
          onTap: () => c.pick(i),
          onHover: () => c.hover(i),
          right: it.drill
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(it.value ?? '', style: sans(11.5, color: AppColors.fg4)),
                  AppIcon('chevron-right', size: 14, color: AppColors.fg3),
                ])
              : Text(it.command, style: mono(11, color: AppColors.fg4)),
        ));
      }
    } else {
      final isResume = sub == SlashCmd.resume;
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Text(
            switch (sub) {
              SlashCmd.resume => '/resume',
              SlashCmd.warm => '/warm',
              SlashCmd.handoff => '/handoff',
              _ => '/settle',
            },
            style: mono(11, color: AppColors.fg4)),
      ));
      rows.add(_Row(
        icon: 'arrow-left',
        label: 'Back to commands',
        on: c.index == 0,
        onTap: () => c.pick(0),
        onHover: () => c.hover(0),
        right: Text('Backspace', style: sans(11, color: AppColors.fg4)),
      ));
      rows.add(_group(switch (sub) {
        SlashCmd.resume => 'When this session is cold',
        SlashCmd.warm => 'Keep the cache warm while idle',
        SlashCmd.handoff => 'Pass to · what you typed goes as the note',
        _ => 'After 12 hours idle',
      }));
      Widget check() => AppIcon('check', size: 14, color: AppColors.fg2);
      Widget opt(int i, String label, bool current,
              {String? meta, bool mono_ = false}) =>
          _Row(
            icon: null,
            label: label,
            on: c.index == i,
            onTap: () => c.pick(i),
            onHover: () => c.hover(i),
            right: Row(mainAxisSize: MainAxisSize.min, children: [
              if (meta != null)
                Text(meta,
                    style: mono_
                        ? mono(11, color: AppColors.fg4)
                        : sans(11.5, color: AppColors.fg4)),
              if (current) ...[
                if (meta != null) const SizedBox(width: 8),
                check(),
              ],
            ]),
          );
      if (sub == SlashCmd.handoff) {
        final a = e.handoffAgents;
        if (a == null) {
          rows.add(_group('Loading agents…'));
        } else if (a.isEmpty) {
          rows.add(_group('No other agent is available'));
        } else {
          for (var i = 0; i < a.length; i++) {
            rows.add(opt(i + 1, a[i].$2, false));
          }
        }
      } else if (sub == SlashCmd.warm) {
        rows.addAll([
          opt(1, 'On', e.warmOn == true),
          opt(2, 'Off', e.warmOn != true),
        ]);
      } else if (isResume) {
        final t = e.resumeTokens;
        rows.addAll([
          opt(1, 'Ask each time', e.resumeMode == 'ask'),
          opt(2, 'Lean', e.resumeMode == 'lean', meta: 'summary'),
          opt(3, 'Full', e.resumeMode == 'full',
              meta: t == null ? null : formatTokens(t), mono_: true),
        ]);
      } else {
        rows.addAll([
          opt(1, 'On', e.settleOn),
          opt(2, 'Off', !e.settleOn),
        ]);
      }
    }
    return Container(
      // Phone: the full content width, above the composer, 6 rows then scroll.
      width: kMobile ? double.infinity : 300,
      constraints: kMobile ? const BoxConstraints(maxHeight: 6 * 48 + 8) : null,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(kMobile ? 12 : 10),
      ),
      child: kMobile
          ? SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows),
    );
  }

  Widget _group(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: Text(t, style: sans(11, color: AppColors.fg4)),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    required this.onHover,
    required this.right,
  });
  final String? icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final Widget right;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => onHover(),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: kMobile ? 48 : 30),
            padding: EdgeInsets.symmetric(horizontal: kMobile ? 12 : 8),
            decoration: BoxDecoration(
              color: on
                  ? (kMobile
                      ? AppColors.surface3
                      : AppColors.fg1.withValues(alpha: 0.07))
                  : null,
              borderRadius: BorderRadius.circular(kMobile ? 8 : 6),
            ),
            child: Row(children: [
              if (icon != null) ...[
                AppIcon(icon!, size: 16, color: AppColors.fg3),
                const SizedBox(width: 10),
              ] else
                const SizedBox(width: 26),
              Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 13 : 12.5, color: AppColors.fg2))),
              right,
            ]),
          ),
        ),
      );
}
