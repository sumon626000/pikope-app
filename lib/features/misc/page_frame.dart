import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';

/// Shared chrome for the menu screens: back button, title, scrolling body.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.child, this.maxWidth = 980, this.action});

  final String title;
  final Widget child;
  final double maxWidth;

  /// Primary action kept in the header so it never scrolls out of view.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DuelColors.ink,
      body: DuelBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title, style: AppText.label(20, weight: FontWeight.w900))),
                    ?action,
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: panelDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.label(13, color: AppColors.gold)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Segmented choice used across lobby and settings.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          GestureDetector(
            onTap: () => onChanged(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: e.key == value ? AppColors.active : AppColors.backgroundAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: e.key == value ? AppColors.active : AppColors.frame, width: 2),
              ),
              child: Text(e.value,
                  style: AppText.label(13, color: e.key == value ? Colors.black : AppColors.text)),
            ),
          ),
      ],
    );
  }
}
