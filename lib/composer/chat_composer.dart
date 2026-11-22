import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ambient/live_caption.dart';
import '../motion.dart';
import '../platform.dart';
import '../theme.dart';
import 'composer_card.dart';
import 'voice_note.dart';

const double kDesktopComposerWidth = 960;

/// The one composer for session chats, agent threads and group threads, on
/// phone and desktop: field, attach, voice note, send and stop, docked with
/// the same spacing everywhere. Screens pass their own extras as slots.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.input,
    required this.focus,
    required this.hint,
    required this.voice,
    required this.onSend,
    required this.canSend,
    required this.hasDraft,
    this.listen,
    required this.onAttach,
    this.attach,
    this.onStop,
    this.onSteer,
    this.running = false,
    this.sending = false,
    this.recipient = '',
    this.onRecordMore,
    this.above = const [],
    this.attachments,
    this.banner,
    this.fieldKey,
    this.cardKey,
    this.shortcuts,
    this.fieldWrapper,
    this.contentInsertion,
    this.trailing,
    this.deskModel,
    this.deskCold,
    this.deskHint,
    this.highlight = false,
    this.attentionExclude,
    this.besideCard,
    this.hintColor,
  });

  final TextEditingController input;
  final FocusNode focus;
  final String hint;
  final VoiceNoteController voice;
  final VoidCallback onSend;

  /// Whether Send would send now; [hasDraft] is text or attachments typed.
  /// Read on every rebuild, which [input], [voice] and [listen] trigger.
  final ValueGetter<bool> canSend;
  final ValueGetter<bool> hasDraft;
  final Listenable? listen;

  /// Default attach button action; [attach] replaces the phone button.
  final VoidCallback onAttach;
  final Widget? attach;

  /// Stop is offered while [running]; [onSteer] is the long-press send.
  final VoidCallback? onStop;
  final VoidCallback? onSteer;
  final bool running;
  final bool sending;

  /// Who a voice note is for, named on the desktop recorder.
  final String recipient;

  /// Attach this take and record another; defaults to the controller's own.
  final VoidCallback? onRecordMore;

  /// Rows stacked above the attachments and card: tray, dock, queue, mentions.
  final List<Widget> above;
  final Widget? Function()? attachments;
  final Widget? banner;
  final Key? fieldKey;
  final Key? cardKey;
  final Map<ShortcutActivator, VoidCallback>? shortcuts;

  /// Wraps the desktop field, for slash-menu keys.
  final Widget Function(Widget field)? fieldWrapper;
  final ContentInsertionConfiguration? contentInsertion;
  final Widget Function(bool compact)? trailing;
  final Widget? deskModel;
  final Widget? deskCold;
  final Widget? Function()? deskHint;
  final bool highlight;
  final String? attentionExclude;

  /// Optional control anchored beside the composer pill.
  final Widget? besideCard;
  final Color? hintColor;

  Map<ShortcutActivator, VoidCallback> get _bindings =>
      shortcuts ??
      {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!kMobile && canSend()) onSend();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): onSend,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): onSend,
      };

  void _submit() {
    if (canSend()) onSend();
  }

  Widget _phoneCard() => ComposerCard(
        highlight: highlight,
        text: input,
        banner: banner,
        field: CallbackShortcuts(
          bindings: _bindings,
          child: TextField(
            key: fieldKey,
            controller: input,
            focusNode: focus,
            contentInsertionConfiguration: contentInsertion,
            minLines: 1,
            maxLines: 8,
            cursorColor: AppColors.accent,
            onSubmitted: (_) => _submit(),
            style: ComposerCard.fieldStyle,
            // A fixed strut keeps the line box the same for hint and text, so
            // Geist's ascent never nudges the baseline off the icons' centre.
            strutStyle: StrutStyle(
                fontSize: C7.field,
                height: 22 / C7.field,
                forceStrutHeight: true,
                leading: 0),
            textAlignVertical: TextAlignVertical.center,
            decoration: ComposerCard.decoration(hint,
                style: ComposerCard.fieldStyle, hintColor: hintColor),
          ),
        ),
        attach: attach ??
            ComposerIconButton('plus', tooltip: 'Attach', onTap: onAttach),
        trailing: trailing,
        send: _phoneAction(),
      );

  /// One button that is mic, send or stop, with a bare mic beside stop so
  /// voice stays one tap away while the agent runs.
  Widget _phoneAction() {
    final action = hasDraft()
        ? ComposerAction.send
        : running && onStop != null
            ? ComposerAction.stop
            : kCanRecord
                ? ComposerAction.mic
                : ComposerAction.send;
    void mic() => unawaited(voice.toggleRecording());
    final morph = ComposerMorphButton(
      action: action,
      enabled: action != ComposerAction.send || canSend(),
      busy: sending,
      onTap: switch (action) {
        ComposerAction.stop => onStop,
        ComposerAction.mic => mic,
        ComposerAction.send => canSend() ? onSend : null,
      },
      onLongPress: running && canSend() ? onSteer : null,
    );
    if (action != ComposerAction.stop || !kCanRecord) return morph;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ComposerBareButton('mic', label: 'Record', onTap: mic),
      const SizedBox(width: 4),
      morph,
    ]);
  }

  Widget _deskCard() {
    Widget field = TextField(
      controller: input,
      focusNode: focus,
      contentInsertionConfiguration: contentInsertion,
      minLines: 1,
      maxLines: 10,
      cursorColor: AppColors.fg1,
      onSubmitted: (_) => _submit(),
      style: DeskComposerCard.fieldStyle,
      decoration: DeskComposerCard.decoration(hint),
    );
    if (fieldWrapper != null) field = fieldWrapper!(field);
    return DeskComposerCard(
      attentionExclude: attentionExclude,
      highlight: highlight,
      focus: focus,
      banner: banner,
      field: CallbackShortcuts(bindings: _bindings, child: field),
      attach: DeskIconButton('plus',
          tooltip: 'Attach', onTap: onAttach, iconSize: 16, color: AppColors.fg2),
      model: deskModel,
      cold: deskCold,
      hint: deskHint?.call(),
      mic: kCanRecord
          ? DeskIconButton('mic',
              tooltip: 'Record',
              onTap: () => unawaited(voice.toggleRecording()))
          : null,
      action: _deskAction(),
    );
  }

  Widget _deskAction() {
    final send = DeskActionButton(
      icon: 'arrow-up',
      tooltip: 'Send',
      on: canSend(),
      busy: sending,
      onTap: canSend() ? onSend : null,
    );
    if (!running || onStop == null) return send;
    final stop = DeskActionButton(
        icon: 'stop', tooltip: 'Stop', soft: true, onTap: onStop);
    if (!hasDraft()) return stop;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      stop,
      const SizedBox(width: 6),
      send,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    return AnimatedPadding(
      duration: Motion.fast,
      curve: Motion.enter,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          // The gutter sits outside the column so it lines up with the rows.
          constraints: BoxConstraints(
              maxWidth: kMobile
                  ? double.infinity
                  : kDesktopComposerWidth + 2 * S.s20),
          child: LiveCaptionAnchor(
            padding: EdgeInsets.fromLTRB(
                kMobile ? M.gutter : S.s20,
                S.s8,
                kMobile ? M.gutter : S.s20,
                kMobile
                    ? S.of(10) + (keyboard > 0 ? S.s8 : mq.padding.bottom)
                    : 18),
            child: ListenableBuilder(
              listenable: Listenable.merge([voice, input, listen]),
              builder: (context, _) {
                final recording = voice.isActive;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...above,
                    // Attachments sit above the composer, never inside it.
                    if (attachments?.call() case final bar?) bar,
                    Swap(
                      stateKey: recording ? 'recorder' : 'composer',
                      alignment: Alignment.bottomCenter,
                      child: recording
                          ? VoiceNoteRecorderStrip(
                              controller: voice,
                              sending: sending,
                              recipient: recipient,
                              onSend: onSend,
                              onMore: onRecordMore ?? () => unawaited(voice.recordMore()),
                            )
                          : besideCard != null
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    besideCard!,
                                    SizedBox(width: S.s8),
                                    Expanded(
                                      child: KeyedSubtree(
                                        key: cardKey,
                                        child: kMobile
                                            ? _phoneCard()
                                            : _deskCard(),
                                      ),
                                    ),
                                  ],
                                )
                              : KeyedSubtree(
                                  key: cardKey,
                                  child: kMobile ? _phoneCard() : _deskCard()),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
