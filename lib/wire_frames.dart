import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int _kPackBase = 0x80;
const int _kPackMask = 0xF8;
const int _kPackFinal = 0x01;
const int _kPackGzip = 0x02;
const int _kPackStream = 0x04;

bool isPackedFrame(List<int> bytes) =>
    bytes.isNotEmpty && (bytes[0] & _kPackMask) == _kPackBase;

class PackedFrame {
  const PackedFrame(this.bytes, {required this.gzip, required this.stream});
  final Uint8List bytes;
  final bool gzip;
  final bool stream;
  int get length => bytes.length;
}

class PackedFrameAssembler {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  PackedFrame? add(List<int> message) {
    final flags = message[0];
    _buffer.add(Uint8List.sublistView(
        message is Uint8List ? message : Uint8List.fromList(message), 1));
    if (flags & _kPackFinal == 0) return null;
    return PackedFrame(_buffer.takeBytes(),
        gzip: flags & _kPackGzip != 0, stream: flags & _kPackStream != 0);
  }

  void reset() => _buffer.clear();
}

class StreamInflater {
  RawZLibFilter _filter = RawZLibFilter.inflateFilter(raw: true);

  Uint8List inflate(Uint8List data) {
    _filter.process(data, 0, data.length);
    final out = BytesBuilder(copy: false);
    List<int>? chunk;
    while ((chunk = _filter.processed(flush: false)) != null) {
      out.add(chunk!);
    }
    return out.takeBytes();
  }

  void reset() => _filter = RawZLibFilter.inflateFilter(raw: true);
}

Object? decodePackedFrame(PackedFrame frame) {
  final raw = frame.gzip ? gzip.decode(frame.bytes) : frame.bytes;
  return jsonDecode(utf8.decode(raw, allowMalformed: true));
}

Object? decodeJsonBytes(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes, allowMalformed: true));
