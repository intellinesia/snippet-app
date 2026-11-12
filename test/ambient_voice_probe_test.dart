import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/ambient/sink.dart';
import 'package:snippet/ambient/stream.dart';
import 'package:snippet/ambient/voice.dart';

void main() {
  test('probe go:false resumes a locally paused stream', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.send({'t': 'tts_start', 'turn': 1});
      rig.flush(async);
      rig.voice.localSpeech(true, canPause: true);
      rig.flush(async);
      rig.send({'t': 'probe', 'phase': 'begin', 'turn': 1, 'seq': 1});
      rig.voice.localSpeech(false);
      rig.flush(async);

      rig.elapse(async, const Duration(milliseconds: 900));
      expect(rig.sink.resumes, 0);

      rig.send({
        't': 'probe',
        'phase': 'verdict',
        'go': false,
        'turn': 1,
        'seq': 1,
      });
      rig.flush(async);
      expect(rig.sink.resumes, 1);
      rig.dispose(async);
    });
  });

  test('probe go:true stays paused until the safety resume', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.send({'t': 'tts_start', 'turn': 1});
      rig.flush(async);
      rig.voice.localSpeech(true, canPause: true);
      rig.flush(async);
      rig.send({'t': 'probe', 'phase': 'begin', 'turn': 1, 'seq': 1});
      rig.voice.localSpeech(false);
      rig.flush(async);

      rig.elapse(async, const Duration(milliseconds: 900));
      expect(rig.sink.resumes, 0);
      rig.send({
        't': 'probe',
        'phase': 'verdict',
        'go': true,
        'turn': 1,
        'seq': 1,
      });
      rig.flush(async);
      expect(rig.sink.resumes, 0);

      rig.elapse(async, const Duration(milliseconds: 600));
      expect(rig.sink.resumes, 1);
      rig.dispose(async);
    });
  });

  test('probe without a verdict resumes at the probe limit', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.send({'t': 'tts_start', 'turn': 1});
      rig.flush(async);
      rig.voice.localSpeech(true, canPause: true);
      rig.flush(async);
      rig.send({'t': 'probe', 'phase': 'begin', 'turn': 1, 'seq': 1});
      rig.voice.localSpeech(false);
      rig.flush(async);

      rig.elapse(async, const Duration(milliseconds: 900));
      expect(rig.sink.resumes, 0);
      rig.elapse(async, const Duration(milliseconds: 500));
      expect(rig.sink.resumes, 0);
      rig.elapse(async, const Duration(milliseconds: 100));
      expect(rig.sink.resumes, 1);
      rig.dispose(async);
    });
  });

  test('tts_stop clears the in-flight probe', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.send({'t': 'tts_start', 'turn': 1});
      rig.flush(async);
      rig.voice.localSpeech(true, canPause: true);
      rig.flush(async);
      rig.send({'t': 'probe', 'phase': 'begin', 'turn': 1, 'seq': 1});
      rig.voice.localSpeech(false);
      rig.flush(async);

      rig.elapse(async, const Duration(milliseconds: 900));
      rig.send({'t': 'tts_stop', 'turn': 1});
      rig.flush(async);
      expect(rig.sink.stops, 1);

      rig.elapse(async, const Duration(seconds: 1));
      expect(rig.sink.resumes, 0);
      rig.dispose(async);
    });
  });
}

class _Rig {
  _Rig() {
    voice.attach(stream);
  }

  final _FakeSink sink = _FakeSink();
  final AmbientStream stream = AmbientStream(
    baseUrl: 'http://127.0.0.1:9',
    token: 'tok',
    device: 'dev',
  );
  late final AmbientVoice voice = AmbientVoice(
    baseUrl: 'http://127.0.0.1:9',
    token: 'tok',
    device: 'dev',
    sink: sink,
  );

  void send(Map<String, dynamic> msg) => stream.onTts!(msg);

  void flush(FakeAsync async) => async.flushMicrotasks();

  void elapse(FakeAsync async, Duration duration) {
    async.elapse(duration);
    async.flushMicrotasks();
  }

  void dispose(FakeAsync async) {
    voice.dispose();
    async.flushMicrotasks();
  }
}

class _FakeSink implements AmbientSink {
  int pauses = 0;
  int resumes = 0;
  int stops = 0;
  int volumes = 0;

  @override
  Future<void> warm() async {}

  @override
  Future<void> enqueue(int turn, int seq, Uint8List pcm, int silenceMs) async {}

  @override
  Future<void> enqueueFrame(int turn, Uint8List pcm) async {}

  @override
  Future<Map<String, dynamic>> position() async => const {};

  @override
  Future<Map<String, dynamic>> streamPosition() async => const {
    'turns': <int, int>{},
  };

  @override
  Future<Map<String, dynamic>> stopStream(int turn, {int fadeMs = 25}) async {
    stops++;
    return const {};
  }

  @override
  Future<void> cancelAfter(int turn, int seq, {int fadeMs = 50}) async {}

  @override
  Future<void> volume(double volume) async {
    volumes++;
  }

  @override
  Future<void> pauseTts() async {
    pauses++;
  }

  @override
  Future<void> resumeTts() async {
    resumes++;
  }

  @override
  Future<Map<String, dynamic>> stop() async => const {};

  @override
  Future<bool> mediaActive() async => false;

  @override
  Future<bool> inCall() async => false;

  @override
  Future<bool> hasExternal() async => false;

  @override
  Future<int> builtinMicId() async => -1;

  @override
  Future<bool> prepare() async => false;

  @override
  Future<void> leave() async {}
}
