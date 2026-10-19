import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../l10n/strings.dart';
import 'page_frame.dart';

enum LegalDoc { privacy, terms, conditions }

class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(localizedContentProvider);
    final sections = switch (doc) {
      LegalDoc.privacy => content.privacySections,
      LegalDoc.terms => content.termsSections,
      LegalDoc.conditions => content.conditionsSections,
    };
    final title = switch (doc) {
      LegalDoc.privacy => content.legalTitle('privacy'),
      LegalDoc.terms => content.legalTitle('terms'),
      LegalDoc.conditions => content.legalTitle('conditions'),
    };
    return PageFrame(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(content.lastUpdated, style: AppText.label(12, color: AppColors.textDim)),
          const SizedBox(height: 16),
          for (var i = 0; i < sections.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sections[i], style: AppText.label(15, weight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    sections[i + 1],
                    style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.45, color: AppColors.text),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
