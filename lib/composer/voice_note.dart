import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../ambient/hold.dart';
import '../api.dart';
import '../composer_strip.dart';
import '../glass.dart';
import '../media_views.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'composer_card.dart';

typedef VoiceNoteToast = void Function(String message, {bool danger});

class VoiceNoteController extends ChangeNotifier {
  VoiceNoteController({
    required this.client,
    this.onToast,
    this.onConfirmTake,
    this.filePrefix = 'snippet-voice',
  });

  final DaemonClient client;
  final VoiceNoteToast? onToast;
  final Future<void> Function(Uint8List bytes)? onConfirmTake;
  final String filePrefix;

  Duration _maxRecordingDuration = const Duration(minutes: 3);
  final AudioRecorder _recorder = HeldRecorder();
  AudioPlayer? _player;

  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _recordingTimer;

  bool _isRecording = false;
  String? _recordingPath;
  Uint8List? _recordingBytes;
  Duration _recordingElapsed = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  bool _isPlayingRecording = false;
  final WaveBuffer _waveform = WaveBuffer();
  bool _disposed = false;

  bool get isRecording => _isRecording;
  bool get hasTake => _recordingPath != null || _recordingBytes != null;
  bool get isReviewing => !_isRecording && hasTake;
  bool get isActive => _isRecording || hasTake;
  String? get path => _recordingPath;
  Uint8List? get bytes => _recordingBytes;
  Duration get elapsed => _recordingElapsed;
  Duration get playbackPosition => _playbackPosition;
  Duration get playbackDuration => _playbackDuration;
  bool get isPlaying => _isPlayingRecording;
  WaveBuffer get waveform => _waveform;

  @visibleForTesting
  void debugSeedTake(
    Uint8List bytes, {
    String? path,
    Duration elapsed = const Duration(seconds: 2),
  }) {
    _isRecording = false;
    _recordingPath = path;
    _recordingBytes = bytes;
    _recordingElapsed = elapsed;
    _waveform
      ..clear()
      ..add(0.4);
    notifyListeners();
  }

  AudioPlayer get _audioPlayer {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _playerStateSub = player.onPlayerStateChanged.listen((state) {
      if (_disposed) return;
      _isPlayingRecording = state == PlayerState.playing;
      notifyListeners();
    });
    _positionSub = player.onPositionChanged.listen((position) {
      if (_disposed) return;
      _playbackPosition = position;
      notifyListeners();
    });
    _durationSub = player.onDurationChanged.listen((duration) {
      if (_disposed) return;
      _playbackDuration = duration;
      notifyListeners();
    });
    return _player = player;
  }

  void _toast(String message, {bool danger = false}) {
    if (_disposed) return;
    onToast?.call(message, danger: danger);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stop();
    } else {
      await start();
    }
  }

  Future<void> start() async {
    if (!kCanRecord || _disposed) return;
    _isRecording = true;
    _recordingElapsed = Duration.zero;
    _waveform
      ..clear()
      ..add(0.08);
    _notify();

    final granted = kMobile
        ? (await Permission.microphone.request()).isGranted
        : await _recorder.hasPermission();
    if (_disposed) return;
    if (!granted) {
      _isRecording = false;
      _notify();
      _toast(
        kMobile
            ? 'Microphone permission is required.'
            : 'Microphone permission is required by macOS.',
        danger: true,
      );
      if (kMobile) {
        final status = await Permission.microphone.status;
        if (status.isPermanentlyDenied) await openAppSettings();
      }
      return;
    }

    try {
      final voice = (await client
              .getConfig()
              .timeout(const Duration(seconds: 3)))
          .voice;
      if (_disposed) return;
      if (!voice.enabled) {
        _isRecording = false;
        _notify();
        _toast('Voice notes are turned off in Settings → Voice.');
        return;
      }
      _maxRecordingDuration = Duration(seconds: voice.maxSeconds);
    } catch (_) {}

    if (_disposed) return;
    try {
      if (hasTake) {
        await discard();
      }
      final tempDir = await getTemporaryDirectory();
      if (_disposed) return;
      final path =
          '${tempDir.path}/$filePrefix-${DateTime.now().microsecondsSinceEpoch}.$voiceNoteExtension';
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: kMobile ? 16000 : 44100,
          numChannels: 1,
          androidConfig: const AndroidRecordConfig(manageBluetooth: false),
        ),
        path: path,
      );
      if (_disposed) {
        unawaited(_recorder.cancel().catchError((_) {}));
        return;
      }
      if (!await _recorder.isRecording()) {
        await _recorder.cancel();
        _isRecording = false;
        _notify();
        _toast('Could not start recording.', danger: true);
        return;
      }
      _amplitudeSub?.cancel();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
        if (_disposed) return;
        final level = ((a.current + 60) / 60).clamp(0.04, 1.0).toDouble();
        _waveform.add(level);
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed) return;
        final next = _recordingElapsed + const Duration(seconds: 1);
        if (next >= _maxRecordingDuration) {
          _recordingElapsed = _maxRecordingDuration;
          _notify();
          unawaited(stop());
          final d = _maxRecordingDuration;
          _toast(
              'Recording stopped at the ${d.inSeconds % 60 == 0 ? '${d.inMinutes}-minute' : '${d.inSeconds}-second'} limit.');
        } else {
          _recordingElapsed = next;
          _notify();
        }
      });
      _recordingPath = path;
      _notify();
    } catch (e) {
      _isRecording = false;
      _notify();
      _toast('Could not start recording: $e', danger: true);
    }
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    _isRecording = false;
    _notify();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final stoppedPath = await _recorder.stop();
      final path = stoppedPath ?? _recordingPath;
      if (path == null) {
        _toast('No recording was captured.');
        return;
      }
      final bytes = await _waitForRecordingFile(path);
      if (bytes == null || bytes.isEmpty) {
        await discard();
        _toast('The recording was empty.');
        return;
      }
      if (_disposed) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
        return;
      }
      _recordingPath = path;
      _recordingBytes = bytes;
      _notify();
    } catch (e) {
      await discard();
      _toast('Could not finish recording: $e', danger: true);
    }
  }

  Future<Uint8List?> _waitForRecordingFile(String path) async {
    final file = File(
        path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
    const attempts = 120;
    for (var i = 0; i < attempts; i++) {
      try {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  Future<void> discard() async {
    final path = _recordingPath;
    final wasRecording = _isRecording;
    _isRecording = false;
    _recordingPath = null;
    _recordingBytes = null;
    _recordingElapsed = Duration.zero;
    _playbackPosition = Duration.zero;
    _playbackDuration = Duration.zero;
    _waveform.clear();
    _isPlayingRecording = false;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _notify();

    if (wasRecording) {
      try {
        await _recorder.cancel();
      } catch (_) {}
    }
    final player = _player;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
    }
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<bool> confirmTake([
    Future<void> Function(Uint8List bytes)? accept,
  ]) async {
    final fn = accept ?? onConfirmTake;
    if (fn == null) return false;
    final path = _recordingPath;
    final currentBytes = _recordingBytes;
    if (path == null && currentBytes == null) return false;
    try {
      if (currentBytes == null || currentBytes.isEmpty) {
        await discard();
        _toast('The recording was empty.');
        return false;
      }
      await fn(currentBytes);
      await discard();
      return true;
    } catch (e) {
      _toast('Could not attach recording: $e', danger: true);
      return false;
    }
  }

  Future<void> recordMore([
    Future<void> Function(Uint8List bytes)? accept,
  ]) async {
    if (await confirmTake(accept)) await start();
  }

  Future<void> togglePlayback() async {
    final path = _recordingPath;
    if (path == null || _isRecording) return;
    try {
      if (_isPlayingRecording) {
        await _audioPlayer.pause();
      } else if (_audioPlayer.state == PlayerState.paused) {
        await _audioPlayer.resume();
      } else {
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      _toast('Could not play preview: $e', danger: true);
    }
  }

  static String formatDuration(Duration d) {
    final seconds = d.inSeconds.clamp(0, 5999);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _disposed = true;
    _amplitudeSub?.cancel();
    _recordingTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    if (_isRecording) {
      unawaited(_recorder.cancel().catchError((_) {}));
    }
    if (kCanRecord) {
      unawaited(_recorder.dispose().catchError((_) {}));
    }
    final player = _player;
    if (player != null) unawaited(player.dispose().catchError((_) {}));
    final pendingPath = _recordingPath;
    if (pendingPath != null) {
      try {
        final f = File(pendingPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }
}

class VoiceNoteRecorderStrip extends StatelessWidget {
  const VoiceNoteRecorderStrip({
    super.key,
    required this.controller,
    required this.onSend,
    this.sending = false,
    this.onMore,
  });

  final VoiceNoteController controller;
  final VoidCallback onSend;
  final bool sending;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final recording = controller.isRecording;
        final reviewing = controller.isReviewing;
        final playbackDuration = controller.playbackDuration;
        final elapsed = controller.elapsed;
        final playbackPosition = controller.playbackPosition;
        final total =
            playbackDuration > Duration.zero ? playbackDuration : elapsed;
        final time = reviewing
            ? '${VoiceNoteController.formatDuration(playbackPosition)} / ${VoiceNoteController.formatDuration(total)}'
            : VoiceNoteController.formatDuration(elapsed);
        final progress = !reviewing || total.inMilliseconds <= 0
            ? null
            : (playbackPosition.inMilliseconds / total.inMilliseconds)
                .clamp(0.0, 1.0);
        if (!kMobile) {
          return DesktopRecorderStrip(
            recording: recording,
            time: time,
            wave: LiveRecordingWave(
                buffer: controller.waveform, live: recording, progress: progress),
            playing: controller.isPlaying,
            onDiscard: () => unawaited(controller.discard()),
            onPlay: () => unawaited(controller.togglePlayback()),
            onStop: () => unawaited(controller.stop()),
            onSend: sending ? () {} : onSend,
            onMore: reviewing ? onMore : null,
          );
        }
        Widget btn(String icon, String tip, VoidCallback onTap,
                {Color? color}) =>
            Semantics(
                button: true,
                label: tip,
                child: ComposerIconButton(icon,
                    tooltip: tip, onTap: onTap, color: color));
        Widget slot(Widget w) => SizedBox(height: 36, child: Center(child: w));
        return Glass(
          radius: BorderRadius.circular(ComposerCard.radius),
          tint: AppColors.surface1.withValues(alpha: 0.78),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(children: [
              if (reviewing) ...[
                slot(btn('trash', 'Discard',
                    () => unawaited(controller.discard()))),
                slot(btn(
                    controller.isPlaying ? 'pause' : 'play',
                    controller.isPlaying ? 'Pause' : 'Play',
                    () => unawaited(controller.togglePlayback()),
                    color: AppColors.fg1)),
              ] else
                slot(Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: StatusDot(
                      status: 'running', size: 8, color: AppColors.danger),
                )),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: LiveRecordingWave(
                      buffer: controller.waveform,
                      live: recording,
                      progress: progress),
                ),
              ),
              const SizedBox(width: 10),
              Text(time,
                  style: sans(13,
                      tabular: true,
                      color: reviewing ? AppColors.fg3 : AppColors.danger)),
              const SizedBox(width: 6),
              if (recording)
                slot(Semantics(
                  button: true,
                  label: 'Stop',
                  child: ComposerSendButton(
                      enabled: true,
                      stop: true,
                      onTap: () => unawaited(controller.stop())),
                ))
              else ...[
                if (onMore != null) ...[
                  slot(btn('mic', 'Record more', onMore!)),
                  const SizedBox(width: 4),
                ],
                slot(Semantics(
                  button: true,
                  label: 'Send voice note',
                  child: ComposerSendButton(
                      enabled: !sending,
                      sending: sending,
                      onTap: sending ? null : onSend),
                )),
              ],
            ]),
          ),
        );
      },
    );
  }
}
