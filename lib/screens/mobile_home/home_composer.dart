import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../composer/chat_composer.dart';
import '../../composer/composer_attachments.dart';
import '../../composer/composer_card.dart' show ComposerIconButton;
import '../../composer/voice_note.dart';
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
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;
  final String hint;

  /// "+" is new session, agent or group; the anchor is the button's context.
  final void Function(BuildContext anchor) onPlus;
  final VoidCallback? onSent;

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
  void dispose() {
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

  @override
  Widget build(BuildContext context) => ChatComposer(
        input: _input,
        focus: _focus,
        hint: widget.hint,
        voice: _voice,
        listen: _attachments,
        recipient: widget.agentName,
        attachments: () =>
            _attachments.isNotEmpty ? _attachments.buildBar(context) : null,
        attach: Builder(
          builder: (ctx) => ComposerIconButton('plus',
              tooltip: 'New session, agent or group',
              onTap: () => widget.onPlus(ctx)),
        ),
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
