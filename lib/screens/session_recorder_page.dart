import 'package:flutter/material.dart';

import '../platform.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'spec_bar.dart';

String clockText(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// A saved recording row: date, session, duration.
class SavedRecording {
  const SavedRecording(this.date, this.session, this.duration);
  final String date, session;
  final Duration duration;
}

/// SE-09 recorder: Record button when idle, a 64 high card with a static dot,
/// tabular elapsed time and a 48 x 48 Stop while recording.
class SessionRecorderPage extends StatelessWidget {
  const SessionRecorderPage({
    super.key,
    required this.sessionTitle,
    required this.recording,
    required this.elapsed,
    required this.onRecord,
    required this.onStop,
    this.saved = const [],
    this.onOpenSaved,
  });
  final String sessionTitle;
  final bool recording;
  final Duration elapsed;
  final VoidCallback onRecord, onStop;
  final List<SavedRecording> saved;
  final void Function(int index)? onOpenSaved;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SpecBar(title: 'Recorder', subtitle: sessionTitle),
        Expanded(
          child:
              ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
              child: Text('Record this session',
                  style: sans(15, weight: W.label, color: AppColors.fg1)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                  'Keeps messages, tool calls and canvas edits for replay.',
                  style: sans(12, color: AppColors.fg3)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: recording ? _card() : _idle(),
            ),
            if (saved.isNotEmpty) ...[
              SpecLabel('Saved recordings: ${saved.length}', top: 24),
              for (var i = 0; i < saved.length; i++) _savedRow(i, saved[i]),
            ],
          ]),
        ),
      ]);

  Widget _idle() => !kMobile
      ? Semantics(
          container: true,
          label: 'Record',
          child: Align(
              alignment: Alignment.centerLeft,
              child: Btn('Record',
                  small: true, variant: BtnVariant.secondary, onTap: onRecord)))
      : Semantics(
          container: true,
          button: true,
          label: 'Record',
          child: ExcludeSemantics(
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRecord,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.fg1, width: 1.5))),
                  const SizedBox(width: 8),
                  Text('Record',
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                ]),
              ),
            ),
          ),
        );

  Widget _card() => Container(
        constraints: BoxConstraints(minHeight: kMobile ? 64 : 40),
        padding: EdgeInsets.only(left: kMobile ? 20 : 12),
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(
              width: 14,
              height: 14,
              decoration:
                  BoxDecoration(color: AppColors.fg1, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
              child: Text('Recording',
                  style: sans(kMobile ? 14 : 13,
                      weight: W.label, color: AppColors.fg1))),
          Text(clockText(elapsed),
              style: kMobile
                  ? sans(14,
                      weight: W.label, color: AppColors.fg1, tabular: true)
                  : mono(12, color: AppColors.fg1)),
          Semantics(
            container: true,
            button: true,
            label: 'Stop',
            child: ExcludeSemantics(
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onStop,
                child: SizedBox(
                  width: kMobile ? 64 : 56,
                  height: kMobile ? 48 : 28,
                  child: Center(
                      child:
                          Text('Stop', style: sans(12, color: AppColors.fg2))),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _savedRow(int i, SavedRecording r) => Semantics(
        container: true,
        button: onOpenSaved != null,
        label: '${r.date}, ${r.session}, ${clockText(r.duration)}',
        child: ExcludeSemantics(
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenSaved == null ? null : () => onOpenSaved!(i),
            child: Container(
              constraints: BoxConstraints(minHeight: kMobile ? 56 : 32),
              padding: EdgeInsets.symmetric(
                  horizontal: kMobile ? 16 : 12, vertical: kMobile ? 8 : 4),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.date,
                            style:
                                sans(kMobile ? 15 : 13, color: AppColors.fg1)),
                        Text(r.session,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12, color: AppColors.fg3)),
                      ]),
                ),
                Text(clockText(r.duration),
                    style: kMobile
                        ? sans(12, color: AppColors.fg3, tabular: true)
                        : mono(12, color: AppColors.fg3)),
              ]),
            ),
          ),
        ),
      );
}

class ReplayEvent {
  const ReplayEvent(this.at, this.text);
  final Duration at;
  final String text;
}

/// SE-09 replay: scrubber, transport row and the event list (the list is
/// omitted when a recording carries no events).
class SessionReplayPage extends StatelessWidget {
  const SessionReplayPage({
    super.key,
    required this.sessionTitle,
    required this.total,
    required this.position,
    required this.playing,
    required this.onSeek,
    required this.onToggle,
    this.onPrevious,
    this.onNext,
    this.events = const [],
  });
  final String sessionTitle;
  final Duration total, position;
  final bool playing;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onToggle;
  final VoidCallback? onPrevious, onNext;
  final List<ReplayEvent> events;

  int get _current {
    var c = -1;
    for (var i = 0; i < events.length; i++) {
      if (events[i].at <= position) c = i;
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final frac = total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final cur = _current;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpecBar(title: 'Replay', subtitle: sessionTitle),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: _Scrubber(
            fraction: frac, total: total, position: position, onSeek: onSeek),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
        child: Row(children: [
          Text(clockText(position),
              style: kMobile
                  ? sans(12, color: AppColors.fg2, tabular: true)
                  : mono(11, color: AppColors.fg3)),
          const Spacer(),
          Text(clockText(total),
              style: kMobile
                  ? sans(12, color: AppColors.fg3, tabular: true)
                  : mono(11, color: AppColors.fg3)),
        ]),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SpecIconAction('chevron-left', 'Previous event', onPrevious ?? () {}),
        const SizedBox(width: 8),
        Semantics(
          container: true,
          button: true,
          label: playing ? 'Pause' : 'Play',
          child: ExcludeSemantics(
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Container(
                width: kMobile ? 56 : 28,
                height: kMobile ? 56 : 28,
                decoration:
                    BoxDecoration(color: AppColors.fg1, shape: BoxShape.circle),
                child: Center(
                    child: AppIcon(playing ? 'pause' : 'play',
                        size: kMobile ? 24 : 14,
                        color: AppColors.bg,
                        filled: true)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SpecIconAction('chevron-right', 'Next event', onNext ?? () {}),
      ]),
      const SizedBox(height: 8),
      if (events.isNotEmpty)
        Expanded(
          child: ListView(children: [
            for (var i = 0; i < events.length; i++)
              _eventRow(events[i], i == cur),
          ]),
        ),
    ]);
  }

  Widget _eventRow(ReplayEvent e, bool current) => Container(
        constraints: BoxConstraints(minHeight: kMobile ? 54 : 32),
        margin: const EdgeInsets.symmetric(horizontal: 0),
        decoration: BoxDecoration(color: current ? AppColors.surface2 : null),
        child: Stack(alignment: Alignment.centerLeft, children: [
          if (current)
            Positioned(
                left: 0,
                top: 4,
                bottom: 4,
                child: Container(width: 2, color: AppColors.fg1)),
          Padding(
            padding: kMobile
                ? const EdgeInsets.fromLTRB(24, 8, 16, 8)
                : const EdgeInsets.fromLTRB(16, 7, 12, 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 52,
                  child: Text(clockText(e.at),
                      style: kMobile
                          ? sans(12, color: AppColors.fg3, tabular: true)
                          : mono(12, color: AppColors.fg3))),
              Expanded(
                  child: Text(e.text,
                      style: sans(kMobile ? 14 : 13,
                          weight: current ? W.label : W.body,
                          color: AppColors.fg1))),
            ]),
          ),
        ]),
      );
}

class _Scrubber extends StatelessWidget {
  const _Scrubber(
      {required this.fraction,
      required this.total,
      required this.position,
      required this.onSeek});
  final double fraction;
  final Duration total, position;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, c) {
        final w = c.maxWidth;
        void seekTo(double dx) => onSeek(Duration(
            milliseconds:
                (total.inMilliseconds * (dx / w).clamp(0.0, 1.0)).round()));
        final step = Duration(
            milliseconds:
                (total.inMilliseconds / 20).round().clamp(1, 1 << 30));
        return Semantics(
          container: true,
          slider: true,
          label: 'Replay position',
          value: '${clockText(position)} of ${clockText(total)}',
          increasedValue: clockText(position + step),
          decreasedValue: clockText(position - step),
          onIncrease: () =>
              onSeek(position + step > total ? total : position + step),
          onDecrease: () => onSeek(position - step < Duration.zero
              ? Duration.zero
              : position - step),
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => seekTo(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
              child: SizedBox(
                height: kMobile ? 48 : 28,
                child: Stack(alignment: Alignment.centerLeft, children: [
                  Container(
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.surface3,
                          borderRadius: BorderRadius.circular(2))),
                  Container(
                      width: w * fraction,
                      height: 4,
                      decoration: BoxDecoration(
                          color: kMobile ? AppColors.fg2 : AppColors.fg1,
                          borderRadius: BorderRadius.circular(2))),
                  Positioned(
                    left: (w - (kMobile ? 20 : 12)) * fraction,
                    child: Container(
                        width: kMobile ? 20 : 12,
                        height: kMobile ? 20 : 12,
                        decoration: BoxDecoration(
                            color: AppColors.fg1, shape: BoxShape.circle)),
                  ),
                ]),
              ),
            ),
          ),
        );
      });
}
