import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../core/icon_motion.dart';
import '../../core/widgets.dart';
import '../misc/leaderboard_screen.dart';
import '../misc/settings_screen.dart';
import '../online/session.dart';
import '../online/notification_unread.dart';
import 'items_screen.dart';
import 'notifications_screen.dart';
import 'notices_screen.dart';
import 'shop_screen.dart';
import '../../l10n/strings.dart';
import '../start/auth_prompt.dart';

void pushScreen(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

/// Logo, player, wallet and shortcuts across the top of a lobby screen.
class DuelTopBar extends ConsumerWidget {
  const DuelTopBar({
    super.key,
    this.showProfile = true,
    this.showShortcuts = true,
  });

  final bool showProfile;
  final bool showShortcuts;

  Future<void> _walletTap(BuildContext context, WidgetRef ref) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (context.mounted) pushScreen(context, const ShopScreen());
  }

  Future<void> _profileTap(BuildContext context, WidgetRef ref) async {
    if (!await requireRegisteredAccount(context, ref)) return;
    if (context.mounted) pushScreen(context, const SettingsScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final unread = ref.watch(notificationUnreadProvider);
    final registered = hasRegisteredAccount(ref);
    final coins = lobbyDisplayCoins(ref);
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
                _profileTap(context, ref);
              },
              child: Row(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: registered
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFFE08A),
                                Color(0xFF5C8BFF),
                                Color(0xFFFF3B4E),
                              ],
                            )
                          : null,
                      color: registered ? null : const Color(0xFF1A2140),
                      border: registered ? null : Border.all(color: DuelColors.rimLight, width: 2),
                      boxShadow: registered
                          ? const [
                              BoxShadow(
                                color: Color(0x663B6CFF),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: Color(0x99000000),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: ClipOval(
                      child: registered
                          ? AvatarImage(settings.avatar, size: 76)
                          : const Icon(Icons.person_rounded, color: DuelColors.silver, size: 44),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 300,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          registered ? settings.name.toUpperCase() : t.browseProfileTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(
                            20,
                            color: DuelColors.silver,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (registered)
                          Row(
                            children: [
                              Text(
                                t.lvDot(session.level),
                                style: AppText.label(
                                  13,
                                  color: DuelColors.silver,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF151A36),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0xFF2B3566),
                                    ),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: (session.levelProgress / 100)
                                        .clamp(0.02, 1.0),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(5),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF9BF26E),
                                            Color(0xFF2FBF2A),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: DuelColors.green.withValues(
                                              alpha: 0.7,
                                            ),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${session.levelProgress}%',
                                style: AppText.label(
                                  12,
                                  color: DuelColors.silver,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            t.browseProfileSub,
                            style: AppText.label(13, color: DuelColors.dim),
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
            amount: coins,
            placeholderLabel: t.signUpOrLogin,
            onAdd: () {
              AudioService.tap();
              _walletTap(context, ref);
            },
          ),
          if (showShortcuts) ...[
            const SizedBox(width: 44),
            _TopIcon(Icons.mail_rounded, () async {
              if (!await requireRegisteredAccount(context, ref)) return;
              if (context.mounted) pushScreen(context, const NoticesScreen());
            }),
            _TopIcon(Icons.notifications_rounded, () async {
              if (!await requireRegisteredAccount(context, ref)) return;
              if (context.mounted) {
                pushScreen(context, const NotificationsScreen());
              }
            }, badge: unread),
            _TopIcon(
              Icons.settings_rounded,
              () => _profileTap(context, ref),
            ),
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
    badgeWidget = PulseBadge(
      minScale: 0.92,
      maxScale: 1.06,
      child: badgeWidget,
    );

    return PressScale(
      onTap: onTap,
      scale: 0.9,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: DuelColors.silver, size: 50),
            if (badge > 0) Positioned(right: -4, top: -2, child: badgeWidget),
          ],
        ),
      ),
    );
  }
}

/// Page frame of the secondary lobby screens (shop, cues, history ...) in
/// the Pool City look: player header, purple title bar, the content on the
/// translucent panel, red BACK bottom-left. [expanded], [sideBack] and
/// [contentTop] are kept for callers from the landscape layout; the portrait
/// page has one layout.
class DuelPage extends ConsumerWidget {
  const DuelPage({
    super.key,
    required this.title,
    required this.child,
    this.sub,
    this.expanded = false,
    this.sideBack = false,
    this.contentTop,
    this.scroll = false,
    this.nav,
    this.legacyScale,
    this.onBack,
  });

  /// Replaces the back button's default pop.
  final VoidCallback? onBack;

  /// The body is laid out in the old small units: magnify it by this factor.
  final double? legacyScale;
  final String title;
  final String? sub;
  final Widget child;
  final bool expanded;
  final bool sideBack;
  final double? contentTop;

  /// Let the page scroll the body (bodies that are not scrollables themselves).
  final bool scroll;

  /// Bottom tab bar instead of the back button (shop / inventory tabs).
  final List<HomeNavItem>? nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final registered = hasRegisteredAccount(ref);
    final child = legacyScale == null ? this.child : PcLegacyScale(factor: legacyScale!, child: this.child);
    return PcPage(
      header: PcHeader(
        avatar: settings.avatar,
        name: settings.name,
        registered: registered,
        level: session.level,
        coins: lobbyDisplayCoins(ref),
        gems: registered ? session.gems : null,
        placeholder: t.signUpOrLogin,
        onProfile: () async {
          AudioService.tap();
          if (!await requireRegisteredAccount(context, ref)) return;
          if (context.mounted) pushScreen(context, const SettingsScreen());
        },
        onWallet: () async {
          AudioService.tap();
          if (!await requireRegisteredAccount(context, ref)) return;
          if (context.mounted) pushScreen(context, const ShopScreen());
        },
      ),
      title: title,
      scroll: scroll,
      nav: nav,
      onBack: onBack,
      body: sub == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(sub!, textAlign: TextAlign.center, style: pcText(28, color: DesignColors.pcTextDim, weight: FontWeight.w500)),
                const SizedBox(height: 16),
                scroll ? child : Expanded(child: child),
              ],
            ),
    );
  }
}

/// Convenience: the five-tab bar for pages that are tabs in the reference
/// (Shop, Inventory, Practice). Tapping another tab replaces this page.
List<HomeNavItem> duelTabNav(BuildContext context, WidgetRef ref, {required int active}) {
  final t = ref.read(stringsProvider);
  void go(Widget screen) => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => screen));
  return [
    HomeNavItem(icon: Icons.smart_toy_rounded, label: t.practice, active: active == 0, onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
    HomeNavItem(icon: Icons.leaderboard_rounded, label: t.navRankings, active: active == 1, onTap: () => go(const LeaderboardScreen())),
    HomeNavItem(icon: Icons.home_rounded, label: t.navHome, active: false, onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
    HomeNavItem(icon: Icons.backpack_rounded, label: t.navItems, active: active == 3, onTap: () => go(const ItemsScreen())),
    HomeNavItem(icon: Icons.shopping_cart_rounded, label: t.navShop, active: active == 4, onTap: () => go(const ShopScreen())),
  ];
}
