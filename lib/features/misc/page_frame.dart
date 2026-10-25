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
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
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
  const SectionCard({super.key, required this.title, required this.child, this.compact = false});

  final String title;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 8 : 14),
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, compact ? 8 : 12, compact ? 12 : 16, compact ? 8 : 12),
      decoration: panelDecoration(radius: compact ? 12 : 16).copyWith(
        boxShadow: compact
            ? const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: compact ? 12 : 14,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Text(title, style: AppText.label(compact ? 11 : 13, color: AppColors.gold, weight: FontWeight.w800)),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
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
    this.dense = false,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: dense ? 5 : 8,
      runSpacing: dense ? 5 : 8,
      children: [
        for (final e in options.entries)
          GestureDetector(
            onTap: () => onChanged(e.key),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 16, vertical: dense ? 5 : 10),
              decoration: BoxDecoration(
                color: e.key == value ? AppColors.active : AppColors.backgroundAlt,
                borderRadius: BorderRadius.circular(dense ? 8 : 12),
                border: Border.all(color: e.key == value ? AppColors.active : AppColors.frame, width: dense ? 1.5 : 2),
              ),
              child: Text(
                e.value,
                style: AppText.label(dense ? 11 : 13, color: e.key == value ? Colors.black : AppColors.text),
              ),
            ),
          ),
      ],
    );
  }
}
