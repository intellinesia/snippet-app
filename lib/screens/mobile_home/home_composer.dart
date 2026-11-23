import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../composer/chat_composer.dart';
import '../../composer/composer_attachments.dart';
import '../../composer/composer_card.dart' show ComposerIconButton;
import '../../composer/voice_note.dart';
import '../../drafts.dart';
import '../../mochi.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// The shared floating composer on the phone home and the managed view. It
/// sends to one agent; [onSent] fires after the message is accepted.
class HomeComposer extends StatefulWidget {
  const HomeComposer({
    super.key,
    required this.client,
    required this.agentId,
    required this.agentName,
    required this.hint,
    required this.onPlus,
    this.onSent,
    this.onOpenChat,
    this.openOnFocus = false,
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;
  final String hint;

  /// "+" is new session, agent or group; the anchor is the button's context.
  final void Function(BuildContext anchor) onPlus;
  final VoidCallback? onSent;

  /// Opens the target agent's chat directly without sending a message.
  final VoidCallback? onOpenChat;

  /// Tapping the field opens the chat instead of typing here, so the thread
  /// (with its keyboard and Back) is where the message gets written.
  final bool openOnFocus;

  @override
  State<HomeComposer> createState() => _HomeComposerState();
}

class _HomeComposerState extends State<HomeComposer> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  late final ComposerAttachmentController _attachments =
      ComposerAttachmentController(
    client: widget.client,
    onToast: (msg, {bool danger = false}) {
      if (mounted) toast(context, msg, danger: danger);
    },
  );

  late final VoiceNoteController _voice = VoiceNoteController(
    client: widget.client,
    filePrefix: 'snippet-home-voice',
    onToast: (msg, {bool danger = false}) {
      if (mounted) toast(context, msg, danger: danger);
    },
    onConfirmTake: (bytes, name) => _attachments.ingest([
      (name: name, localPath: null, readBytes: () async => bytes)
    ], upload: _voice.uploadTake),
  );

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (!widget.openOnFocus || !_focus.hasFocus) return;
    _focus.unfocus();
    _openChat();
  }

  /// Hands any typed text to the thread's composer as its draft.
  void _openChat() {
    final open = widget.onOpenChat;
    if (open == null) return;
    final text = _input.text;
    if (widget.agentId == 'lead' && text.trim().isNotEmpty) {
      Drafts.instance.save(
          Drafts.keyFor(widget.client.baseUrl, 'lead'),
          Draft(text: text));
      _input.clear();
    }
    open();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _input.dispose();
    _focus.dispose();
    _attachments.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_voice.isRecording) await _voice.stop();
    if (_voice.hasTake) {
      if (!await _voice.confirmTake((bytes, name) => _attachments.ingest([
            (name: name, localPath: null, readBytes: () async => bytes)
          ], upload: _voice.uploadTake))) {
        return;
      }
    }
    if (_attachments.isUploading) {
      if (mounted) toast(context, 'Please wait for attachments to upload');
      return;
    }
    final body = _attachments.appendMarkers(_input.text);
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.client.sendAgentMessage(
        toAgentId: widget.agentId,
        body: body,
        idempotencyKey: 'local-${DateTime.now().microsecondsSinceEpoch}',
      );
      _input.clear();
      _attachments.clear();
      unawaited(_voice.discard());
      widget.onSent?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget? _openButton() {
    final open = widget.onOpenChat;
    if (open == null) return null;
    final label = '${widget.agentName}, open chat';
    return Tooltip(
      message: widget.agentName,
      child: Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: TapDetector(
            key: ValueKey('home-open-${widget.agentId}'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tapHaptic();
              _openChat();
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: AgentMochi(widget.agentId, size: 30)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final openBtn = _openButton();
    final plus = Builder(
      builder: (ctx) => ComposerIconButton('plus',
          tooltip: 'New session, agent or group',
          onTap: () => widget.onPlus(ctx)),
    );
    return ChatComposer(
      input: _input,
      focus: _focus,
      hint: widget.hint,
      hintColor: AppColors.fg2,
      voice: _voice,
      listen: _attachments,
      recipient: widget.agentName,
      attachments: () => _attachments.isNotEmpty
          ? _attachments.buildBar(context,
              onInsertText: (t) => appendToInput(_input, t))
          : null,
      attach: openBtn == null
          ? plus
          : Row(mainAxisSize: MainAxisSize.min, children: [openBtn, plus]),
      onAttach: () => unawaited(_attachments.pickFromSheet(context)),
      sending: _sending,
      hasDraft: () => _input.text.trim().isNotEmpty || _attachments.isNotEmpty,
      canSend: () =>
          (_input.text.trim().isNotEmpty ||
              _attachments.isNotEmpty ||
              _voice.isActive) &&
          !_sending,
      onSend: () => unawaited(_send()),
    );
  }
}


