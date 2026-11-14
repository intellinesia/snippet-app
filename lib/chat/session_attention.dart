import '../api.dart';
import '../models.dart';

/// What a session is waiting on right now, read from one shared sessions
/// fetch so a thread full of cards costs a single request.
class SessionAttentionProbe {
  static final _cache = <DaemonClient, (DateTime, Future<List<SessionInfo>>)>{};
  static const _ttl = Duration(seconds: 15);

  static Future<({bool found, Map<String, dynamic>? attention})> of(
      DaemonClient client, String session) async {
    final now = DateTime.now();
    final hit = _cache[client];
    final Future<List<SessionInfo>> list;
    if (hit != null && now.difference(hit.$1) < _ttl) {
      list = hit.$2;
    } else {
      list = client.sessions();
      _cache[client] = (now, list);
    }
    try {
      for (final s in await list) {
        if (s.id == session) return (found: true, attention: s.attention);
      }
    } catch (_) {
      _cache.remove(client);
    }
    return (found: false, attention: null);
  }

  /// True when the session is known and no longer waiting on this request.
  static Future<bool> isOutdated(DaemonClient client,
      {required String session, required String type, String id = ''}) async {
    if (session.isEmpty) return false;
    final r = await of(client, session);
    if (!r.found) return false;
    final a = r.attention;
    if (a == null || '${a['type'] ?? ''}' != type) return true;
    return id.isNotEmpty && '${a['id'] ?? ''}' != id;
  }
}
