import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';

/// Shared chrome for the menu screens in the Pool City look: purple title
/// bar, the content on the translucent panel (scrolling), red BACK.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = DesignAuth.pageFrameMaxWidth,
    this.action,
  });

  final String title;
  final Widget child;

  /// Kept for callers; the portrait panel already bounds the width.
  final double maxWidth;

  /// Primary action kept at the top of the panel so it never scrolls out of view.
  final Widget? action;

  @override
  Widget build(BuildContext context) => PcPage(
        title: title,
        scroll: action == null,
        body: action == null
            ? child
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerRight, child: action),
                  const SizedBox(height: 16),
                  Expanded(child: SingleChildScrollView(child: child)),
                ],
              ),
      );
}

/// Titled block inside a page ("Sound & Vibration"): heading with a rule,
/// then the content.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.compact = false, this.legacy = false});

  final String title;
  final Widget child;
  final bool compact;

  /// The child is laid out in phone logical pixels: magnify it to the canvas.
  final bool legacy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: compact ? 24 : 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PcSectionTitle(title),
            SizedBox(height: compact ? 14 : 20),
            if (legacy)
              PcLegacyScale(child: child)
            else
              DefaultTextStyle.merge(
                style: pcText(30, color: const Color(0xFFE6E2FF), weight: FontWeight.w500, shadow: false).copyWith(height: 1.4),
                child: child,
              ),
          ],
        ),
      );
}

/// Segmented choice used across lobby and settings (the reference's ON / OFF rows).
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.dense = false,
    this.mini = false,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  /// Sized for content inside a [PcLegacyScale] (phone logical pixels).
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final h = mini ? 36.0 : (dense ? 76.0 : 96.0);
    final fs = mini ? 15.0 : (dense ? 30.0 : 38.0);
    // Up to four options share one segmented bar; longer lists wrap into rows of three.
    if (options.length <= 4) {
      return PcSegmented<T>(options: options, value: value, onChanged: onChanged, height: h, fontSize: fs);
    }
    final entries = options.entries.toList();
    return Column(
      children: [
        for (var i = 0; i < entries.length; i += 3)
          Padding(
            padding: EdgeInsets.only(bottom: i + 3 < entries.length ? 12 : 0),
            child: PcSegmented<T>(
              options: {for (final e in entries.sublist(i, (i + 3).clamp(0, entries.length))) e.key: e.value},
              value: value,
              onChanged: onChanged,
              height: h,
              fontSize: fs,
            ),
          ),
      ],
    );
  }
}
