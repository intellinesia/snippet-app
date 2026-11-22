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
import '../diagnostics.dart';
import '../media_views.dart';
import '../platform.dart';
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
  final Future<void> Function(Uint8List bytes, String name)? onConfirmTake;
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
  int _take = 0;
  bool _confirming = false;

  /// The take's upload, started as soon as recording stops so Send is instant.
  Future<String>? _takeUpload;
  String? _takeName;

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
  bool get isConfirming => _confirming;
  String? get takeName => _takeName;

  /// The upload begun when the take stopped, so a leaving screen can keep it.
  Future<String>? get takeUpload => isReviewing ? _takeUpload : null;

  /// Upload [bytes] as [name], reusing the upload begun at stop for this take.
  Future<String> uploadTake(Uint8List bytes, String name) async {
    final early = name == _takeName ? _takeUpload : null;
    if (early != null) {
      try {
        return await Diag.span('upload (started early)', () => early);
      } catch (_) {}
    }
    return Diag.span('upload ${bytes.length}B',
        () => client.uploadFile(bytes, name: name));
  }

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
      if (state == PlayerState.completed) _playbackPosition = _playbackDuration;
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
          // Speech: 32 kbps at 16 kHz is clear and a third of the upload.
          bitRate: kMobile ? 32000 : 96000,
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
    final take = _take;
    _isRecording = false;
    _notify();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final stoppedPath =
          await Diag.span('recorder.stop', () => _recorder.stop());
      final path = stoppedPath ?? _recordingPath;
      if (path == null) {
        _toast('No recording was captured.');
        return;
      }
      final bytes = await _waitForRecordingFile(path);
      // Discarded while the encoder finished: do not bring the take back.
      if (take != _take) return;
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
      _startTakeUpload(bytes);
    } catch (e) {
      await discard();
      _toast('Could not finish recording: $e', danger: true);
    }
  }

  void _startTakeUpload(Uint8List bytes) {
    final name =
        'voice-${DateTime.now().microsecondsSinceEpoch}.$voiceNoteExtension';
    _takeName = name;
    final upload = client.uploadFile(bytes, name: name);
    upload.ignore();
    _takeUpload = upload;
    Diag.crumb('take upload started ${bytes.length}B');
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
    _take++;
    _takeUpload = null;
    _takeName = null;
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

  /// Hand the take to [accept] (or [onConfirmTake]) with its upload name. The
  /// pill clears at once so a second tap cannot race; a failure restores it.
  Future<bool> confirmTake([
    Future<void> Function(Uint8List bytes, String name)? accept,
  ]) async {
    final fn = accept ?? onConfirmTake;
    if (fn == null || _isRecording || _confirming) return false;
    final path = _recordingPath;
    var bytes = _recordingBytes;
    if (path == null && bytes == null) return false;
    _confirming = true;
    _recordingPath = null;
    _recordingBytes = null;
    _notify();
    try {
      if ((bytes == null || bytes.isEmpty) && path != null) {
        bytes = await _waitForRecordingFile(path);
      }
      if (bytes == null || bytes.isEmpty) {
        await discard();
        _toast('The recording was empty.');
        return false;
      }
      final name = _takeName ??
          'voice-${DateTime.now().microsecondsSinceEpoch}.$voiceNoteExtension';
      await Diag.span('recorder.ingest', () => fn(bytes!, name));
      _recordingPath = path;
      await discard();
      return true;
    } catch (e) {
      _recordingPath = path;
      _recordingBytes = bytes;
      _notify();
      _toast('Could not attach recording: $e', danger: true);
      return false;
    } finally {
      _confirming = false;
    }
  }

  Future<void> recordMore([
    Future<void> Function(Uint8List bytes, String name)? accept,
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
        await _audioPlayer.play(DeviceFileSource(path),
            position: _playbackPosition >= _playbackDuration
                ? Duration.zero
                : _playbackPosition);
      }
    } catch (e) {
      _toast('Could not play preview: $e', danger: true);
    }
  }

  Future<void> seek(double fraction) async {
    final path = _recordingPath;
    final total = _playbackDuration > Duration.zero
        ? _playbackDuration
        : _recordingElapsed;
    if (path == null || total <= Duration.zero) return;
    final target =
        Duration(milliseconds: (total.inMilliseconds * fraction).round());
    try {
      final player = _audioPlayer;
      if (player.state == PlayerState.stopped ||
          player.state == PlayerState.completed) {
        await player.setSource(DeviceFileSource(path));
      }
      await player.seek(target);
      _playbackPosition = target;
      _notify();
    } catch (_) {}
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

/// The one recorder for every chat: the voice pill on phones, the voice card
/// on desktop, both driven by a [VoiceNoteController].
class VoiceNoteRecorderStrip extends StatelessWidget {
  const VoiceNoteRecorderStrip({
    super.key,
    required this.controller,
    required this.onSend,
    this.sending = false,
    this.onMore,
    this.recipient = '',
  });

  final VoiceNoteController controller;
  final VoidCallback onSend;
  final bool sending;
  final VoidCallback? onMore;

  /// Who the note is for, named in the desktop card's label.
  final String recipient;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final recording = controller.isRecording;
        final reviewing = controller.isReviewing;
        final position = controller.playbackPosition;
        final total = controller.playbackDuration > Duration.zero
            ? controller.playbackDuration
            : controller.elapsed;
        final showPosition =
            reviewing && (controller.isPlaying || position > Duration.zero);
        final fmt = VoiceNoteController.formatDuration;
        final time = reviewing
            ? '${fmt(showPosition ? position : Duration.zero)} / ${fmt(total)}'
            : fmt(controller.elapsed);
        final progress = !reviewing || total.inMilliseconds <= 0
            ? null
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        final wave = LiveRecordingWave(
            buffer: controller.waveform, live: recording, progress: progress);
        void discard() => unawaited(controller.discard());
        void play() => unawaited(controller.togglePlayback());
        void stop() => unawaited(controller.stop());
        final more = reviewing ? onMore : null;
        if (!kMobile) {
          return DeskVoiceCard(
            recording: recording,
            sending: sending,
            playing: controller.isPlaying,
            label: recording
                ? (recipient.isEmpty
                    ? 'Recording a voice note'
                    : 'Recording a voice note for $recipient')
                : 'Voice note ready to send',
            time: time,
            wave: wave,
            onDiscard: discard,
            onPlay: play,
            onStop: stop,
            onSend: onSend,
            onMore: more,
          );
        }
        return ComposerVoicePill(
          recording: recording,
          sending: sending,
          time: time,
          wave: wave,
          playing: controller.isPlaying,
          onDiscard: discard,
          onPlay: play,
          onStop: stop,
          onSend: onSend,
          onSeek: reviewing ? (f) => unawaited(controller.seek(f)) : null,
          onMore: more,
        );
      },
    );
  }
}
