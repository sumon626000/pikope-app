import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../l10n/strings.dart';

/// In-match chat sheet: custom text, phrase chips, emoji chips.
/// Uses root [showDialog] (not [showDuelDialog]) so the keyboard does not
/// break [MediaQuery] while typing.
Future<void> showMatchChatDialog({
  required BuildContext context,
  required AppStrings t,
  required int maxCustomLength,
  required List<String> phrases,
  required List<String> emojis,
  required void Function(int catalogIndex) onPreset,
  required void Function(String text) onCustom,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierColor: const Color(0xAA000000),
    barrierDismissible: true,
    builder: (dialogContext) => _MatchChatDialog(
      t: t,
      maxCustomLength: maxCustomLength,
      phrases: phrases,
      emojis: emojis,
      onPreset: onPreset,
      onCustom: onCustom,
    ),
  );
}

class _MatchChatDialog extends StatefulWidget {
  const _MatchChatDialog({
    required this.t,
    required this.maxCustomLength,
    required this.phrases,
    required this.emojis,
    required this.onPreset,
    required this.onCustom,
  });

  final AppStrings t;
  final int maxCustomLength;
  final List<String> phrases;
  final List<String> emojis;
  final void Function(int catalogIndex) onPreset;
  final void Function(String text) onCustom;

  @override
  State<_MatchChatDialog> createState() => _MatchChatDialogState();
}

class _MatchChatDialogState extends State<_MatchChatDialog> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  void _send() {
    AudioService.tap();
    widget.onCustom(_controller.text);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = mq.padding;
    final maxW = mq.size.width - inset.horizontal - 16;
    final maxH = mq.size.height - inset.vertical - mq.viewInsets.vertical - 8;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.fromLTRB(
        8 + inset.left,
        8 + inset.top,
        8 + inset.right,
        8 + inset.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(480, maxW),
          maxHeight: math.max(200, maxH),
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: duelPanel(rim: DuelColors.rimLight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.t.ludoChatTitle,
                    style: AppText.label(18, weight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    focusNode: _focus,
                    maxLength: widget.maxCustomLength,
                    style: AppText.label(16, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: widget.t.ludoChatHint,
                      hintStyle: AppText.label(14, color: DuelColors.dim),
                      counterStyle: AppText.label(11, color: DuelColors.dim),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DuelButton(
                          label: widget.t.ludoChatSend,
                          height: 44,
                          color: DuelColors.gold,
                          onPressed: _send,
                        ),
                      ),
                      const SizedBox(width: 10),
                      DuelButton(
                        label: widget.t.close,
                        width: 110,
                        height: 44,
                        color: DuelColors.rimLight,
                        onPressed: _close,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.t.ludoChatPhrases,
                    style: AppText.label(13, color: DuelColors.dim, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < widget.phrases.length; i++)
                        _PhraseChip(
                          label: widget.phrases[i],
                          onTap: () {
                            AudioService.tap();
                            widget.onPreset(i);
                            _close();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.t.ludoChatEmojis,
                    style: AppText.label(13, color: DuelColors.dim, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < widget.emojis.length; i++)
                        _EmojiChip(
                          emoji: widget.emojis[i],
                          onTap: () {
                            AudioService.tap();
                            widget.onPreset(widget.phrases.length + i);
                            _close();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhraseChip extends StatelessWidget {
  const _PhraseChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: duelPanel(radius: 12, rim: DuelColors.rim),
        child: Text(
          label,
          style: AppText.label(13, color: DuelColors.silver, weight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _EmojiChip extends StatelessWidget {
  const _EmojiChip({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: duelPanel(radius: 12, rim: DuelColors.rim),
        child: Text(emoji, style: const TextStyle(fontSize: 26, height: 1)),
      ),
    );
  }
}
