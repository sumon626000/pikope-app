import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';
import '../../core/widgets.dart';
import '../misc/settings_screen.dart';
import '../online/session.dart';
import '../online/notification_unread.dart';
import 'notifications_screen.dart';
import 'notices_screen.dart';
import 'shop_screen.dart';
import '../../l10n/strings.dart';

void pushScreen(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

/// Logo, player, wallet and shortcuts across the top of a lobby screen.
class DuelTopBar extends ConsumerWidget {
  const DuelTopBar({super.key, this.showProfile = true, this.showShortcuts = true});

  final bool showProfile;
  final bool showShortcuts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final unread = ref.watch(notificationUnreadProvider);
    return SizedBox(
      height: 112,
      child: Row(
        children: [
          const SizedBox(width: 42),
          const DuelLogo(),
          const SizedBox(width: 38),
          if (showProfile)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AudioService.tap();
                pushScreen(context, const SettingsScreen());
              },
              child: Row(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE08A), Color(0xFF5C8BFF), Color(0xFFFF3B4E)]),
                      boxShadow: [BoxShadow(color: Color(0x663B6CFF), blurRadius: 18, spreadRadius: 1), BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 4))],
                    ),
                    child: ClipOval(child: AvatarImage(settings.avatar, size: 76)),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 300,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(settings.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label(20, color: DuelColors.silver, weight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(t.lvDot(session.level), style: AppText.label(13, color: DuelColors.silver)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                height: 9,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF151A36),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: const Color(0xFF2B3566)),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: (session.levelProgress / 100).clamp(0.02, 1.0),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      gradient: const LinearGradient(colors: [Color(0xFF9BF26E), Color(0xFF2FBF2A)]),
                                      boxShadow: [BoxShadow(color: DuelColors.green.withValues(alpha: 0.7), blurRadius: 8)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('${session.levelProgress}%', style: AppText.label(12, color: DuelColors.silver)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          CurrencyPill(
            icon: const PikoCoinIcon(size: 76),
            amount: settings.coins,
            onAdd: () => pushScreen(context, const ShopScreen()),
          ),
          if (showShortcuts) ...[
            const SizedBox(width: 44),
            _TopIcon(Icons.mail_rounded, () => pushScreen(context, const NoticesScreen())),
            _TopIcon(Icons.notifications_rounded, () => pushScreen(context, const NotificationsScreen()), badge: unread),
            _TopIcon(Icons.settings_rounded, () => pushScreen(context, const SettingsScreen())),
          ],
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon(this.icon, this.onTap, {this.badge = 0});

  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    Widget badgeWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: DuelColors.red,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black54),
      ),
      child: Text(
        badge > 99 ? '99+' : '$badge',
        style: AppText.label(11, color: Colors.white, weight: FontWeight.w900),
      ),
    );
    badgeWidget = PulseBadge(minScale: 0.92, maxScale: 1.06, child: badgeWidget);

    return PressScale(
      onTap: onTap,
      scale: 0.9,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: DuelColors.silver, size: 50),
            if (badge > 0)
              Positioned(
                right: -4,
                top: -2,
                child: badgeWidget,
              ),
          ],
        ),
      ),
    );
  }
}

/// Page frame of the secondary lobby screens (shop, cues, history ...):
/// top bar, a title, the content, and BACK in the corner.
class DuelPage extends ConsumerWidget {
  const DuelPage({super.key, required this.title, required this.child, this.sub, this.expanded = false, this.sideBack = false});

  final String title;
  final String? sub;
  final Widget child;

  /// Use almost the full canvas (shop add-cash / redeem).
  final bool expanded;

  /// BACK sits on the left side, clear of the shop cards.
  final bool sideBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return DuelCanvas(
        child: Stack(
          children: [
            const Positioned(left: 0, right: 0, top: 6, child: DuelTopBar(showProfile: false, showShortcuts: false)),
            Positioned(left: 0, right: 0, top: 118, child: Center(child: DuelTitle(title, size: 44, sub: sub))),
            Positioned(
              left: sideBack ? 188 : (expanded ? 36 : 210),
              right: expanded ? 36 : 60,
              top: expanded ? 188 : 226,
              bottom: expanded ? 24 : 40,
              child: child,
            ),
            if (sideBack)
              Positioned(
                left: 28,
                top: 210,
                child: NavTile(icon: Icons.reply_rounded, label: t.navBack, onTap: () => Navigator.of(context).pop()),
              )
            else
              Positioned(
                left: 42,
                bottom: 34,
                child: NavTile(icon: Icons.reply_rounded, label: t.navBack, onTap: () => Navigator.of(context).pop()),
              ),
          ],
        ),
      );
  }
}
