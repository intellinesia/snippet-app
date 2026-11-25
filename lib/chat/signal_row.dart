// One grammar for the quiet rows in a transcript: watches, wakes, limits,
// errors, coordination envelopes. A dot (a glyph only for trouble), one sentence, an optional
// time, one optional action and a sub line.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart' show DaemonClient;
import '../models.dart' show InferenceProfile;
import '../envelope.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../tap_detector.dart';

enum SignalTone { neutral, ok, run, danger, accent }

/// Line tier: neutral text. No green ticks, no red; amber is kept for the
/// hand that means "needs you".
Color signalColor(SignalTone tone) => switch (tone) {
      SignalTone.danger => AppColors.fg1,
      _ => AppColors.fg2,
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
    final trouble = tone == SignalTone.danger;
    return SizedBox.square(
      dimension: tile,
      child: Center(
          child: AppIcon(trouble ? (icon ?? 'alert-triangle') : (icon ?? 'info'),
              size: kMobile ? 16 : 14, color: AppColors.fg2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final trouble = tone == SignalTone.danger;
    final base = sans(kMobile ? 14 : 13,
        height: 1.35,
        weight: trouble ? FontWeight.w500 : null,
        color: trouble ? AppColors.fg1 : AppColors.fg2);
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
                style: sans(12, height: 1.35, color: AppColors.fg3)),
          );
    final body = Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [sentence, if (subLine != null) subLine],
    );
    final row = Row(
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _glyph(),
        SizedBox(width: S.s8),
        center ? Flexible(child: body) : Expanded(child: body),
        if (time != null && time!.isNotEmpty) ...[
          SizedBox(width: S.s8),
          Text(time!, style: sans(12, color: AppColors.fg3)),
        ],
        if (action != null) ...[
          SizedBox(width: S.s8),
          TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: SizedBox(
              height: kMobile ? 44 : 28,
              child: Center(
                child: Text(action!,
                    style: sans(12, weight: FontWeight.w500, color: AppColors.fg1)),
              ),
            ),
          ),
        ],
      ],
    );
    final padded = ConstrainedBox(
      constraints: BoxConstraints(minHeight: kMobile ? 48 : 28),
      child: Align(
          alignment: center ? Alignment.center : Alignment.centerLeft,
          child: row),
    );
    if (onTap == null) return padded;
    return _LineTarget(onTap: onTap!, child: padded);
  }
}

/// The line is the target: hover is one surface step, radius 8.
class _LineTarget extends StatefulWidget {
  const _LineTarget({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_LineTarget> createState() => _LineTargetState();
}

class _LineTargetState extends State<_LineTarget> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
                color: _hover ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(8)),
            child: widget.child,
          ),
        ),
      );
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
/// else the id title-cased (`lead` is Lead).
String agentDisplayName(String raw, [Map<String, String>? known]) {
  var id = raw.trim();
  if (id.startsWith('agent:')) id = id.substring(6);
  if (id.isEmpty) return 'An agent';
  if (id == 'human' || id == 'user') return 'You';
  final map = known ?? agentNames.value;
  final hit = map[id];
  if (hit != null && hit.trim().isNotEmpty) return hit.trim();
  if (id == 'lead') {
    return 'Lead';
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

String prettyProvider(String raw) {
  final p = raw.trim().toLowerCase();
  return switch (p) {
    'claude-code' => 'Claude Code',
    'anthropic' || 'anthropic-compatible' => 'Anthropic',
    'openai' || 'openai-compatible' => 'OpenAI',
    'chatgpt' => 'ChatGPT',
    'codex' => 'Codex',
    'gemini' || 'google' => 'Gemini',
    'antigravity' => 'Antigravity',
    'xai' => 'xAI',
    'openrouter' => 'OpenRouter',
    'opencode' || 'opencode-zen' || 'opencode-go' => 'OpenCode',
    'devin' => 'Devin',
    '' => '',
    _ => prettyProfile(raw),
  };
}

/// Model label (profile name as fallback) and provider key for an agent's
/// profile, so every surface reads the same.
({String label, String? provider}) profileMeta(
    Map<String, InferenceProfile> profiles, String? key) {
  final k = (key ?? '').trim();
  if (k.isEmpty) return (label: '', provider: null);
  final p = profiles[k];
  final model = (p?.model ?? '').trim();
  return (
    label: model.isNotEmpty ? prettyModel(model) : prettyProfile(k),
    provider: (p?.provider ?? '').isNotEmpty ? p!.provider : k,
  );
}

String prettyModel(String raw) {
  var m = raw.trim();
  if (m.isEmpty) return '';
  if (m.contains('/')) m = m.split('/').last;
  // Strip trailing date stamps like -20250929.
  m = m.replaceFirst(RegExp(r'-20\d{6}$'), '');
  final claude = RegExp(r'^claude-(opus|sonnet|haiku)-(\d+)-(\d+)(?:-(.+))?$',
          caseSensitive: false)
      .firstMatch(m);
  if (claude != null) {
    final fam = claude.group(1)!;
    final cap = '${fam[0].toUpperCase()}${fam.substring(1).toLowerCase()}';
    return '$cap ${claude.group(2)}.${claude.group(3)}';
  }
  return prettyProfile(m);
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
// Coordination envelopes: XML with attributes and child elements.
// ---------------------------------------------------------------------------

class CoordinationEnvelope {
  const CoordinationEnvelope(this.tag, this.text);
  final String tag;
  final String text;

  String field(String name) => envelopeField(text, name);
}

CoordinationEnvelope? parseCoordinationEnvelope(String body) {
  final t = body.trim();
  final tag = envelopeKind(t);
  if (tag == null) return null;
  return CoordinationEnvelope(tag, t);
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
    case 'lead_task':
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
  }
  final what = env.tag.replaceAll('_', ' ');
  return EnvelopeSignal('message', SignalTone.neutral, '$who sent a $what',
      sub: _firstLine(env.field('body').isNotEmpty
          ? env.field('body')
          : env.field('title')));
}

/// The full text behind a signal row, in a sheet.
bool _looksCodeOrError(String title, String body) {
  final t = title.toLowerCase();
  if (t.contains('error') || t.contains('stderr') || t.contains('trace')) {
    return true;
  }
  final b = body.trimLeft();
  return b.startsWith('{') || b.startsWith('[') || b.contains('\n#0 ');
}

Future<void> showSignalDetails(BuildContext context,
    {required String title, required String body, Offset? point}) {
  final isCode = _looksCodeOrError(title, body);
  final textStyle = isCode
      ? codeMono(kMobile ? 13 : 12.5, height: 1.55, color: AppColors.fg2)
      : sans(kMobile ? 14 : 13.5, height: 1.6, color: AppColors.fg2);

  void copy(BuildContext ctx) {
    Clipboard.setData(ClipboardData(text: body));
    toast(ctx, 'Copied');
  }

  if (!kMobile) {
    return showPointPopover<void>(
      context,
      point: point ?? lastPointerDown,
      width: 460,
      maxHeight: 380,
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s6, S.s8),
              child: Row(children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, weight: W.label, color: AppColors.fg1)),
                ),
                if (body.trim().isNotEmpty)
                  IconBtn('clipboard',
                      size: 26,
                      iconSize: 13,
                      tooltip: 'Copy',
                      onTap: () => copy(ctx)),
                IconBtn('x',
                    size: 26,
                    iconSize: 13,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(ctx).pop()),
              ]),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.line),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(S.s12),
                child: SelectableText(body, style: textStyle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  return showAppSheet<void>(
    context,
    title: title,
    maxWidth: 640,
    maxHeight: 580,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(body, style: textStyle),
        if (body.trim().isNotEmpty) ...[
          SizedBox(height: S.s16),
          Align(
            alignment: Alignment.centerRight,
            child: Builder(
              builder: (ctx) => Btn('Copy',
                  icon: 'clipboard',
                  small: true,
                  variant: BtnVariant.surface,
                  onTap: () => copy(ctx)),
            ),
          ),
        ],
      ],
    ),
  );
}
