import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Shared low-rate heartbeat for decorative loops.
///
/// A vsync ticker schedules a frame every refresh, and Impeller re-rasterises
/// the whole screen on each one; a 15 Hz timer keeps idle screens cheap.
class AmbientClock extends ChangeNotifier {
  AmbientClock._();

  static final AmbientClock instance = AmbientClock._();

  static const interval = Duration(milliseconds: 66);

  Timer? _timer;
  Stopwatch? _watch;
  double _base = 0;

  /// Seconds the clock has run while listened to.
  double get seconds =>
      _base + (_watch?.elapsedMicroseconds ?? 0) / Duration.microsecondsPerSecond;

  bool get isRunning => _timer != null;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_timer != null) return;
    // From `clock` so fake-async tests see fake time.
    _watch = clock.stopwatch()..start();
    _timer = Timer.periodic(interval, (_) => notifyListeners());
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (hasListeners || _timer == null) return;
    _base = seconds;
    _timer!.cancel();
    _timer = null;
    _watch = null;
  }
}

/// A repeating 0..1 phase driven by [AmbientClock] instead of a ticker.
class AmbientLoop extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  AmbientLoop(this.period, {this.reverse = false});

  final Duration period;

  /// Triangle wave 0 to 1 to 0, as `repeat(reverse: true)`.
  final bool reverse;

  bool _running = false;
  bool _muted = false;
  bool _listening = false;
  double _held = 0;
  ValueListenable<TickerModeData>? _tickerMode;

  bool get isRunning => _running;

  @override
  double get value {
    if (!_running) return _held;
    final cycle = period.inMicroseconds / Duration.microsecondsPerSecond;
    final t = (AmbientClock.instance.seconds / cycle) % (reverse ? 2.0 : 1.0);
    return reverse && t > 1 ? 2 - t : t;
  }

  @override
  AnimationStatus get status =>
      _running ? AnimationStatus.forward : AnimationStatus.dismissed;

  void start() {
    if (_running) return;
    _running = true;
    _sync();
    notifyStatusListeners(status);
  }

  /// Stops the loop, holding [at] or the current phase.
  void stop({double? at}) {
    final held = at ?? value;
    final changed = _running || held != _held;
    final wasRunning = _running;
    _held = held;
    _running = false;
    _sync();
    if (wasRunning) notifyStatusListeners(status);
    if (changed) notifyListeners();
  }

  /// Follows [TickerMode] so offstage subtrees stop updating, like tickers.
  void bind(BuildContext context) {
    final mode = TickerMode.getValuesNotifier(context);
    if (mode == _tickerMode) return;
    _tickerMode?.removeListener(_modeChanged);
    _tickerMode = mode..addListener(_modeChanged);
    _modeChanged();
  }

  void _modeChanged() {
    _muted = !(_tickerMode?.value.enabled ?? true);
    _sync();
  }

  void _sync() {
    final want = _running && !_muted;
    if (want == _listening) return;
    _listening = want;
    if (want) {
      AmbientClock.instance.addListener(notifyListeners);
    } else {
      AmbientClock.instance.removeListener(notifyListeners);
    }
  }

  @override
  void didRegisterListener() {}

  @override
  void didUnregisterListener() {}

  void dispose() {
    _tickerMode?.removeListener(_modeChanged);
    _tickerMode = null;
    _running = false;
    _sync();
    clearListeners();
    clearStatusListeners();
  }
}
