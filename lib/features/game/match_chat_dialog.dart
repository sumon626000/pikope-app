import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../l10n/strings.dart';

/// In-match chat sheet: custom text, phrase chips, emoji chips.
void showMatchChatDialog({
  required BuildContext context,
  required AppStrings t,
  required int maxCustomLength,
  required List<String> phrases,
  required List<String> emojis,
  required void Function(int catalogIndex) onPreset,
  required void Function(String text) onCustom,
}) {
  final controller = TextEditingController();
  showDuelDialog<void>(
    context,
    barrierColor: const Color(0xAA000000),
    builder: (dialog) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(dialog).size.height * 0.88,
        ),
        padding: const EdgeInsets.all(18),
        decoration: duelPanel(rim: DuelColors.rimLight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.ludoChatTitle,
                style: AppText.label(18, weight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLength: maxCustomLength,
                style: AppText.label(16, color: Colors.white),
                decoration: InputDecoration(
                  hintText: t.ludoChatHint,
                  hintStyle: AppText.label(14, color: DuelColors.dim),
                  counterStyle: AppText.label(11, color: DuelColors.dim),
                ),
                onSubmitted: (v) {
                  AudioService.tap();
                  onCustom(v);
                  Navigator.of(dialog).pop();
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DuelButton(
                      label: t.ludoChatSend,
                      height: 44,
                      color: DuelColors.gold,
                      onPressed: () {
                        AudioService.tap();
                        onCustom(controller.text);
                        Navigator.of(dialog).pop();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  DuelButton(
                    label: t.close,
                    width: 110,
                    height: 44,
                    color: DuelColors.rimLight,
                    onPressed: () => Navigator.of(dialog).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                t.ludoChatPhrases,
                style: AppText.label(13, color: DuelColors.dim, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < phrases.length; i++)
                    _PhraseChip(
                      label: phrases[i],
                      onTap: () {
                        AudioService.tap();
                        Navigator.of(dialog).pop();
                        onPreset(i);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                t.ludoChatEmojis,
                style: AppText.label(13, color: DuelColors.dim, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < emojis.length; i++)
                    _EmojiChip(
                      emoji: emojis[i],
                      onTap: () {
                        AudioService.tap();
                        Navigator.of(dialog).pop();
                        onPreset(phrases.length + i);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(controller.dispose);
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
