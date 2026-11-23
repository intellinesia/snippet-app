import 'package:flutter/material.dart';

import '../api.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// One bullet of a memory index: a linked topic file or a short note.
class MemoryEntry {
  MemoryEntry({required this.text, this.file, this.added});
  final String text;
  final String? file;
  final String? added;

  /// What the daemon matches on when editing or forgetting this entry.
  String get match => file != null
      ? '[[$file]]'
      : (text.length > 80 ? text.substring(0, 80) : text);
}

List<MemoryEntry> parseMemoryEntries(String md) {
  final out = <MemoryEntry>[];
  final link = RegExp(r'^\[\[([^\]]+)\]\]\s*[—–-]?\s*(.*)$');
  final meta = RegExp(r'\s*\[(?:source|added)[^\]\n]*\]');
  final added = RegExp(r'added: (\d{4}-\d{2}-\d{2})');
  for (final raw in md.split('\n')) {
    final l = raw.trim();
    if (!l.startsWith('- ')) continue;
    final body = l.substring(2).trim();
    final m = link.firstMatch(body);
    if (m != null) {
      out.add(MemoryEntry(text: m[2]!.trim(), file: m[1]!.trim()));
      continue;
    }
    out.add(MemoryEntry(
        text: body.replaceAll(meta, '').trim(),
        added: added.firstMatch(body)?[1]));
  }
  return out;
}

String memoryDay(String? ymd) {
  final d = ymd == null ? null : DateTime.tryParse(ymd);
  if (d == null) return '';
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  return '${m[d.month - 1]} ${d.day}';
}

bool memoryEntryMatches(MemoryEntry e, String query) {
  final q = query.trim().toLowerCase();
  return q.isEmpty ||
      e.text.toLowerCase().contains(q) ||
      (e.file ?? '').toLowerCase().contains(q);
}

/// Removes an entry from a scope's index after confirming. True when removed.
Future<bool> forgetMemoryEntry(BuildContext context, DaemonClient client,
    String scope, MemoryEntry e) async {
  final ok = await confirmAction(context,
      title: 'Forget this?',
      body: e.file != null
          ? 'Removes ${e.file} from the memory index. The file itself stays.'
          : e.text,
      confirmLabel: 'Forget');
  if (!ok) return false;
  try {
    await client.editMemoryEntry(scope, e.match);
    return true;
  } catch (err) {
    if (context.mounted) toast(context, '$err', danger: true);
    return false;
  }
}

/// Rewrites a note after prompting. Returns the new text, or null if unchanged.
Future<String?> editMemoryNote(BuildContext context, DaemonClient client,
    String scope, MemoryEntry e) async {
  final next = await promptText(context,
      title: 'Edit memory', initial: e.text, minLines: 3, maxLines: 8);
  if (next == null || next.trim().isEmpty || next.trim() == e.text) return null;
  final text = next.trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
  try {
    await client.editMemoryEntry(scope, e.match, entry: text);
    return text;
  } catch (err) {
    if (context.mounted) toast(context, '$err', danger: true);
    return null;
  }
}

class MemorySearchField extends StatelessWidget {
  const MemorySearchField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kMobile ? 40 : 32,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.line),
      ),
      padding: EdgeInsets.symmetric(horizontal: S.of(10)),
      child: Row(children: [
        AppIcon('search', size: 13, color: AppColors.fg4),
        SizedBox(width: S.s8),
        Expanded(
          child: TextField(
            controller: controller,
            style: sans(13, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search memory',
              hintStyle: sans(13, color: AppColors.fg4),
            ),
          ),
        ),
      ]),
    );
  }
}

class MemoryEntryCard extends StatelessWidget {
  const MemoryEntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.wide = false,
    this.selected = false,
  });
  final MemoryEntry entry;
  final VoidCallback onTap;
  final bool wide;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final sel = wide && selected;
    final when = memoryDay(e.added);
    return Padding(
      padding: EdgeInsets.only(bottom: S.s8),
      child: Material(
        color: sel ? AppColors.surface2 : AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.card),
          side: BorderSide(color: sel ? Colors.transparent : AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.card),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.of(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (e.file != null || when.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: S.of(5)),
                  child: Row(children: [
                    if (e.file != null)
                      Expanded(
                        child: Text('${e.file}.md',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(12, color: AppColors.fg2)),
                      )
                    else
                      const Spacer(),
                    if (when.isNotEmpty)
                      Text(when, style: sans(11, color: AppColors.fg4)),
                    if (e.file != null)
                      AppIcon('chevron-right', size: 12, color: AppColors.fg3),
                  ]),
                ),
              Text(e.text,
                  maxLines: wide ? 3 : 6,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, height: 1.5, color: AppColors.fg3)),
            ]),
          ),
        ),
      ),
    );
  }
}

class MemoryAction extends StatelessWidget {
  const MemoryAction(this.label, this.onTap, {super.key, this.danger = false});
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
        side: BorderSide(
            color: danger
                ? AppColors.danger.withValues(alpha: 0.3)
                : Colors.transparent));
    return Padding(
      padding: EdgeInsets.only(left: S.s6),
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: SizedBox(
          // Phone touch target is 44 around a 32px pill.
          height: kMobile ? 44 : 28,
          child: Center(
            child: Material(
              color: danger ? Colors.transparent : AppColors.surface2,
              shape: shape,
              child: Container(
                height: kMobile ? 32 : 28,
                padding: EdgeInsets.symmetric(horizontal: S.s12),
                alignment: Alignment.center,
                child: Text(label,
                    style: sans(12,
                        color: danger ? AppColors.danger : AppColors.fg2)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
