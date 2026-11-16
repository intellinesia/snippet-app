import 'dart:async';

/// Local "the user has seen this session" pings.
///
/// `POST /session/seen` has no device event, so session lists would keep a
/// Came back row until the next sessions fetch. The session screen pings here
/// the moment it marks a session seen and shells patch their cached rows
/// optimistically; the daemon's next payload stays authoritative.
final _seen = StreamController<String>.broadcast();

Stream<String> get sessionSeenPings => _seen.stream;

void pingSessionSeen(String sessionId) {
  if (!_seen.isClosed) _seen.add(sessionId);
}
