import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';

/// Horizontal game row for portrait lobbies. Fills the height it is given.
class PortraitGameRow extends StatelessWidget {
  const PortraitGameRow({
    super.key,
    required this.color,
    required this.title,
    required this.art,
    required this.playLabel,
    required this.onPlay,
    this.subtitle,
  });

  final Color color;
  final String title;
  final String? subtitle;
  final Widget art;
  final String playLabel;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onPlay,
      scale: 0.98,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.lerp(color, const Color(0xFF070A14), 0.35)!,
              const Color(0xFF0A0E1C),
              const Color(0xFF070910),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Row(
            children: [
              AspectRatio(aspectRatio: 1, child: art),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(
                        15,
                        color: Colors.white,
                        weight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label(
                          10,
                          color: Colors.white70,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DuelButton(
                  label: playLabel,
                  color: color,
                  width: 88,
                  height: 32,
                  fontSize: 11,
                  onPressed: onPlay,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact shortcut used beside the game list on the portrait home screen.
class PortraitFeatureTile extends StatelessWidget {
  const PortraitFeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.accent,
    required this.onTap,
    this.subtitle,
    this.badge = false,
    this.attention = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final VoidCallback? onTap;
  final bool badge;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      scale: 0.97,
      child: DecoratedBox(
        decoration: duelPanel(
          radius: 14,
          rim: accent.withValues(alpha: 0.65),
          fill: const Color(0xCC0B0E1C),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IdleAttentionScale(
                    active: attention,
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppText.label(
                      10,
                      color: accent,
                      weight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppText.label(
                        9,
                        color: DuelColors.dim,
                        weight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            if (badge)
              const Positioned(
                right: 6,
                top: 6,
                child: PulseBadge(
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: DuelColors.red,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
