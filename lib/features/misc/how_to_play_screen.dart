import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../l10n/strings.dart';
import 'page_frame.dart';

class HowToPlayScreen extends ConsumerWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final content = ref.watch(localizedContentProvider);
    return PageFrame(
      title: t.howToPlay,
      child: Column(
        children: [
          for (final s in content.howToPlaySections)
            SectionCard(
              title: s.$1,
              child: Text(
                s.$2,
                style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.45, color: AppColors.text),
              ),
            ),
        ],
      ),
    );
  }
}
