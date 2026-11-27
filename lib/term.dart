import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'theme.dart';
import 'widgets.dart';

/// Terminal colour palette derived from the active theme's `terminal.ansi`
/// slots, falling back to the default palette for missing entries.
TerminalTheme resolvedTerminalTheme() {
  final ansi = ThemeManager.instance.resolved.terminal.ansi;
  Color slot(int i) =>
      i < ansi.length ? ansi[i] : ThemeTerminalTokens.defaultAnsi[i];
  return TerminalTheme(
    cursor: AppColors.accent,
    selection: AppColors.accent.withValues(alpha: 0.33),
    foreground: AppColors.fg1,
    background: AppColors.canvas,
    black: slot(0),
    red: slot(1),
    green: slot(2),
    yellow: slot(3),
    blue: slot(4),
    magenta: slot(5),
    cyan: slot(6),
    white: slot(7),
    brightBlack: slot(8),
    brightRed: slot(9),
    brightGreen: slot(10),
    brightYellow: slot(11),
    brightBlue: slot(12),
    brightMagenta: slot(13),
    brightCyan: slot(14),
    brightWhite: slot(15),
    searchHitBackground: const Color(0xffD4923C),
    searchHitBackgroundCurrent: const Color(0xffE3A85A),
    searchHitForeground: const Color(0xff000000),
  );
}

/// Session-shell view backed by xterm.dart so cursor, wrap, and CSI
/// come from a real emulator instead of the homemade VT parser.
///
/// Two layouts: the phone one ([mobileKeys]) runs full bleed under a 1px rule
/// with the grouped key bar; the desktop one adds a cwd · branch · size footer.
class SessionTermView extends StatefulWidget {
  const SessionTermView({
    super.key,
    required this.alive,
    required this.terminal,
    required this.onInput,
    required this.onResize,
    required this.onClose,
    this.onNew,
    this.mobileKeys = false,
    this.showChrome = true,
    this.flat = false,
    this.ended = false,
    this.title,
    this.onRestart,
    this.cwd,
    this.branch,
  });

  final bool alive;
  final Terminal terminal;
  final ValueChanged<Uint8List> onInput;
  final void Function(int cols, int rows) onResize;
  final VoidCallback onClose;
  final VoidCallback? onNew;
  final bool mobileKeys;
  final bool showChrome;
  final bool flat;

  /// The shell was alive and has exited. Distinct from `!alive`, which is
  /// also true while a new shell is still starting.
  final bool ended;

  /// Tab label, used for the "Shell N ended" card.
  final String? title;
  final VoidCallback? onRestart;

  /// Desktop footer context; both optional.
  final String? cwd;
  final String? branch;

  @override
  State<SessionTermView> createState() => _SessionTermViewState();
}

/// One key in the phone key bar's overflow menu.
typedef _MoreKey = (String, TerminalKey?);

class _SessionTermViewState extends State<SessionTermView> {
  final _termView = GlobalKey<TerminalViewState>();
  final _termController = TerminalController();
  late Terminal _host;
  int _lastC = 0;
  int _lastR = 0;
  bool _ctrl = false;
  bool _alt = false;
  bool _more = false;
  double? _deadTop;

  static const _extraKeys = <(String, TerminalKey)>[
    ('home', TerminalKey.home),
    ('end', TerminalKey.end),
    ('pgup', TerminalKey.pageUp),
    ('pgdn', TerminalKey.pageDown),
    ('ins', TerminalKey.insert),
    ('del', TerminalKey.delete),
    ('F1', TerminalKey.f1),
    ('F2', TerminalKey.f2),
    ('F5', TerminalKey.f5),
    ('F10', TerminalKey.f10),
  ];

  static TerminalTheme get _theme => resolvedTerminalTheme();

  bool get _phone => widget.mobileKeys;

  @override
  void initState() {
    super.initState();
    _host = widget.terminal;
    _bind(_host);
  }

  @override
  void didUpdateWidget(SessionTermView old) {
    super.didUpdateWidget(old);
    if (old.terminal != widget.terminal) {
      _unbind(old.terminal);
      _host = widget.terminal;
      _bind(_host);
    }
    if (!widget.ended) _deadTop = null;
  }

  @override
  void dispose() {
    _unbind(_host);
    _termController.dispose();
    super.dispose();
  }

  void _bind(Terminal t) {
    t.onOutput = _onOutput;
    t.onResize = _onTermResize;
    t.addListener(_onTermChanged);
  }

  void _unbind(Terminal t) {
    t.onOutput = null;
    t.onResize = null;
    t.removeListener(_onTermChanged);
  }

  /// Output can land without this widget rebuilding; keep the ended card under
  /// the last line and drop the "starting" hint once the shell prints.
  void _onTermChanged() {
    if (!mounted || widget.alive) return;
    if (widget.ended) {
      _placeDeadCard();
    } else if (_shownStarting && !_starting) {
      setState(() {});
    }
  }

  bool _shownStarting = false;

  void _onOutput(String data) {
    if (data.isEmpty) return;
    var out = data;
    if (widget.mobileKeys && (_ctrl || _alt) && _isPrintableInsert(data)) {
      out = _applyStickyMods(data);
      setState(() => _ctrl = _alt = false);
    }
    if (out.isEmpty) return;
    widget.onInput(Uint8List.fromList(utf8.encode(out)));
  }

  bool _isPrintableInsert(String data) {
    if (data.isEmpty) return false;
    for (final u in data.runes) {
      if (u < 0x20 || u == 0x7f) return false;
    }
    return true;
  }

  String _applyStickyMods(String data) {
    final buf = StringBuffer();
    for (final u in data.runes) {
      var code = u;
      if (_ctrl) {
        final lower = code >= 0x41 && code <= 0x5a ? code + 32 : code;
        if (lower >= 0x61 && lower <= 0x7a) {
          code = lower - 0x60;
        } else if (code >= 0x40 && code <= 0x5f) {
          code = code & 0x1f;
        }
      }
      if (_alt) buf.writeCharCode(0x1b);
      buf.writeCharCode(code);
    }
    return buf.toString();
  }

  void _onTermResize(int w, int h, int pw, int ph) {
    if (w == _lastC && h == _lastR) return;
    _lastC = w;
    _lastR = h;
    widget.onResize(w, h);
    // Resize lands during layout; the footer's size readout repaints after.
    if (!_phone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _sendKey(TerminalKey key) {
    widget.terminal.keyInput(key, ctrl: _ctrl, alt: _alt);
    if (_ctrl || _alt || _more) {
      setState(() {
        _ctrl = _alt = false;
        _more = false;
      });
    }
    _termView.currentState?.requestKeyboard();
  }

  // ---- phone key bar -------------------------------------------------------

  Widget _key(String label, VoidCallback tap,
      {bool on = false, String? icon, Key? key}) {
    final fg = on ? AppColors.accent : AppColors.fg2;
    return Material(
      key: key,
      color: on ? AppColors.accent.withValues(alpha: 0.13) : Colors.transparent,
      child: InkWell(
        onTap: tap,
        child: SizedBox(
          height: 40,
          child: Center(
            child: icon != null
                ? AppIcon(icon, size: 14, color: fg)
                : Text(label,
                    maxLines: 1,
                    softWrap: false,
                    style: codeMono(12, height: 1.2, color: fg)),
          ),
        ),
      ),
    );
  }

  /// One rounded surface2 group; keys split evenly with 1px border2 rules.
  Widget _group(double width, List<Widget> keys) {
    return Container(
      width: width,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.of(12)),
      ),
      child: Row(children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) Container(width: 1, color: AppColors.border2),
          Expanded(child: keys[i]),
        ],
      ]),
    );
  }

  Widget _keyBar(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      key: const ValueKey('term-keybar'),
      padding: EdgeInsets.fromLTRB(16, 8, 16, S.s12 + inset),
      child: LayoutBuilder(builder: (context, box) {
        // CSS flex 1 1 auto: each group's basis is its keys at the 34px
        // minimum; the free width is shared 1:1:2:1, arrows taking double.
        const gap = 6.0;
        const minKey = 34.0;
        const counts = [2, 1, 4, 1];
        const grow = [1.0, 1.0, 2.0, 1.0];
        final basis = [for (final c in counts) c * minKey + (c - 1)];
        final used = basis.fold<double>(0, (a, b) => a + b) + gap * 3;
        final free = math.max(0.0, box.maxWidth - used);
        final growSum = grow.fold<double>(0, (a, b) => a + b);
        double w(int i) =>
            (basis[i] + free * grow[i] / growSum).floorToDouble();
        return Row(children: [
          _group(w(0), [
            _key('esc', () => _sendKey(TerminalKey.escape)),
            _key('tab', () => _sendKey(TerminalKey.tab)),
          ]),
          const SizedBox(width: gap),
          _group(w(1), [
            _key('ctrl', () => setState(() => _ctrl = !_ctrl), on: _ctrl),
          ]),
          const SizedBox(width: gap),
          _group(w(2), [
            _key('←', () => _sendKey(TerminalKey.arrowLeft)),
            _key('↓', () => _sendKey(TerminalKey.arrowDown)),
            _key('↑', () => _sendKey(TerminalKey.arrowUp)),
            _key('→', () => _sendKey(TerminalKey.arrowRight)),
          ]),
          const SizedBox(width: gap),
          _group(w(3), [
            _key('more', () => setState(() => _more = !_more),
                key: const ValueKey('term-more'),
                on: _more || _alt,
                icon: 'more-horizontal'),
          ]),
        ]);
      }),
    );
  }

  /// The overflow keys, as a small popover above the key bar. Kept in-tree
  /// (no route) so opening it does not take focus from the shell and drop the
  /// soft keyboard.
  Widget _moreMenu() {
    final keys = <_MoreKey>[
      ('alt', null),
      for (final k in _extraKeys) (k.$1, k.$2),
    ];
    return Container(
      key: const ValueKey('term-more-menu'),
      width: 4 * 52 + 2,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(color: AppColors.border2),
        borderRadius: BorderRadius.circular(R.of(12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Wrap(children: [
        for (var i = 0; i < keys.length; i++)
          Container(
            width: 52,
            decoration: BoxDecoration(
              border: Border(
                right: i % 4 == 3
                    ? BorderSide.none
                    : BorderSide(color: AppColors.border2),
                bottom: i ~/ 4 == (keys.length - 1) ~/ 4
                    ? BorderSide.none
                    : BorderSide(color: AppColors.border2),
              ),
            ),
            child: keys[i].$2 == null
                ? _key(
                    keys[i].$1,
                    () => setState(() {
                          _alt = !_alt;
                          _more = false;
                        }),
                    on: _alt)
                : _key(keys[i].$1, () => _sendKey(keys[i].$2!)),
          ),
      ]),
    );
  }

  // ---- ended + starting -----------------------------------------------------

  void _placeDeadCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.ended) return;
      final st = _termView.currentState;
      if (st == null) return;
      // The cursor sits on the empty line after "[process exited]".
      final top = st.cursorRect.top + 6;
      if (_deadTop == null || (top - _deadTop!).abs() > 0.5) {
        setState(() => _deadTop = top);
      }
    });
  }

  Widget _deadCard() {
    final label = widget.title == null || widget.title!.isEmpty
        ? 'Shell ended'
        : '${_capitalised(widget.title!)} ended';
    return Container(
      key: const ValueKey('term-ended'),
      padding: EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.of(12)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, color: AppColors.fg2)),
        ),
        if (widget.onRestart != null)
          Material(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(R.of(10)),
            child: InkWell(
              key: const ValueKey('term-restart'),
              borderRadius: BorderRadius.circular(R.of(10)),
              onTap: widget.onRestart,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('Restart',
                    style:
                        sans(13, weight: W.label, color: AppColors.accentFg)),
              ),
            ),
          ),
      ]),
    );
  }

  static String _capitalised(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Nothing written yet and no pty: a shell on its way up. An exited shell
  /// keeps its scrollback, so it never reads as starting.
  bool get _starting {
    if (widget.alive || widget.ended) return false;
    final lines = widget.terminal.buffer.lines;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].getText().trim().isNotEmpty) return false;
    }
    return true;
  }

  // ---- layout ----------------------------------------------------------------

  Widget _terminal(EdgeInsets padding) {
    return TerminalView(
      widget.terminal,
      key: _termView,
      controller: _termController,
      theme: _theme,
      backgroundOpacity: 0,
      autofocus: true,
      readOnly: widget.ended,
      hardwareKeyboardOnly: false,
      deleteDetection: widget.mobileKeys,
      keyboardType: TextInputType.visiblePassword,
      padding: padding,
      textStyle: TerminalStyle(
          fontSize: _phone ? 12 : 12.5, height: 1.5, fontFamily: kMonoFamily),
    );
  }

  Widget _body(EdgeInsets padding) {
    final starting = _shownStarting = _starting;
    if (widget.ended) _placeDeadCard();
    return LayoutBuilder(builder: (context, box) {
      const cardH = 52.0;
      final top = (_deadTop ?? padding.top)
          .clamp(0.0, math.max(0.0, box.maxHeight - cardH - 8))
          .toDouble();
      return Stack(children: [
        Positioned.fill(child: _terminal(padding)),
        if (starting)
          Positioned(
            left: padding.left,
            top: padding.top,
            child: IgnorePointer(
              child: Text('starting…',
                  key: const ValueKey('term-starting'),
                  style: codeMono(_phone ? 12 : 12.5, color: AppColors.fg4)),
            ),
          ),
        if (widget.ended)
          Positioned(
            left: padding.left,
            right: padding.right,
            top: top,
            child: _deadCard(),
          ),
      ]);
    });
  }

  Widget _chrome() {
    final cwd = widget.cwd?.trim() ?? '';
    final desk = !_phone;
    return Container(
      height: desk ? PaneRow.height : 40,
      padding: EdgeInsets.fromLTRB(desk ? S.s12 : S.s16, 0, S.s8, 0),
      decoration: desk
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.paneLine, width: AppColors.hairline)))
          : null,
      child: Row(children: [
        Tooltip(
          message: cwd,
          child: Text(widget.alive ? 'Shell' : 'Shell · starting',
              style: sans(desk ? PaneRow.label : 13,
                  weight: W.label,
                  color: desk
                      ? Color.lerp(AppColors.fg1, AppColors.fg2, 0.3)
                      : AppColors.fg1)),
        ),
        const Spacer(),
        if (widget.onNew != null)
          IconBtn('plus',
              size: desk ? 26 : 28,
              iconSize: desk ? 13 : 14,
              tooltip: 'New shell',
              onTap: widget.onNew),
        IconBtn('x',
            size: desk ? 26 : 28,
            iconSize: desk ? 13 : 14,
            tooltip: 'Close',
            onTap: widget.onClose),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phone) {
      final keys = !widget.ended;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.showChrome) _chrome(),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: _body(const EdgeInsets.fromLTRB(16, 4, 16, 8)),
              ),
            ),
            // Inside the body's bounds so it stays hit-testable.
            if (keys && _more)
              Positioned(right: 16, bottom: 6, child: _moreMenu()),
          ]),
        ),
        if (keys) _keyBar(context),
      ]);
    }
    return ColoredBox(
      color: AppColors.panelBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.showChrome) _chrome(),
        Expanded(child: _body(const EdgeInsets.fromLTRB(12, 4, 12, 12))),
      ]),
    );
  }
}

/// A `Terminal` that fixes `clear`.
///
/// CSI 2J only blanks the viewport, so fish's `clear` (CUP 1;1 then reprint)
/// leaves the last history line glued to the new prompt. Pushing the screen into
/// scrollback first matches gnome-terminal / iTerm. Lives here rather than in
/// session.dart so the global-shell controller can share it without importing
/// the session screen.
class ClearScrollTerminal extends Terminal {
  ClearScrollTerminal() : super(maxLines: 5000);

  @override
  void eraseDisplay() {
    if (!buffer.isAltBuffer) {
      final n = viewHeight;
      for (var i = 0; i < n; i++) {
        buffer.index();
      }
    }
    buffer.eraseDisplay();
    buffer.setCursor(0, 0);
  }
}
