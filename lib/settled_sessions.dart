import 'models.dart';

const int settledRetentionDays = 15;

({List<SessionInfo> main, List<SessionInfo> settled}) splitSettled(
    Iterable<SessionInfo> sessions) {
  final main = <SessionInfo>[];
  final settled = <SessionInfo>[];
  for (final s in sessions) {
    (s.settled ? settled : main).add(s);
  }
  settled.sort((a, b) =>
      (b.settledAt ?? b.lastActive).compareTo(a.settledAt ?? a.lastActive));
  return (main: main, settled: settled);
}

/// Whole days left before auto-delete, or null when the settle time is unknown.
int? settledDaysLeft(SessionInfo s, {int? nowSecs}) {
  final at = s.settledAt;
  if (at == null) return null;
  final now = nowSecs ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final left = settledRetentionDays * 86400 - (now - at);
  if (left <= 0) return 0;
  return (left + 86399) ~/ 86400;
}
