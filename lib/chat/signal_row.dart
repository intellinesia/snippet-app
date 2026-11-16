// One grammar for the quiet rows in a transcript: watches, wakes, limits,
// errors, coordination envelopes. A dot (a glyph only for trouble), one sentence, an optional
// time, one optional action and a sub line.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart' show DaemonClient;
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

enum SignalTone { neutral, ok, run, danger, accent }

Color signalColor(SignalTone tone) => switch (tone) {
      SignalTone.ok => AppColors.ok,
      SignalTone.run => AppColors.run,
      SignalTone.danger => AppColors.danger,
      SignalTone.accent => AppColors.accent,
      SignalTone.neutral => AppColors.fg3,
    };

/// Splits `Some **name** here` into spans: names a step brighter and heavier.
List<InlineSpan> signalSpans(String text, TextStyle base) {
  final out = <InlineSpan>[];
  final parts = text.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    out.add(TextSpan(
        text: parts[i],
        style: i.isOdd
            ? base.copyWith(
                color: AppColors.fg2, fontWeight: weightFor(W.label))
            : base));
  }
  return out;
}

/// The text with its `**` markers removed.
String signalPlain(String text) => text.replaceAll('**', '');

class SignalRow extends StatelessWidget {
  const SignalRow({
    super.key,
    required this.text,
    this.icon,
    this.leading,
    this.tone = SignalTone.neutral,
    this.time,
    this.action,
    this.onAction,
    this.actionTone,
    this.sub,
    this.onTap,
    this.center = false,
    this.maxLines = 2,
  });

  /// The sentence; `**name**` marks a name.
  final String text;
  final String? icon;

  /// Replaces the glyph tile, e.g. a sender's character.
  final Widget? leading;
  final SignalTone tone;
  final String? time;
  final String? action;
  final VoidCallback? onAction;
  final SignalTone? actionTone;
  final String? sub;
  final VoidCallback? onTap;
  final bool center;
  final int maxLines;

  static const tile = 20.0;

  Widget _glyph() {
    if (leading != null) {
      return SizedBox.square(dimension: tile, child: Center(child: leading));
    }
    final c = signalColor(tone);
    // Only trouble earns a glyph; routine signals get a quiet dot.
    if (tone == SignalTone.danger) {
      return SizedBox.square(
          dimension: tile,
          child: Center(child: AppIcon(icon ?? 'alert-triangle', size: 14, color: c)));
    }
    final quiet = tone == SignalTone.neutral;
    return SizedBox.square(
      dimension: tile,
      child: Center(
        child: Container(
          width: quiet ? 5 : 6,
          height: quiet ? 5 : 6,
          decoration: BoxDecoration(
              color: quiet ? AppColors.fg4 : c, shape: BoxShape.circle),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final base = sans(kMobile ? 14 : 13, height: 1.35, color: AppColors.fg3);
    final sentence = Text.rich(
      TextSpan(children: signalSpans(text, base)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
    final subLine = sub == null || sub!.trim().isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(sub!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(12, height: 1.35, color: AppColors.fg4)),
          );
    final body = Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [sentence, if (subLine != null) subLine],
    );
    final pillTone = actionTone ?? SignalTone.accent;
    final pillColor = signalColor(pillTone);
    final row = Row(
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _glyph(),
        SizedBox(width: S.s8),
        center ? Flexible(child: body) : Expanded(child: body),
        if (time != null && time!.isNotEmpty) ...[
          SizedBox(width: S.s8),
          Text(time!, style: mono(12, color: AppColors.fg4)),
        ],
        if (action != null) ...[
          SizedBox(width: S.s8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: SizedBox(
              height: kMobile ? 44 : 28,
              child: Center(
                child: Container(
                  height: 26,
                  padding: EdgeInsets.symmetric(horizontal: S.s8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pillColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(action!,
                      style: sans(12, weight: W.label, color: pillColor)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    final padded = Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 28 : 24),
        child: center ? Center(child: row) : row,
      ),
    );
    if (onTap == null) return padded;
    return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onTap, child: padded);
  }
}

// ---------------------------------------------------------------------------
// Names: agents are people in the thread, never ids.
// ---------------------------------------------------------------------------

/// Display names the app has learned from the coordination agent list.
final agentNames = ValueNotifier<Map<String, String>>(const {});

String _titleCaseWords(String id) => id
    .split(RegExp(r'[-_\s]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// A person's name for an agent id: the coordination display name when known,
/// else the id title-cased (`mission-control` is Mission Control).
String agentDisplayName(String raw, [Map<String, String>? known]) {
  var id = raw.trim();
  if (id.startsWith('agent:')) id = id.substring(6);
  if (id.isEmpty) return 'An agent';
  if (id == 'human' || id == 'user') return 'You';
  final map = known ?? agentNames.value;
  final hit = map[id];
  if (hit != null && hit.trim().isNotEmpty) return hit.trim();
  if (id == 'mission-control' || id == 'mission_control') {
    return 'Mission Control';
  }
  return _titleCaseWords(id);
}

final _namesLoadedFor = <DaemonClient, DateTime>{};

/// Learns display names once a minute per client; failures leave title case.
void ensureAgentNames(DaemonClient client) {
  final at = _namesLoadedFor[client];
  if (at != null && DateTime.now().difference(at).inSeconds < 60) return;
  _namesLoadedFor[client] = DateTime.now();
  client.coordinationAgents().then((agents) {
    final next = Map<String, String>.of(agentNames.value);
    for (final a in agents) {
      if (a.displayName.trim().isNotEmpty) next[a.id] = a.displayName.trim();
    }
    if (!mapEquals(next, agentNames.value)) agentNames.value = next;
  }).catchError((_) {});
}

/// `claude-opus` reads Claude Opus; `gpt-5` reads GPT 5.
String prettyProfile(String raw) {
  final id = raw.trim();
  if (id.isEmpty) return 'the model';
  return id
      .split(RegExp(r'[-_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => switch (w.toLowerCase()) {
            'gpt' || 'ai' || 'cli' => w.toUpperCase(),
            _ => '${w[0].toUpperCase()}${w.substring(1)}',
          })
      .join(' ');
}

/// Rebuilds when the display names arrive.
class AgentNamesBuilder extends StatelessWidget {
  const AgentNamesBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, Map<String, String> names)
      builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
      valueListenable: agentNames, builder: (c, m, _) => builder(c, m));
}

/// HH:MM from an event time: unix seconds or milliseconds, or an ISO string.
String? formatEventTime(dynamic raw) {
  DateTime? dt;
  if (raw is num && raw > 0) {
    final ms = raw > 100000000000 ? raw.toInt() : (raw * 1000).toInt();
    dt = DateTime.fromMillisecondsSinceEpoch(ms);
  } else if (raw is String && raw.isNotEmpty) {
    dt = DateTime.tryParse(raw)?.toLocal();
  }
  if (dt == null) return null;
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Coordination envelopes: `[tag]` + `key: value` lines + `[/tag]`.
// ---------------------------------------------------------------------------

class CoordinationEnvelope {
  const CoordinationEnvelope(this.tag, this.fields);
  final String tag;
  final Map<String, String> fields;

  String field(String name) => fields[name]?.trim() ?? '';
}

CoordinationEnvelope? parseCoordinationEnvelope(String body) {
  final t = body.trim();
  final open = RegExp(r'^\[([a-z_]+)\]').firstMatch(t);
  if (open == null) return null;
  final tag = open.group(1)!;
  final close = t.indexOf('[/$tag]');
  final inner =
      t.substring(open.end, close > open.end ? close : t.length).trim();
  final fields = <String, String>{};
  String? last;
  for (final line in inner.split('\n')) {
    final m = RegExp(r'^([a-z_]+):[ \t]*(.*)$').firstMatch(line);
    if (m != null) {
      last = m.group(1);
      fields[last!] = m.group(2)!;
    } else if (last != null && line.trim().isNotEmpty) {
      fields[last] = '${fields[last]}\n${line.trim()}';
    }
  }
  return CoordinationEnvelope(tag, fields);
}

class EnvelopeSignal {
  const EnvelopeSignal(this.icon, this.tone, this.text, {this.sub});
  final String icon;
  final SignalTone tone;
  final String text;
  final String? sub;
}

String _firstLine(String s, [int max = 140]) {
  final line = s.trim().split('\n').first.trim();
  return line.length <= max ? line : '${line.substring(0, max - 1)}…';
}

/// One sentence for an envelope, naming [sender] and the task it concerns.
EnvelopeSignal envelopeSignal(CoordinationEnvelope env, String sender) {
  final who = '**$sender**';
  final title = env.field('title').isNotEmpty
      ? env.field('title')
      : env.field('task_title');
  final subject = title.isEmpty ? 'a task' : '**$title**';
  switch (env.tag) {
    case 'task_cancelled':
      return EnvelopeSignal('x', SignalTone.danger, '$who cancelled $subject',
          sub: _firstLine(env.field('reason')));
    case 'task_dispatched':
    case 'mission_control_task':
      return EnvelopeSignal('send', SignalTone.accent, '$who sent $subject',
          sub: _firstLine(env.field('scope')));
    case 'task_offer':
      return EnvelopeSignal('send', SignalTone.accent, '$who offered $subject');
    case 'review_request':
      return EnvelopeSignal(
          'eye', SignalTone.accent, '$who asked for a review of $subject');
    case 'review_findings':
      return EnvelopeSignal(
          'check', SignalTone.ok, '$who sent review findings on $subject');
    case 'mission_task_report':
    case 'task_report':
      return EnvelopeSignal('check', SignalTone.ok, '$who reported on $subject',
          sub: _firstLine(env.field('summary')));
    case 'lane_report':
      return EnvelopeSignal(
          'layers', SignalTone.neutral, '$who sent a lane report',
          sub: _firstLine(env.field('summary')));
    case 'owed_reply':
      return EnvelopeSignal(
          'clock', SignalTone.run, '$who is waiting on a reply');
    case 'task_plan':
      return EnvelopeSignal(
          'list', SignalTone.neutral, '$who shared a plan for $subject');
  }
  final what = env.tag.replaceAll('_', ' ');
  return EnvelopeSignal('message', SignalTone.neutral, '$who sent a $what',
      sub: _firstLine(env.field('body').isNotEmpty
          ? env.field('body')
          : env.field('title')));
}

/// The full text behind a signal row, in a sheet.
Future<void> showSignalDetails(BuildContext context,
    {required String title, required String body}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface1,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(S.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: sans(16, weight: W.strong, color: AppColors.fg1)),
              SizedBox(height: S.s8),
              SelectableText(body,
                  style: codeMono(13, height: 1.5, color: AppColors.fg2)),
            ],
          ),
        ),
      ),
    ),
  );
}
