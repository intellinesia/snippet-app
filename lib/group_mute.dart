import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Groups whose @mentions should not notify. Local to this device: the group
/// still shows and counts unread in the sidebar.
const _key = 'muted_groups';

final ValueNotifier<Set<String>> mutedGroups = ValueNotifier(const {});

Future<Set<String>> loadMutedGroups() async {
  final sp = await SharedPreferences.getInstance();
  // Another isolate (the Android background watcher) may have written it.
  await sp.reload();
  final s = (sp.getStringList(_key) ?? const <String>[]).toSet();
  mutedGroups.value = s;
  return s;
}

Future<void> setGroupMuted(String id, bool on) async {
  final s = {...await loadMutedGroups()};
  on ? s.add(id) : s.remove(id);
  final sp = await SharedPreferences.getInstance();
  await sp.setStringList(_key, s.toList());
  mutedGroups.value = s;
}
